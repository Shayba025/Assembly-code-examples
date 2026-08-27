;;; ============================================================================
;;; lagrange_final.asm -- Lagrange interpolation, shown step by step
;;; Practice session 9                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Fits the unique degree-4 polynomial through the five points
;;;   (0,1) (1,3) (2,2) (3,5) (4,2), evaluates it at x = 2.5, and prints every
;;;   intermediate quantity along the way. Then it checks two properties that
;;;   ought to hold and shows that they do.
;;;   (Verified: P is exact at all five nodes, with error 0.00e+00 at each.)
;;;
;;;   THE MATHEMATICS, briefly. For each data point i you build a BASIS
;;;   POLYNOMIAL that is 1 at x_i and 0 at every other node:
;;;       L_i(x) = product over j != i of  (x - x_j) / (x_i - x_j)
;;;   Then P(x) = sum of y_i * L_i(x). At x = x_k every term vanishes except the
;;;   k-th, which contributes y_k -- so P passes through every point exactly.
;;;   That is what Step 4 verifies.
;;;
;;;   AND THE PARTITION OF UNITY, checked in Step 2: sum of all L_i(x) = 1, for
;;;   ANY x. It follows because the interpolant of the constant function 1 must
;;;   be 1. It is a cheap and excellent sanity check on any implementation --
;;;   if your L_i values do not sum to 1, you have a bug.
;;;
;;;   ------------------------------------------------------------------
;;;   THE CODE
;;;   ------------------------------------------------------------------
;;;   TWO NESTED LOOPS, and the inner one SKIPS j == i:
;;;       cmp r13, r12
;;;       je  .inner_next
;;;   That one comparison is the whole "product over j != i". Without it the
;;;   denominator would contain (x_i - x_i) = 0 and every L_i would be infinite.
;;;
;;;   ARRAY INDEXING WITH `lea`:
;;;       lea rax, [xs + r13*8]     ; rax := &xs[j]
;;;       fld qword [rax]           ; push xs[j]
;;;   `lea` computes an ADDRESS and keeps the number; `fld [rax]` then loads
;;;   through it. The author's comment explains why the address is materialised
;;;   first: x87 memory operands do not accept the full base+index*scale form in
;;;   every encoding, so putting the address in a register is the always-safe
;;;   route. This is the same base + 8*index idiom as every array in this course,
;;;   with 8 because the elements are doubles.
;;;
;;;   *** THE FILE CONTAINS THE SAME LOOP TWICE, AND THAT IS WORTH NOTICING. ***
;;;   `compute_P` computes P(x_q) silently; the loop inside `main` computes the
;;;   same thing while printing every intermediate value. Duplicated logic is a
;;;   maintenance hazard -- change the formula in one and forget the other and
;;;   the verification step will disagree with the display step for reasons that
;;;   take an hour to find. A better design would have `compute_P` take a "print
;;;   or not" flag. Worth doing as an exercise.
;;;
;;;   HOW THE VERIFICATION STEP WORKS is a small trick: it OVERWRITES [x_q] with
;;;   each node in turn, calls `compute_P`, and restores [x_q] from [x_q_save] at
;;;   the end. Passing arguments through a global like that is exactly what makes
;;;   a function non-reentrant -- it could never be called from two threads -- but
;;;   with x87 it is the pragmatic choice, because agreeing on FPU stack depth
;;;   across a call is far more error-prone.
;;;
;;;   `fst` VERSUS `fstp` at line 332: `fst` stores to memory and KEEPS the value
;;;   on the stack, so y_i is saved for printf and simultaneously left in place
;;;   for the multiply on the next line. One instruction saved, and the sort of
;;;   thing that only reads clearly if you are tracking the FPU depth.
;;;
;;;   A CORRECTION TO THE AUTHOR'S ALIGNMENT NOTE (lines 231-235). It reasons
;;;   from "the 16-aligned entry rsp" and concludes that 8 mod 16 inside printf
;;;   would be WRONG. Both halves are mistaken, and they cancel, so the CODE IS
;;;   CORRECT. Measured:
;;;       at main's first instruction   rsp % 16 == 8   (call main pushed 8)
;;;       after the four pushes         rsp % 16 == 8
;;;       after `sub rsp, 8`            rsp % 16 == 0   <- correct at a `call`
;;;       at printf's first instruction rsp % 16 == 8   <- which is RIGHT
;;;   The ABI's rule is "rsp is a multiple of 16 immediately BEFORE the call",
;;;   i.e. 8 mod 16 at the callee's first instruction. Verify with
;;;   `break printf` then `p $rsp % 16`.
;;;
;;;   THE ERRORS IN STEP 4 COME OUT AS EXACTLY 0.00e+00, which is slightly
;;;   better than the author's comment predicts. That is a happy accident of
;;;   these particular numbers -- x87 computes internally at 80 bits, and with
;;;   small integer data the rounding cancels perfectly. Change a y value to
;;;   something like 1.1 and you will see the 1e-16 the comment expects.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/9/lagrange_final.asm"
;;;
;;;   Check the answer independently:
;;;   python3 -c "
;;;   xs=[0,1,2,3,4]; ys=[1,3,2,5,2]; x=2.5
;;;   P=sum(y*__import__('math').prod((x-xj)/(xi-xj) for j,xj in enumerate(xs) if j!=i)
;;;         for i,(xi,y) in enumerate(zip(xs,ys)))
;;;   print(P)"
;;;
;;;   Change the data by editing `xs` and `ys` (keep N equ 5 in step with them),
;;;   or the query point by editing BOTH `x_q_save` and `x_q`.
;;;
;;;   Try giving two points the same x -- say `xs dq 0.0, 1.0, 1.0, 3.0, 4.0` --
;;;   and watch the denominator go to zero. Interpolation needs distinct nodes.
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/9/lagrange_final.asm"
;;;
;;;   Useful session -- watch one basis polynomial being built:
;;;     break lagrange_final.asm:NN     NN on the `fdiv qword [den]` in .inner_done
;;;     c
;;;     p (double)num             the product of (x - x_j)
;;;     p (double)den             the product of (x_i - x_j)
;;;     si
;;;     p $st0                    L_i = num/den
;;;     p $r12                    which i this is
;;;
;;;   Watch the skip that makes the formula work:
;;;     break lagrange_final.asm:NN     NN on the `cmp r13, r12` line
;;;     c
;;;     info registers r12 r13    i and j
;;;     si si                     the compare and the conditional jump
;;;     p $rip                    when i == j, it jumped over the whole body
;;;
;;;   Check the partition of unity as it accumulates:
;;;     break printf
;;;     c ... c                   step through the five nodes
;;;     p (double)unity           watch it climb towards exactly 1.0
;;;     p (double)total           and the interpolated value towards P(2.5)
;;;
;;;   And confirm the FPU stack discipline the author claims:
;;;     break compute_P
;;;     c
;;;     info float                EMPTY on entry, as documented
;;;     finish
;;;     info float                EMPTY on exit
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THIS IS THE FIRST PROGRAM IN ps_code WITH A REAL SUBROUTINE THAT OBEYS THE
;;;   FULL ABI, and it is worth reading `compute_P`'s prologue and epilogue as a
;;;   statement of intent:
;;;       push rbx / push r15 / push r14    ...    pop r14 / pop r15 / pop rbx
;;;   Those three registers are CALLEE-SAVED, so the function that uses them must
;;;   give them back. The author says so in the header comment, and then does it.
;;;   Note the pops mirror the pushes IN REVERSE -- the stack is last-in
;;;   first-out, and getting that ordering wrong swaps two of the caller's
;;;   registers, which is a spectacularly confusing bug.
;;;
;;;   Watch the promise being kept:
;;;       break compute_P
;;;       c
;;;       p/x $rbx                whatever main had there
;;;       finish
;;;       p/x $rbx                identical
;;;
;;;   MEANWHILE THE FPU STACK IS GOVERNED BY A SEPARATE, EXPLICIT CONTRACT:
;;;   "Stack is EMPTY on entry. Stack is EMPTY on exit. Every fld is matched by
;;;   exactly one fstp or fdivp/fmulp/fsubp." That is written into the function
;;;   header, and it has to be, because THERE ARE ONLY EIGHT SLOTS. A leak of one
;;;   per call would break this program on the eighth iteration -- silently, with
;;;   NaNs rather than a crash. Track the depth through the inner loop:
;;;       break lagrange_final.asm:NN     NN on the `fld qword [x_q]` in .inner
;;;       c
;;;       info float          empty
;;;       si si si si         fld, fsub, fmul, fstp
;;;       info float          empty again
;;;   Maximum depth: ONE. This program never has more than two values on the FPU
;;;   stack at once, which is why it is safe.
;;;
;;;   THE THIRD THING TO NOTICE is what is NOT on either stack. `num`, `den`,
;;;   `Li_val`, `term`, `total`, `unity`, `pct` -- seven live doubles -- all live
;;;   in .bss. They have to: there are more of them than the FPU has usable
;;;   slots, and none of them would survive a `call printf` in a register anyway.
;;;   That is the same conclusion code-0018.asm reaches with three integers and a
;;;   stack frame, arrived at from the other direction. WHEN YOU HAVE MORE LIVE
;;;   VALUES THAN REGISTERS, MEMORY IS NOT A FALLBACK -- IT IS THE DESIGN.
;;; ============================================================================

