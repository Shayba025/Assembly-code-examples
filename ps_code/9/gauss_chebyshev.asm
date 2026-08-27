;;; ============================================================================
;;; gauss_chebyshev.asm -- numerical integration on the x87 FPU
;;; Practice session 9                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Approximates the integral of sin(x) from 0 to 1 using eight Chebyshev
;;;   nodes, prints the contribution of each node, and compares the answer with
;;;   the exact value 1 - cos(1) = 0.45969769413186028. The original header above
;;;   explains the mathematics properly; the notes here are about the CODE.
;;;
;;;   THE PROGRAM IS ALREADY WELL COMMENTED BY ITS AUTHOR -- unusually so. The
;;;   annotations added below fill in the lines that had none and explain the
;;;   instructions themselves; the "FPU stack trace" blocks the author wrote are
;;;   exactly the right way to document x87 and are worth imitating.
;;;
;;;   THE SHAPE OF THE COMPUTATION, so the loop reads easily:
;;;       once, before the loop:   half_ba = (b-a)/2,  midpoint = (a+b)/2,
;;;                                weight  = pi/N,     sum = 0
;;;       for i = 1 .. N:          angle    = (2i-1)*pi/(2N)
;;;                                x_i      = cos(angle)          the node
;;;                                w_factor = sqrt(1 - x_i^2)     the correction
;;;                                t_i      = half_ba*x_i + midpoint
;;;                                sum     += sin(t_i) * w_factor
;;;       finally:                 result = half_ba * weight * sum
;;;   Note that the three quantities that do not depend on i are computed ONCE,
;;;   before the loop -- the numerical equivalent of hoisting a loop invariant.
;;;
;;;   `fild` IS THE INSTRUCTION TO LEARN HERE. x87 cannot take an immediate and
;;;   cannot read a general register: to get the integer i onto the FPU stack you
;;;   must first store it to memory and then load it back:
;;;       mov  dword [i_int], r12d      ; integer register -> memory
;;;       fild dword [i_int]            ; memory -> FPU stack, converted
;;;   That is why .bss contains three little `resd 1` scratch slots that hold
;;;   nothing interesting. Memory is the only channel between the integer unit
;;;   and the FPU -- the same fact that arc.asm relies on in the other direction.
;;;   (The author's note about `fildl` is right: that spelling is AT&T/GAS
;;;   syntax and NASM rejects it.)
;;;
;;;   THREE FLOATING-POINT UNITS ARE IN PLAY, and it is worth naming them:
;;;       x87   does all the arithmetic (fcos, fsin, fsqrt, fdivp)
;;;       SSE   carries doubles to printf in xmm0..xmm3
;;;       the integer registers hold i, N and the loop control
;;;   Values move between them only through memory.
;;;
;;;   A CORRECTION TO THE AUTHOR'S ALIGNMENT NOTE. The comment at lines 113-117
;;;   says "entry_rsp was 16-aligned" and concludes that inside the callee rsp is
;;;   0 mod 16. Both halves are off by 8, though the CODE IS CORRECT. Measured:
;;;       at main's first instruction   rsp % 16 == 8   (call main pushed 8)
;;;       after the three pushes        rsp % 16 == 0   <- correct at a `call`
;;;       at printf's first instruction rsp % 16 == 8
;;;   The ABI's rule is "rsp is a multiple of 16 immediately BEFORE the call",
;;;   which is the same as "8 mod 16 at the callee's first instruction". So the
;;;   three pushes really do land it correctly and no `sub rsp, 8` is needed --
;;;   the reasoning written next to it just starts from the wrong premise. Check
;;;   it yourself with `break printf` then `p $rsp % 16`.
;;;
;;;   WHY THE ERROR IS ABOUT 1e-3 AND NOT 1e-15: Gauss-Chebyshev is exact for
;;;   integrands of the form f(x)/sqrt(1-x^2), and sin(t) with the sqrt factor
;;;   absorbed is not a polynomial. Raise N and the error falls -- which is what
;;;   the closing line of output invites you to try.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/9/gauss_chebyshev.asm"
;;;
;;;   Check the exact value:
;;;   python3 -c "import math; print('%.17f' % (1 - math.cos(1)))"
;;;
;;;   THE EXPERIMENT THE PROGRAM ASKS FOR: change `N equ 8` to 4, 16, 32 and
;;;   watch the error shrink. One line, and you have measured the convergence
;;;   rate of a quadrature rule.
;;;
;;;   Change the interval by editing `a` and `b`, and the integrand by replacing
;;;   the `fsin` in Step E.
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/9/gauss_chebyshev.asm"
;;;
;;;   Useful session -- follow one node all the way through:
;;;     break gauss_chebyshev.asm:NN     NN on the `fcos` line in Step B
;;;     c
;;;     p $st0                    the angle, in radians
;;;     si
;;;     p $st0                    x_i = cos(angle)
;;;     p (double)node_x          ...after the fstp, in memory
;;;     p (double)w_factor        sqrt(1 - x_i^2)
;;;     p (double)node_t          the transformed node
;;;     p (double)sum_fw          the running sum
;;;     c                         next node
;;;
;;;   Watch the integer-to-float bridge, which is the point of `fild`:
;;;     break gauss_chebyshev.asm:NN     NN on the `mov dword [i_int], r12d` line
;;;     c
;;;     p $r12d                   i, in an integer register
;;;     si
;;;     x/1dw &i_int              ...now in memory
;;;     info float                the FPU stack is still empty
;;;     si                        fild
;;;     p $st0                    ...and now on the FPU stack, as a float
;;;
;;;   Confirm the FPU stack is empty at every step boundary:
;;;     break printf
;;;     c
;;;     info float                empty, every single time
;;;
;;;   And check the alignment claim for yourself:
;;;     break main
;;;     c
;;;     p $rsp % 16               8, not 0 -- the source comment is wrong
;;;     break printf
;;;     c
;;;     p $rsp % 16               8 -- which is correct
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE CALL STACK IS FLAT AND BORING, WHICH IS THE POINT. `bt` shows two
;;;   frames at every breakpoint, `p $rsp` never moves after the prologue, and
;;;   there are no locals -- every named quantity lives in .bss. This is a
;;;   program with a lot of state and none of it on the stack.
;;;
;;;   WHY? Because eleven doubles cannot live in registers across nine printf
;;;   calls, and because the FPU stack has only eight slots and none of them
;;;   survive a call in any useful way. Once you have more live values than
;;;   registers, static memory or a stack frame is the only option -- and .bss is
;;;   the simpler of the two when the values are global to the whole computation.
;;;   Compare code-0018.asm, which puts three loop variables in a frame, and
;;;   code-0021.asm, which uses both a frame and .bss for different things.
;;;
;;;   THE INTERESTING STACK IS THE OTHER ONE. Track the FPU depth through a
;;;   single node:
;;;       break gauss_chebyshev.asm:NN     NN on the `fld qword [c_one]` in Step C
;;;       c
;;;       info float          empty
;;;       si                  push 1        -> depth 1
;;;       si                  push x_i      -> depth 2
;;;       si                  fmul st0,st0  -> depth 2
;;;       si                  fsubp         -> depth 1
;;;       si                  fsqrt         -> depth 1
;;;       si                  fstp          -> depth 0
;;;   Six instructions, and the depth goes 0,1,2,2,1,1,0. THE MAXIMUM DEPTH IS
;;;   TWO. That is what makes this program safe: with eight slots available and a
;;;   peak of two or three, there is no way to overflow -- and every step
;;;   returning to zero means no step can affect any other. It is exactly the
;;;   same discipline as "restore rsp before you return", one level down.
;;;
;;;   Finally, r12 and r13 are pushed in the prologue and popped in the epilogue.
;;;   r12 holds the loop counter, and being CALLEE-SAVED is precisely why it
;;;   survives the printf inside the loop without ever being written to memory.
;;;   r13 is pushed for alignment and never used -- the author's comment says
;;;   "(reserved/pad)", which is honest.
;;; ============================================================================