; ===========================================================================
; lagrange_final.asm
; x86-64 + x87 FPU  —  Lagrange Polynomial Interpolation
;
; Data points: (0,1)  (1,3)  (2,2)  (3,5)  (4,2)
; Evaluates  P(x)  at  x = 2.5
;
; Build:
;   nasm -f elf64 lagrange_final.asm -o lagrange_final.o
;   gcc  -no-pie -m64 lagrange_final.o -o lagrange_final
; Run:
;   ./lagrange_final
; ===========================================================================

        global  main
                                        ;   export `main` for the C library start-up
        extern  printf
                                        ;   the only external function needed

; ──────────────────────────────────────────────────────────────────────────────
; SECTION .data  — all initialised constants and format strings live here
; ──────────────────────────────────────────────────────────────────────────────
section .data

N       equ  5                          ; number of data points (compile-time)
                                        ;   `equ` = an ASSEMBLE-TIME constant. Keep it in step with
                                        ;   the two arrays below by hand -- nothing checks.

; x-coordinates of the 5 data points
xs      dq   0.0, 1.0, 2.0, 3.0, 4.0
                                        ;   the five node positions. `dq` emits 8-byte doubles, so
                                        ;   the array stride is 8. They MUST be distinct: equal
                                        ;   nodes give a zero denominator.

; y-coordinates (function values at each x)
ys      dq   1.0, 3.0, 2.0, 5.0, 2.0
                                        ;   the five values to interpolate

; query point — we want P(2.5)
x_q_save dq  2.5                        ; permanent backup (never changed)
                                        ;   a pristine copy, never modified
x_q      dq  2.5                        ; working copy (overwritten in verify step)
                                        ;   the working copy. Step 4 overwrites this with each node
                                        ;   in turn and restores it from the backup afterwards.

; floating-point constants used in arithmetic
c_one   dq   1.0
                                        ;   x87 cannot take an immediate, so even 1.0 and 100.0 have
                                        ;   to live in memory
c_100   dq   100.0

; ── printf format strings ─────────────────────────────────────────────────────
fmt_title  db  10
                                        ;   the box-drawing characters are UTF-8; printf copies the
                                        ;   bytes through without decoding them
           db  "╔══════════════════════════════════════════════════╗", 10
           db  "║   LAGRANGE POLYNOMIAL INTERPOLATION  (x87 FPU)  ║", 10
           db  "╚══════════════════════════════════════════════════╝", 10, 0

fmt_points db  "  Data points: (0,1) (1,3) (2,2) (3,5) (4,2)", 10
                                        ;   one double: the query point
           db  "  Query x = %.1f", 10
           db  "──────────────────────────────────────────────────", 10, 0

fmt_step1  db  10
                                        ;   no conversions at all, so 0 vector registers
           db  "  ─── Step 1: Compute each basis polynomial L_i(x) ───", 10
           db  "  Formula: L_i(x) = prod_{j!=i} (x-x_j) / (x_i-x_j)", 10, 0

fmt_i_hdr  db  10, "  i=%d:", 10, 0
                                        ;   one INT, in an integer register

fmt_nd     db  "    numerator   = prod_{j!=i}(x - x_j)   = %12.6f", 10
                                        ;   two doubles: the numerator and denominator products
           db  "    denominator = prod_{j!=i}(x_i - x_j) = %12.6f", 10, 0

fmt_li     db  "    L_%d(%.1f) = num/den = %12.9f", 10, 0
                                        ;   an int and two doubles -- counted in SEPARATE sequences