; ===========================================================================
; gauss_chebyshev_v2.asm
; x86-64 + x87 FPU
; Gaussian Quadrature with Chebyshev nodes
;
; Computes:  integral of sin(x) dx  from 0 to 1
; Exact answer: 1 - cos(1) = 0.45969769413186028
;
; MATHEMATICAL BACKGROUND:
; -------------------------
; The Chebyshev-Gauss quadrature rule is designed for integrals of the form:
;
;   integral_{-1}^{1}  f(x) / sqrt(1-x^2)  dx
;
; Using n nodes:  x_i = cos( (2i-1)*pi/(2n) )   i = 1..n
; With weights:   w_i = pi/n  for all i  (uniform!)
;
; To integrate a plain function g(t) on [a,b] we must:
;   1. Transform:  t_i = (b-a)/2 * x_i + (a+b)/2
;   2. Absorb the weight function sqrt(1-x_i^2) into g:
;      set f(x_i) = g(t_i) * sqrt(1 - x_i^2)
;   3. Apply the formula:
;      integral_a^b g(t) dt  ≈  (b-a)/2 * (pi/n) * sum_i  g(t_i)*sqrt(1-x_i^2)
;
; g(t) = sin(t),  [a,b] = [0,1],  n = 8
;
; KEY FIXES vs v1 (which had NASM parse errors and wrong formula):
;   - fildl (AT&T GAS syntax) replaced by fild dword (NASM syntax)
;   - Unicode box characters removed from strings (caused encoding errors)
;   - sqrt(1-x_i^2) factor added correctly (was missing in v1 -> wrong result)
;   - fsqrt used for square root (x87 built-in, no library needed)
;   - Stack alignment corrected: 3 pushes + no extra sub = correct alignment
;   - FPU stack strictly empty at all function boundaries
;
; Build:
;   nasm -f elf64 gauss_chebyshev_v2.asm -o gauss_chebyshev_v2.o
;   gcc  -no-pie -m64 gauss_chebyshev_v2.o -o gauss_chebyshev_v2
; Run:
;   ./gauss_chebyshev_v2
; ===========================================================================

        global  main
                                        ;   export `main` for the C library start-up
        extern  printf
                                        ;   the only external function needed