fmt_term   db  "    y_%d * L_%d = %.1f * (%9.6f) = %12.9f   [%6.2f%% of P]", 10, 0
                                        ;   two ints and four doubles. %% prints a literal percent
                                        ;   sign.

fmt_step2  db  10
           db  "  ─── Step 2: Partition-of-Unity Check ───", 10
           db  "  Theory: sum of ALL L_i(x) = 1 for ANY x.", 10, 0

fmt_unity  db  "  Sum L_i(%.1f) = %.15f  (should be exactly 1.0)", 10, 0
                                        ;   two doubles

fmt_step3  db  10, "  ─── Step 3: Final Result ───", 10, 0

fmt_res    db  "  P(%.1f) = sum of y_i * L_i = %.15f", 10, 0
                                        ;   two doubles: the query point and the answer

fmt_step4  db  10
           db  "  ─── Step 4: Verification at Known Nodes ───", 10
           db  "  Lagrange polynomial is EXACT at each x_i.", 10, 0

fmt_ver    db  "  P(%3.1f) = %12.9f   y_%d = %.1f   |error| = %.2e", 10, 0
                                        ;   two doubles, an int, then two more doubles -- so four
                                        ;   vector registers and two integer ones

fmt_foot   db  "──────────────────────────────────────────────────", 10
                                        ;   two ints
           db  "  Polynomial degree = N-1 = %d", 10
           db  "  Exact at %d nodes (errors are floating-point epsilon).", 10
           db  "──────────────────────────────────────────────────", 10, 0

; ──────────────────────────────────────────────────────────────────────────────
; SECTION .bss  — uninitialised working variables (zeroed at program start)
; ──────────────────────────────────────────────────────────────────────────────
section .bss
                                        ;   zero-filled at load time. SEVEN live doubles, which is
                                        ;   more than the FPU stack can usefully hold across calls --
                                        ;   see the call-stack notes.

num      resq  1                        ; numerator product for current L_i
den      resq  1                        ; denominator product for current L_i
Li_val   resq  1                        ; L_i(x_q) = num / den
term     resq  1                        ; y_i * L_i  (one contribution to P)
total    resq  1                        ; running sum P(x_q) = sum of all terms
unity    resq  1                        ; sum of all L_i values (should equal 1.0)
pct      resq  1                        ; |term| / |total| * 100  (percentage contribution)
yi_tmp   resq  1                        ; temporary copy of y_i for printf
ver_err  resq  1                        ; |P(x_i) - y_i| for verification

; ──────────────────────────────────────────────────────────────────────────────
; Tell the linker this object does NOT need an executable stack
; (suppresses the linker warning you saw on screen)
; ──────────────────────────────────────────────────────────────────────────────
section .note.GNU-stack noalloc noexec nowrite progbits

; ──────────────────────────────────────────────────────────────────────────────
section .text
; ──────────────────────────────────────────────────────────────────────────────

; ===========================================================================
; SUBROUTINE: compute_P
;
; PURPOSE:
;   Evaluates the Lagrange interpolating polynomial P at the current value
;   stored in [x_q].  Stores the result in [total].
;   Also accumulates the sum of all L_i in [unity] (should = 1.0).
;
; CALLING CONVENTION:
;   No arguments.  No return value in registers.
;   Result is in memory: [total] = P(x_q),  [unity] = sum of L_i.
;
; REGISTERS USED (all saved and restored):
;   rbx = outer loop index i  (0 .. N-1)
;   r15 = inner loop index j  (0 .. N-1)
;   r14 = scratch address register
;   rax = used for effective address computation
;
; FPU STACK DISCIPLINE:
;   Stack is EMPTY on entry.
;   Stack is EMPTY on exit.
;   Every fld is matched by exactly one fstp or fdivp/fmulp/fsubp.
; ===========================================================================
compute_P:
                                        ;   a real subroutine, with a stated ABI contract
                                        ; ── save registers we use (System V ABI: callee must preserve rbx, r12-r15) ──
        push    rbx
                                        ;   these three are CALLEE-SAVED, so a function that uses
                                        ;   them must hand them back unchanged
        push    r15
        push    r14

                                        ; ── initialise accumulators to 0.0 ───────────────────────────────
        fldz
                                        ;   push 0.0...
        fstp    qword [total]           ; total = 0.0
                                        ;   ...and store it: total = 0
        fldz
                                        ;   push 0.0 again...
        fstp    qword [unity]           ; unity = 0.0
                                        ;   ...unity = 0

        xor     rbx, rbx                ; i = 0  (outer loop counter)
                                        ;   i = 0. `xor r, r` is the idiomatic zeroing.

.cp_outer:                              ; for i = 0 to N-1:
                                        ;   `.cp_outer` is LOCAL to compute_P, so it cannot clash
                                        ;   with main's `.outer`
        cmp     rbx, N
                                        ;   all N basis polynomials done?
        jge     .cp_done

                                        ; ── reset num and den to 1.0 for this new i ──────────────────────
                                        ; WHY: each L_i starts as a product of (N-1) factors;
                                        ;      multiplying into 1.0 is the identity for multiplication.
        fld1
                                        ;   push 1.0 -- the identity for multiplication, because
                                        ;   num is about to become a PRODUCT of N-1 factors
        fstp    qword [num]             ; num = 1.0
                                        ;   num = 1.0
        fld1
                                        ;   and den = 1.0
        fstp    qword [den]             ; den = 1.0

        xor     r15, r15                ; j = 0  (inner loop counter)
                                        ;   j = 0

.cp_inner:                              ; for j = 0 to N-1:
                                        ;   the inner loop, over the other nodes
        cmp     r15, N
        jge     .cp_inner_done
                                        ;   `jge` = jump if greater or equal, signed
        cmp     r15, rbx                ; skip j == i  (the formula excludes it)
                                        ;   THE SKIP THAT MAKES THE FORMULA WORK: j == i is excluded,
                                        ;   because (x_i - x_i) would be zero
        je      .cp_skip

                                        ; ── rax = &xs[j],  r14 = &xs[i] ─────────────────────────────────
                                        ; WHY use lea then [rax]: x87 memory operands cannot use
                                        ; scaled-index addressing like [xs+r15*8] directly in some forms.
                                        ; Loading the address into rax first is always safe.
        lea     rax, [xs + r15*8]
                                        ;   rax := &xs[j]. `lea` computes an address and keeps the
                                        ;   number; the 8 is sizeof(double).
        lea     r14, [xs + rbx*8]
                                        ;   r14 := &xs[i]

                                        ; ── num  *=  (x_q - xs[j]) ───────────────────────────────────────
                                        ; This is the numerator factor for position j
        fld     qword [x_q]             ; ST0 = x_q
                                        ;   push x_q.  FPU stack:  x_q
        fsub    qword [rax]             ; ST0 = x_q - xs[j]
                                        ;   st0 := x_q - xs[j], loading through the address in rax
        fmul    qword [num]             ; ST0 = num * (x_q - xs[j])
                                        ;   st0 := num * (x_q - xs[j])
        fstp    qword [num]             ; num = ST0,  pop → stack EMPTY
                                        ;   store and pop.  stack: EMPTY. Maximum depth: one.

                                        ; ── den  *=  (xs[i] - xs[j]) ─────────────────────────────────────
                                        ; This is the denominator factor for position j
        fld     qword [r14]             ; ST0 = xs[i]
                                        ;   push xs[i]
        fsub    qword [rax]             ; ST0 = xs[i] - xs[j]
                                        ;   st0 := xs[i] - xs[j]
        fmul    qword [den]             ; ST0 = den * (xs[i] - xs[j])
                                        ;   st0 := den * (that factor)
        fstp    qword [den]             ; den = ST0,  pop → stack EMPTY
                                        ;   store and pop.  stack: EMPTY

.cp_skip:
                                        ;   where the j == i case lands
        inc     r15
                                        ;   next j
        jmp     .cp_inner