; ---------------------------------------------------------------------------
section .data
; ---------------------------------------------------------------------------

a           dq  0.0                     ; lower integration limit
                                        ;   the lower limit of integration
b           dq  1.0                     ; upper integration limit
                                        ;   the upper limit
N           equ 8                       ; number of Chebyshev nodes
                                        ;   `equ` = an ASSEMBLE-TIME constant, not memory. CHANGE
                                        ;   THIS TO 4, 16 OR 32 and watch the error shrink.

c_half      dq  0.5
                                        ;   the constant 0.5, because x87 cannot take an immediate
c_one       dq  1.0
                                        ;   ...and 1.0, for the same reason

; exact value: 1 - cos(1)
exact       dq  0.45969769413186028
                                        ;   the true answer, for the error report

; --- format strings (pure ASCII - no Unicode) ---
fmt_hdr     db  10
                                        ;   a multi-line header. %d prints an INT, so this call
                                        ;   needs no vector registers at all.
            db  "=========================================", 10
            db  "  Gauss-Chebyshev Quadrature  (n=%d)", 10
            db  "  Integral of sin(x) from 0 to 1", 10
            db  "=========================================", 10
            db  "  Formula: (b-a)/2 * (pi/n) * sum f(t_i)*sqrt(1-x_i^2)", 10
            db  "-----------------------------------------", 10, 0

fmt_node    db  "  i=%2d: x_i=%9.6f  sqrt(1-x^2)=%9.6f"
                                        ;   one line per node: an int and four doubles. %9.6f means
                                        ;   six decimals right-aligned in nine columns.
            db  "  t_i=%8.6f  f(t_i)*w=%10.7f", 10, 0

fmt_sep     db  "-----------------------------------------", 10, 0
                                        ;   a plain separator, no conversions