.cp_inner_done:
                                        ;   all the factors are in
                                        ; ── L_i = num / den ──────────────────────────────────────────────
        fld     qword [num]             ; ST0 = num
                                        ;   push num
        fdiv    qword [den]             ; ST0 = num / den  =  L_i(x_q)
                                        ;   st0 := num / den = L_i(x_q)
        fstp    qword [Li_val]          ; Li_val = L_i,  pop → EMPTY
                                        ;   store and pop

                                        ; ── unity  +=  L_i ───────────────────────────────────────────────
        fld     qword [unity]
                                        ;   unity += L_i -- the partition-of-unity accumulator
        fadd    qword [Li_val]
        fstp    qword [unity]

                                        ; ── total  +=  y_i * L_i ─────────────────────────────────────────
        lea     rax, [ys + rbx*8]
                                        ;   rax := &ys[i]
        fld     qword [rax]             ; ST0 = y_i
                                        ;   push y_i
        fmul    qword [Li_val]          ; ST0 = y_i * L_i
                                        ;   st0 := y_i * L_i
        fstp    qword [term]            ; term = y_i * L_i
                                        ;   store the contribution

        fld     qword [total]
                                        ;   total += term
        fadd    qword [term]
        fstp    qword [total]           ; total += term

        inc     rbx
                                        ;   next i
        jmp     .cp_outer

.cp_done:
                                        ;   all N done
                                        ; ── restore saved registers ──────────────────────────────────────
        pop     r14
                                        ;   restore the callee-saved registers IN REVERSE ORDER to
                                        ;   the pushes -- the stack is last-in first-out
        pop     r15
        pop     rbx
        ret
                                        ;   pop the return address into rip. No frame pointer was
                                        ;   ever set up: this function has no locals.

; ===========================================================================
; main — orchestrates the output in four clearly labelled steps
; ===========================================================================
main:
                                        ;   int main(void)
                                        ; ── standard prologue ────────────────────────────────────────────
        push    rbp
                                        ;   prologue: save the caller's frame pointer
        mov     rbp, rsp
                                        ;   anchor the frame
        push    r12                     ; outer loop index (callee-saved)
                                        ;   r12, r13 and r14 are CALLEE-SAVED, which is why the two
                                        ;   loop counters can survive the printf calls without ever
                                        ;   being written to memory
        push    r13                     ; inner loop index (callee-saved)
        push    r14                     ; address scratch  (callee-saved)
                                        ; After 3 pushes + original push rbp = 4 × 8 = 32 bytes below
                                        ; the 16-aligned entry rsp.  32 is divisible by 16 → already aligned.
                                        ; BUT: call pushes 8 more → rsp becomes 16k+8 inside printf → WRONG.
                                        ; Fix: subtract 8 now so that call makes it 16-aligned inside callee.
        sub     rsp, 8                  ; alignment pad
                                        ;   the alignment pad. THE CODE IS CORRECT; the reasoning
                                        ;   above it is not -- see the correction in the file header,
                                        ;   and check with `break printf` then `p $rsp % 16`.

                                        ; ── TITLE ────────────────────────────────────────────────────────
        mov     rdi, fmt_title
                                        ;   printf argument 1: the title
        xor     eax, eax                ; eax = 0: no floating-point args to printf here
                                        ;   0 vector registers: no float conversions in this string
        call    printf

        mov     rdi, fmt_points
                                        ;   the data-point summary...
        movsd   xmm0, [x_q]             ; pass x_q as the %.1f argument
                                        ;   ...with the query point as its one double...
        mov     eax, 1                  ; 1 floating-point argument in xmm0
                                        ;   ...so ONE vector register
        call    printf

                                        ; ── STEP 1 header ────────────────────────────────────────────────
        mov     rdi, fmt_step1
                                        ;   the Step 1 header, no conversions
        xor     eax, eax
        call    printf

                                        ; ── Initialise total and unity to 0.0 for the main display loop ──
        fldz
                                        ;   reset the accumulators for the display loop. (compute_P
                                        ;   does the same thing for its own use -- see the note about
                                        ;   duplicated logic in the header.)
        fstp    qword [total]
        fldz
        fstp    qword [unity]

                                        ; ── OUTER LOOP: i = 0 .. N-1 ─────────────────────────────────────
                                        ; For each i we build L_i(x_q) and print the intermediate values.
        xor     r12, r12                ; r12 = i = 0
                                        ;   i = 0

.outer:
                                        ;   `.outer` is LOCAL to main
        cmp     r12, N
        jge     .outer_done

                                        ; -- reset products --
                                        ;   reset the products to 1.0 for this new i
        fld1
        fstp    qword [num]
        fld1
        fstp    qword [den]

                                        ; ── INNER LOOP: j = 0 .. N-1,  j ≠ i ────────────────────────────
                                        ;   j = 0
        xor     r13, r13                ; r13 = j = 0

.inner:
                                        ;   the inner loop
        cmp     r13, N
        jge     .inner_done
        cmp     r13, r12                ; skip j == i
                                        ;   skip j == i
        je      .inner_next

        lea     rax, [xs + r13*8]       ; &xs[j]
                                        ;   &xs[j]
        lea     r14, [xs + r12*8]       ; &xs[i]
                                        ;   &xs[i]

                                        ; num *= (x_q - xs[j])
                                        ;   num *= (x_q - xs[j])
        fld     qword [x_q]
        fsub    qword [rax]
        fmul    qword [num]
        fstp    qword [num]

                                        ; den *= (xs[i] - xs[j])
                                        ;   den *= (xs[i] - xs[j])
        fld     qword [r14]
        fsub    qword [rax]
        fmul    qword [den]
        fstp    qword [den]

.inner_next:
                                        ;   where the skip lands
        inc     r13
                                        ;   next j
        jmp     .inner

.inner_done:
                                        ;   the products are complete
                                        ; ── HIGHLIGHT 1: print i header ──────────────────────────────────
        mov     rdi, fmt_i_hdr
                                        ;   print which i we are on
        mov     rsi, r12                ; i as integer argument
                                        ;   the int argument goes in rsi
        xor     eax, eax
                                        ;   0 vector registers
        call    printf

                                        ; ── HIGHLIGHT 2: print numerator and denominator ─────────────────
                                        ; Students see the raw products BEFORE the division.
                                        ; This makes the formula concrete: L_i is literally num/den.
        mov     rdi, fmt_nd
                                        ;   show the raw products BEFORE the division -- which is
                                        ;   what makes the formula concrete
        movsd   xmm0, [num]
        movsd   xmm1, [den]
        mov     eax, 2                  ; 2 floating-point args
                                        ;   TWO vector registers
        call    printf

                                        ; -- L_i = num / den --
        fld     qword [num]
                                        ;   L_i = num / den
        fdiv    qword [den]
        fstp    qword [Li_val]

                                        ; ── HIGHLIGHT 3: print L_i value ─────────────────────────────────
        mov     rdi, fmt_li
                                        ;   print the basis value
        mov     rsi, r12                ; i  (for L_%d)
                                        ;   i, as an int in rsi
        movsd   xmm0, [x_q]             ; x_q  (for %.1f)
                                        ;   x_q and L_i as the two doubles
        movsd   xmm1, [Li_val]
        mov     eax, 2
                                        ;   TWO vector registers
        call    printf

                                        ; -- term = y_i * L_i --
        lea     rax, [ys + r12*8]
                                        ;   &ys[i]
        fld     qword [rax]
                                        ;   push y_i
        fst     qword [yi_tmp]          ; save y_i for printf (fst = store without pop)
                                        ;   `fst`, NOT `fstp`: store to memory and KEEP the value on
                                        ;   the stack, so the multiply below can use it without
                                        ;   reloading
        fmul    qword [Li_val]
                                        ;   st0 := y_i * L_i
        fstp    qword [term]
                                        ;   store the contribution and pop

                                        ; -- accumulate --
        fld     qword [total]
                                        ;   total += term
        fadd    qword [term]
        fstp    qword [total]

        fld     qword [unity]
                                        ;   unity += L_i
        fadd    qword [Li_val]
        fstp    qword [unity]

                                        ; ── HIGHLIGHT 4: percentage contribution of this term ────────────
                                        ; pct = |term| / |total| * 100
                                        ; Shows students which nodes contribute most to P(x).
        fld     qword [term]
                                        ;   push |term| * 100...
        fabs
        fmul    qword [c_100]
        fld     qword [total]
                                        ;   ...then |total|...
        fabs
        fdivp                           ; ST0 = |term|*100 / |total|
                                        ;   ...and divide: st1 := st1/st0, then pop
        fstp    qword [pct]
                                        ;   pct = the percentage this node contributes

        mov     rdi, fmt_term
                                        ;   print the term line
        mov     rsi, r12                ; y_%d
                                        ;   TWO integer arguments: rsi then rdx
        mov     rdx, r12                ; L_%d
        movsd   xmm0, [yi_tmp]
                                        ;   FOUR doubles: xmm0 through xmm3, in order
        movsd   xmm1, [Li_val]
        movsd   xmm2, [term]
        movsd   xmm3, [pct]
        mov     eax, 4                  ; 4 floating-point args
                                        ;   four vector registers
        call    printf

        inc     r12
                                        ;   next i
        jmp     .outer