fmt_res     db  "  Result = %.15f", 10, 0
                                        ;   one double, to fifteen decimals
fmt_exact   db  "  Exact  = %.15f", 10, 0
                                        ;   ...and the exact value, for comparison
fmt_err     db  "  Error  = %.3e", 10, 0
                                        ;   %.3e is scientific notation -- the right choice for an
                                        ;   error, which spans many orders of magnitude
fmt_foot    db  "  (Error decreases as n increases)", 10, 0
                                        ;   the closing hint

; ---------------------------------------------------------------------------
section .bss
; ---------------------------------------------------------------------------

; integer scratch for fild (NASM requires memory operand for fild)
                                        ;   zero-filled at load time. Everything this program
                                        ;   computes lives here, because there are far more live
                                        ;   doubles than registers.
i_int       resd  1                     ; current i as 32-bit int
                                        ;   THE `fild` SCRATCH SLOTS. x87 cannot read a general
                                        ;   register or take an immediate, so integers must be
                                        ;   written to memory and loaded back. See the header.
two_n_int   resd  1                     ; 2*N as 32-bit int
                                        ;   i, as a 32-bit int
n_int       resd  1                     ; N as 32-bit int
                                        ;   2N, precomputed once

                                        ;   N itself
; floating-point working variables
angle       resq  1                     ; (2i-1)*pi/(2n)
                                        ;   the working variables of the quadrature
node_x      resq  1                     ; Chebyshev node x_i = cos(angle)
node_t      resq  1                     ; transformed node t_i in [a,b]
w_factor    resq  1                     ; sqrt(1 - x_i^2)  -- the correction weight
f_weighted  resq  1                     ; sin(t_i) * sqrt(1 - x_i^2)
sum_fw      resq  1                     ; running sum of f(t_i)*sqrt(1-x_i^2)
half_ba     resq  1                     ; (b-a)/2
midpoint    resq  1                     ; (a+b)/2
weight      resq  1                     ; pi/n
result      resq  1                     ; final answer
abserr      resq  1                     ; |result - exact|

; ---------------------------------------------------------------------------
section .note.GNU-stack noalloc noexec nowrite progbits
                                        ;   the "no executable stack" marker, with the full set of
                                        ;   attributes
; ---------------------------------------------------------------------------
section .text
; ---------------------------------------------------------------------------

; ===========================================================================
; main
; ===========================================================================
main:
                                        ;   int main(void)
        push    rbp
                                        ;   prologue: save the caller's frame pointer
        mov     rbp, rsp
                                        ;   anchor the frame
        push    r12                     ; loop counter i   (callee-saved)
                                        ;   r12 is CALLEE-SAVED, which is exactly why the loop
                                        ;   counter can live there across the printf calls
        push    r13                     ; (reserved/pad)   (callee-saved)
                                        ;   pushed for alignment and never used -- the author's
                                        ;   "(reserved/pad)" is honest. Three pushes take rsp from
                                        ;   8 mod 16 to 0 mod 16, which is correct at a `call`.
                                        ; Stack state after 3 pushes (push rbp, push r12, push r13):
                                        ;   rsp = entry_rsp - 24
                                        ;   entry_rsp was 16-aligned, so rsp ≡ -24 ≡ 8 (mod 16)
                                        ;   call pushes 8 more -> inside callee: rsp ≡ 0 (mod 16) CORRECT
                                        ; No extra sub rsp needed.

                                        ; ── precompute half_ba = (b-a)/2 ────────────────────────────────────
                                        ; WHY: this factor appears in both the node transform and the final
                                        ;      scaling.  Computing it once avoids repeated subtraction.
        fld     qword [b]
                                        ;   push b.  FPU stack:  b
        fsub    qword [a]               ; ST0 = b - a = 1.0
                                        ;   st0 := st0 - [a].  stack:  b - a
        fmul    qword [c_half]          ; ST0 = (b-a)/2 = 0.5
                                        ;   st0 := st0 * 0.5.  stack:  (b-a)/2
        fstp    qword [half_ba]         ; store, pop -> EMPTY
                                        ;   store and pop.  stack: EMPTY

                                        ; ── precompute midpoint = (a+b)/2 ───────────────────────────────────
        fld     qword [a]
                                        ;   push a.  stack:  a
        fadd    qword [b]               ; ST0 = a + b = 1.0
                                        ;   st0 := st0 + [b].  stack:  a + b
        fmul    qword [c_half]          ; ST0 = (a+b)/2 = 0.5
                                        ;   st0 := st0 * 0.5
        fstp    qword [midpoint]
                                        ;   store and pop.  stack: EMPTY

                                        ; ── precompute weight = pi/n ─────────────────────────────────────────
                                        ; WHY: fild requires a MEMORY operand (not an immediate).
                                        ;      We store N to [n_int] then use fild dword [n_int].
                                        ;      fild converts the 32-bit integer to 80-bit extended float.
        mov     dword [n_int],    N
                                        ;   park N in memory, because `fild` needs a MEMORY operand
        mov     dword [two_n_int], 2*N
                                        ;   ...and 2N, computed at assembly time by NASM
        fldpi                           ; ST0 = pi
                                        ;   push the constant pi.  stack:  pi
        fild    dword [n_int]           ; ST0 = (float)N,  ST1 = pi
                                        ;   push N, CONVERTED from 32-bit integer to float.
                                        ;   stack:  pi  N
        fdivp                           ; ST0 = pi/N  (fdivp: ST1/ST0, pop)
                                        ;   st1 := st1 / st0, then pop.  stack:  pi/N
                                        ;   The value pushed FIRST is the numerator.
        fstp    qword [weight]
                                        ;   store and pop.  stack: EMPTY

                                        ; ── initialise sum to 0 ─────────────────────────────────────────────
        fldz
                                        ;   push the constant 0.0
        fstp    qword [sum_fw]
                                        ;   store and pop -- the running sum starts at zero

                                        ; ── print header ─────────────────────────────────────────────────────
        mov     rdi, fmt_hdr
                                        ;   printf argument 1: the format string
        mov     esi, N
                                        ;   argument 2: N, an INT, so an integer register
        xor     eax, eax
                                        ;   0 vector registers carry arguments -- the header has no
                                        ;   float conversions
        call    printf

                                        ; ── node loop: i = 1 .. N ────────────────────────────────────────────
        mov     r12d, 1                 ; i = 1
                                        ;   i = 1. The 32-bit name also zeroes the upper half of r12.