.outer_done:
                                        ;   all five basis polynomials done

                                        ; ── STEP 2: partition-of-unity check ─────────────────────────────
                                        ; KEY PROPERTY: for any x,  sum_{i=0}^{N-1} L_i(x) = 1.
                                        ; This is because the Lagrange basis reproduces the constant
                                        ; polynomial f(x)=1 exactly.
                                        ; We verify it numerically — the result should be 1.000000000000000.
        mov     rdi, fmt_step2
                                        ;   the Step 2 header
        xor     eax, eax
        call    printf

        mov     rdi, fmt_unity
                                        ;   the partition-of-unity check: should print exactly 1.0
        movsd   xmm0, [x_q]
        movsd   xmm1, [unity]
        mov     eax, 2
        call    printf

                                        ; ── STEP 3: final result ─────────────────────────────────────────
        mov     rdi, fmt_step3
                                        ;   the Step 3 header
        xor     eax, eax
        call    printf

        mov     rdi, fmt_res
                                        ;   the answer: P(2.5)
        movsd   xmm0, [x_q]
        movsd   xmm1, [total]
        mov     eax, 2
        call    printf

                                        ; ── STEP 4: verification — P(x_i) must equal y_i exactly ─────────
                                        ; The Lagrange polynomial passes through ALL data points by
                                        ; construction.  Numerically the error should be ~machine epsilon
                                        ; (~1e-16), not exactly 0.0, due to floating-point rounding.
                                        ; We use the helper subroutine compute_P which temporarily
                                        ; overwrites [x_q] then we restore it from [x_q_save].
        mov     rdi, fmt_step4
                                        ;   the Step 4 header
        xor     eax, eax
        call    printf

        xor     r12, r12                ; i = 0
                                        ;   i = 0, for the verification loop

.verify:
                                        ;   one pass per node
        cmp     r12, N
        jge     .verify_done

                                        ; overwrite x_q with xs[i] so compute_P evaluates at a known node
                                        ;   OVERWRITE the working query point with node i, so that
                                        ;   compute_P evaluates there. This is how the argument is
                                        ;   passed -- through a global, which is what makes the
                                        ;   function non-reentrant.
        lea     rax, [xs + r12*8]
        fld     qword [rax]
        fstp    qword [x_q]

        call    compute_P               ; [total] = P(xs[i])
                                        ;   [total] := P(xs[i])

                                        ; error = |P(xs[i]) - ys[i]|
                                        ;   error = |P(xs[i]) - ys[i]|, which should be ~0
        fld     qword [total]
        lea     rax, [ys + r12*8]
        fsub    qword [rax]
        fabs
        fstp    qword [ver_err]

                                        ; printf(fmt_ver, xs[i], total, i, ys[i], ver_err)
                                        ;   print the verification line
        mov     rdi, fmt_ver
        lea     rax, [xs + r12*8]
        movsd   xmm0, [rax]
        movsd   xmm1, [total]
        mov     rsi, r12
        lea     rax, [ys + r12*8]
        movsd   xmm2, [rax]
        movsd   xmm3, [ver_err]
        mov     eax, 4
                                        ;   four vector registers
        call    printf

        inc     r12
                                        ;   next node
        jmp     .verify

.verify_done:
                                        ;   all nodes checked
                                        ; ── restore original query point ─────────────────────────────────
                                        ;   restore the original query point from the pristine copy
        fld     qword [x_q_save]
        fstp    qword [x_q]

                                        ; ── FOOTER ───────────────────────────────────────────────────────
                                        ;   the footer, with two int arguments
        mov     rdi, fmt_foot
        mov     esi, N-1                ; degree = N-1
                                        ;   N-1, computed by NASM at assembly time
        mov     edx, N                  ; number of nodes
        xor     eax, eax
        call    printf

                                        ; ── epilogue ─────────────────────────────────────────────────────
                                        ;   main's return value: 0 = success
        xor     eax, eax                ; return 0
        add     rsp, 8                  ; remove alignment pad
                                        ;   remove the alignment pad, then restore the callee-saved
                                        ;   registers IN REVERSE ORDER to the pushes
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
                                        ;   pop the return address into rip
        ret