.node_loop:
                                        ;   one pass per node. `.node_loop` is LOCAL to main.
        cmp     r12d, N
                                        ;   have we done all N nodes?
        jg      .node_done
                                        ;   `jg` = jump if greater, signed

                                        ; ── Step A: compute angle = (2i-1) * pi / (2N) ──────────────────────
                                        ;
                                        ; In NASM x87, to load an integer as a float we use:
                                        ;   fild dword [memory]    (NOT fildl which is AT&T/GAS syntax)
                                        ;
                                        ; FPU stack trace for angle computation:
                                        ;   fild [i_int]   -> ST0 = (float)i
                                        ;   fadd st0,st0   -> ST0 = 2i
                                        ;   fsub [c_one]   -> ST0 = 2i - 1
                                        ;   fldpi          -> ST0 = pi,    ST1 = 2i-1
                                        ;   fmulp          -> ST0 = (2i-1)*pi       [ST1*=ST0, pop]
                                        ;   fild [two_n]   -> ST0 = 2N,   ST1 = (2i-1)*pi
                                        ;   fdivp          -> ST0 = (2i-1)*pi/(2N)  [ST1/=ST0, pop]
                                        ;   fstp [angle]   -> store, pop -> EMPTY
                                        ;
        mov     dword [i_int], r12d
                                        ;   integer register -> memory, so `fild` can reach it
        fild    dword [i_int]           ; ST0 = (float)i
                                        ;   memory -> FPU stack, converted to floating point.
                                        ;   stack:  i
        fadd    st0, st0                ; ST0 = 2i
                                        ;   st0 := st0 + st0 = 2i. Adding a value to itself is the
                                        ;   cheapest way to double it.
        fsub    qword [c_one]           ; ST0 = 2i - 1
                                        ;   st0 := 2i - 1.  stack:  2i-1
        fldpi                           ; ST0 = pi,       ST1 = 2i-1
                                        ;   push pi.  stack:  2i-1   pi
        fmulp                           ; ST0 = (2i-1)*pi
                                        ;   st1 := st1 * st0, then pop.  stack:  (2i-1)*pi
        fild    dword [two_n_int]       ; ST0 = 2N,       ST1 = (2i-1)*pi
                                        ;   push 2N, converted.  stack:  (2i-1)*pi   2N
        fdivp                           ; ST0 = (2i-1)*pi/(2N)
                                        ;   st1 := st1 / st0, then pop.  stack:  the angle
        fstp    qword [angle]           ; EMPTY
                                        ;   store and pop.  stack: EMPTY

                                        ; ── Step B: x_i = cos(angle) ─────────────────────────────────────────
                                        ; This is the i-th Chebyshev node on [-1, 1].
        fld     qword [angle]
                                        ;   push the angle
        fcos                            ; ST0 = cos(angle) = x_i
                                        ;   cosine of st0, IN PLACE, argument in RADIANS. This is
                                        ;   the i-th Chebyshev node, in [-1, 1].
        fstp    qword [node_x]
                                        ;   store and pop.  stack: EMPTY

                                        ; ── Step C: sqrt_factor = sqrt(1 - x_i^2) ────────────────────────────
                                        ; WHY THIS FACTOR?
                                        ;   The Chebyshev-Gauss rule integrates f(x)/sqrt(1-x^2) exactly.
                                        ;   For a plain integral of g(x), we set f(x) = g(x)*sqrt(1-x^2).
                                        ;   This cancels the 1/sqrt(1-x^2) weight, giving us integral of g.
                                        ;
                                        ; FPU computation:
                                        ;   fld  [c_one]  -> ST0 = 1
                                        ;   fld  [node_x] -> ST0 = x_i,  ST1 = 1
                                        ;   fmul st0,st0  -> ST0 = x_i^2
                                        ;   fsubp         -> ST0 = 1 - x_i^2  [ST1-=ST0, pop]
                                        ;   fsqrt         -> ST0 = sqrt(1 - x_i^2)
        fld     qword [c_one]           ; ST0 = 1
                                        ;   push 1.0.  stack:  1
        fld     qword [node_x]          ; ST0 = x_i,    ST1 = 1
                                        ;   push x_i.  stack:  1   x_i
        fmul    st0, st0                ; ST0 = x_i^2
                                        ;   st0 := st0 * st0.  stack:  1   x_i^2
        fsubp                           ; ST0 = 1 - x_i^2
                                        ;   st1 := st1 - st0, then pop.  stack:  1 - x_i^2
        fsqrt                           ; ST0 = sqrt(1 - x_i^2)
                                        ;   square root, in place. Maximum FPU depth in this block:
                                        ;   TWO slots, out of eight available.
        fstp    qword [w_factor]        ; EMPTY
                                        ;   store and pop.  stack: EMPTY

                                        ; ── Step D: t_i = (b-a)/2 * x_i + (a+b)/2 ───────────────────────────
                                        ; Transform the node from [-1,1] to [a,b] = [0,1]
        fld     qword [node_x]
                                        ;   push x_i
        fmul    qword [half_ba]         ; ST0 = 0.5 * x_i
                                        ;   st0 := x_i * (b-a)/2
        fadd    qword [midpoint]        ; ST0 = 0.5*x_i + 0.5 = t_i
                                        ;   st0 := ... + (a+b)/2. The affine map from [-1,1] to [a,b].
        fstp    qword [node_t]
                                        ;   store and pop.  stack: EMPTY

                                        ; ── Step E: f_weighted = sin(t_i) * sqrt(1 - x_i^2) ─────────────────
        fld     qword [node_t]
                                        ;   push t_i
        fsin                            ; ST0 = sin(t_i)
                                        ;   sine of st0, in place, argument in RADIANS. This is the
                                        ;   integrand g(t). Replace it to integrate something else.
        fmul    qword [w_factor]        ; ST0 = sin(t_i) * sqrt(1-x_i^2)
                                        ;   st0 := sin(t_i) * sqrt(1-x_i^2) -- the weighted sample
        fstp    qword [f_weighted]
                                        ;   store and pop.  stack: EMPTY

                                        ; ── Step F: sum_fw += f_weighted ─────────────────────────────────────
        fld     qword [sum_fw]
                                        ;   push the running sum
        fadd    qword [f_weighted]
                                        ;   st0 := sum + this sample
        fstp    qword [sum_fw]
                                        ;   store the new sum and pop.  stack: EMPTY
                                        ;   The accumulator lives in MEMORY, not on the FPU stack --
                                        ;   which is what keeps every step independent.

                                        ; ── print this node ───────────────────────────────────────────────────
        mov     rdi, fmt_node
                                        ;   printf argument 1
        mov     esi, r12d               ; i
                                        ;   argument 2: i, an INT, in an integer register
        movsd   xmm0, [node_x]          ; x_i
                                        ;   the four doubles go in xmm0..xmm3, IN ORDER. Integer and
                                        ;   float arguments are counted in SEPARATE sequences.
        movsd   xmm1, [w_factor]        ; sqrt(1-x_i^2)
        movsd   xmm2, [node_t]          ; t_i
        movsd   xmm3, [f_weighted]      ; sin(t_i)*sqrt(1-x_i^2)
        mov     eax, 4
                                        ;   FOUR vector registers carry arguments
        call    printf

        inc     r12d
                                        ;   next node
        jmp     .node_loop
                                        ;   round again

.node_done:
                                        ;   local to main, reached when i exceeds N
                                        ; ── Final result: integral ≈ (b-a)/2 * (pi/N) * sum_fw ──────────────
                                        ; The (pi/N) is [weight], and (b-a)/2 is [half_ba].
        fld     qword [sum_fw]
                                        ;   push the sum
        fmul    qword [weight]          ; sum * (pi/N)
                                        ;   st0 := sum * (pi/N)
        fmul    qword [half_ba]         ; * (b-a)/2
                                        ;   st0 := ... * (b-a)/2. The full quadrature formula.
        fstp    qword [result]
                                        ;   store and pop.  stack: EMPTY

                                        ; ── error = |result - exact| ─────────────────────────────────────────
        fld     qword [result]
                                        ;   push the result
        fsub    qword [exact]
                                        ;   st0 := result - exact
        fabs
                                        ;   absolute value, in place
        fstp    qword [abserr]
                                        ;   store and pop.  stack: EMPTY

                                        ; ── print results ────────────────────────────────────────────────────
        mov     rdi, fmt_sep
                                        ;   a separator line: no conversions...
        xor     eax, eax
                                        ;   ...so 0 vector registers
        call    printf

        mov     rdi, fmt_res
                                        ;   the computed answer...
        movsd   xmm0, [result]
                                        ;   ...as one double in xmm0...
        mov     eax, 1
                                        ;   ...so 1 vector register
        call    printf

        mov     rdi, fmt_exact
                                        ;   the exact answer, for comparison
        movsd   xmm0, [exact]
        mov     eax, 1
        call    printf

        mov     rdi, fmt_err
                                        ;   and the error, in scientific notation
        movsd   xmm0, [abserr]
        mov     eax, 1
        call    printf

        mov     rdi, fmt_foot
                                        ;   the closing hint: no conversions
        xor     eax, eax
        call    printf

                                        ; ── epilogue ─────────────────────────────────────────────────────────
        xor     eax, eax
                                        ;   main's return value: 0 = success
        pop     r13
                                        ;   restore the callee-saved registers IN REVERSE ORDER to
                                        ;   the pushes -- the stack is last-in first-out
        pop     r12
        pop     rbp
        ret
                                        ;   pop the return address into rip

