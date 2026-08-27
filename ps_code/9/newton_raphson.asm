;;; ============================================================================
;;; newton_raphson.asm -- root finding on the x87 FPU
;;; Practice session 9                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Finds the root of f(x) = x^3 - 2, i.e. the cube root of 2, by Newton's
;;;   method, printing every iteration.
;;;   (Verified: converges in 5 iterations to 1.259921049894873. The true value
;;;   is 1.2599210498948732, so it is right to every digit printed.)
;;;
;;;   NEWTON'S METHOD in one line:
;;;       x_new = x - f(x) / f'(x)
;;;   Geometrically: draw the tangent to the curve at x, and take the point where
;;;   that tangent crosses zero as your next guess. It converges QUADRATICALLY --
;;;   the number of correct digits roughly doubles each step, which you can watch
;;;   happen in the output:
;;;       iter 0:  f(x) = 1.375e+00
;;;       iter 1:  f(x) = 1.783e-01
;;;       iter 2:  f(x) = 4.819e-03
;;;       iter 3:  f(x) = 3.861e-06
;;;       iter 4:  f(x) = 2.484e-12
;;;       iter 5:  f(x) = 1.234e-16
;;;   Each exponent is about twice the previous one. That is what quadratic
;;;   convergence looks like, and it is why five iterations suffice.
;;;
;;;   *** THE MOST VALUABLE THING IN THIS FILE IS THE BIG COMMENTED-OUT BLOCK
;;;   ABOVE `do_newton_step`. *** It is the author working through the operand
;;;   order of `fdivp` and `fsubp` and getting it wrong four times before getting
;;;   it right. Read it as a worked example of the trap, because the trap is
;;;   real:
;;;       fdivp      st1 := st1 / st0, then pop
;;;       fsubp      st1 := st1 - st0, then pop
;;;       fdivrp     st1 := st0 / st1, then pop     (`r` = reversed)
;;;       fsubrp     st1 := st0 - st1, then pop
;;;   The value pushed FIRST is the left operand. Get it backwards and you
;;;   silently compute the reciprocal, or negate your answer -- no crash, no
;;;   warning, just a wrong number. That is why the working version pushes x
;;;   first, then f(x), then f'(x): the two pops then unwind in exactly the right
;;;   order to leave x - f/f'.
;;;
;;;   THE STRUCTURE IS WORTH COPYING. Three tiny helper functions, each with a
;;;   stated contract "FPU stack: EMPTY on entry, EMPTY on exit":
;;;       eval_f          [fx]    := f(x_cur)
;;;       eval_df         [dfx]   := f'(x_cur)
;;;       do_newton_step  [x_cur] := x_cur - fx/dfx
;;;   They communicate entirely through .bss memory, take no arguments and
;;;   return no values. That is unusual for C-style code and exactly right for
;;;   x87: passing floats in registers between functions would mean agreeing on
;;;   FPU stack depth across a call, which is a nightmare. Memory is the sane
;;;   interface, and the "EMPTY on entry, EMPTY on exit" rule is what makes the
;;;   whole program composable. Verify it with `info float` at each `ret`.
;;;
;;;   THE CONVERGENCE TEST is the other subtle part:
;;;       fld [fx] / fabs / fld [c_tol] / fucomip st0, st1
;;;   `fucomip` compares st0 with st1, sets the ORDINARY integer flags (so `jnc`
;;;   works afterwards), and POPS ONCE. It is the bridge from the FPU back into
;;;   the branch machinery -- without it you would have to route the FPU status
;;;   word through ax by hand.
;;;
;;;   COMPARING FLOATS AGAINST EXACT ZERO IS ALWAYS WRONG, which is why there is
;;;   a tolerance of 1e-12 at all. Rounding means f(x) will never be exactly 0.
;;;   code-0023.asm in "lectures code " makes the same point with its `epsilon`.
;;;
;;;   AND THERE IS A GUARD: `cmp r12d, 20 / jge .converged`. Newton's method does
;;;   not always converge -- start it near a point where f'(x) = 0 and it flies
;;;   off to infinity. An iteration cap is not optional in real numerical code.
;;;   Try `x_cur dq 0.0` and watch it: f'(0) = 0, so the first step divides by
;;;   zero.
;;;
;;;   A SMALL INACCURACY IN THE ORIGINAL COMMENTS: the line `fstp st0 ; pop tol`
;;;   actually pops |f(x)|, not tol -- `fucomip` had already popped tol as part
;;;   of comparing. The net effect (an empty stack) is correct either way.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/9/newton_raphson.asm"
;;;
;;;   Check the answer:
;;;   python3 -c "print('%.15f' % (2 ** (1/3)))"
;;;
;;;   Try other starting points by editing `x_cur dq 1.5`:
;;;       10.0     converges, but takes more iterations
;;;       -1.0     converges to... look carefully. x^3-2 has only ONE real root,
;;;                so it must come back to 1.2599 -- but watch the path it takes
;;;       0.0      f'(0) = 0: division by zero on the very first step
;;;
;;;   And change the function itself. To solve x^2 - 2 = 0 (i.e. find sqrt 2),
;;;   edit `eval_f` to compute x^2 - 2 and `eval_df` to compute 2x.
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/9/newton_raphson.asm"
;;;
;;;   THE session for this file -- watch the FPU stack stay balanced:
;;;     break eval_f
;;;     c
;;;     info float                EMPTY, as the contract promises
;;;     si si si si si            the five instructions
;;;     info float                EMPTY again
;;;     p (double)fx              f(x) at the current guess
;;;
;;;   Watch the Newton step, operand order and all:
;;;     break do_newton_step
;;;     c
;;;     si                        fld [x_cur]   -> stack: x
;;;     p $st0
;;;     si                        fld [fx]      -> stack: x  f(x)
;;;     si                        fld [dfx]     -> stack: x  f(x)  f'(x)
;;;     p $st0
;;;     p $st1
;;;     p $st2
;;;     si                        fdivp         -> stack: x  f/f'
;;;     p $st0                    the correction term
;;;     si                        fsubp         -> stack: x - f/f'
;;;     p $st0                    the new guess
;;;
;;;   Watch quadratic convergence as a number:
;;;     break printf
;;;     c
;;;     p $xmm1.v2_double[0]      f(x) this iteration
;;;     c
;;;     p $xmm1.v2_double[0]      ...and see the exponent roughly double
;;;
;;;   And catch the comparison that ends the loop:
;;;     break newton_raphson.asm:NN     NN on the `fucomip st0, st1` line
;;;     c
;;;     p $st0                    the tolerance, 1e-12
;;;     p $st1                    |f(x)|
;;;     si
;;;     info registers eflags     CF tells you which was larger
;;;     info float                one value left, and the next `fstp` clears it
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   TWO STACKS AGAIN, AND THIS FILE IS THE BEST PLACE IN THE COURSE TO SEE
;;;   THEM BEHAVING INDEPENDENTLY.
;;;
;;;   The call stack does what it always does: `bt` inside `eval_f` shows two
;;;   frames, `p $rsp` drops by 8 per `call`, and nothing recurses. Nothing
;;;   surprising.
;;;
;;;   The FPU stack, meanwhile, is governed by a CONTRACT THE AUTHOR WROTE DOWN
;;;   AND THEN KEPT: "EMPTY on entry, EMPTY on exit", stated in the header of
;;;   every one of the three helpers. Check it at each `ret`:
;;;       break eval_f
;;;       break eval_df
;;;       break do_newton_step
;;;       c
;;;       info float          empty
;;;       finish
;;;       info float          empty
;;;   Why does it matter? Because THERE ARE ONLY EIGHT SLOTS AND NO WAY TO GROW
;;;   THEM. If `eval_f` leaked one slot per call, this loop would break on the
;;;   eighth iteration -- silently, with NaNs rather than a crash. On the call
;;;   stack a leak of 8 bytes per call is invisible until you exhaust megabytes;
;;;   on the FPU stack you get eight chances. That is why x87 code is written
;;;   with an explicit depth contract on every function, and why the `fstp st0`
;;;   on the convergence test exists purely to discard a value nobody wants.
;;;
;;;   THE ALIGNMENT ARITHMETIC IS SPELLED OUT IN THE SOURCE and is worth
;;;   checking rather than trusting:
;;;       push rbp    rsp: 8 mod 16 -> 0
;;;       push r12    rsp: 0 -> 8
;;;       sub rsp, 8  rsp: 8 -> 0        <- the explicit re-alignment
;;;   so every `call printf` sees 8 mod 16, as the ABI promises. Verify:
;;;       break printf
;;;       c
;;;       p $rsp % 16               8
;;;   It matters more here than in an integer program: printf is being handed
;;;   doubles in xmm registers and will execute aligned SSE instructions on its
;;;   own stack memory, so a misaligned stack is a fault, not a slowdown. This is
;;;   exactly the situation printf_alignment_demo.asm in ps_code/5 exists to
;;;   teach, and here it is in a real program.
;;;
;;;   Note also that r12 -- the iteration counter -- is CALLEE-SAVED, pushed in
;;;   the prologue and popped in the epilogue. That is what lets it survive four
;;;   `call printf`s without ever being saved to memory. Compare code-0018.asm,
;;;   which puts its counters in the frame instead, and multboard.asm in
;;;   ps_code/6, which uses callee-saved registers but forgets to push them.
;;; ============================================================================

; ===========================================================================
; newton_raphson_v2.asm   —   CORRECTED FINAL VERSION
; x86-64 + x87 FPU
; Newton-Raphson root finding for  f(x) = x^3 - 2
; Root: x* = cbrt(2) ≈ 1.2599210498948732
;
; KEY FIXES vs v1:
;   1. FPU stack fully balanced at every point (no leftover values)
;   2. Newton step order corrected:  x_new = x - f(x)/f'(x)
;      uses fld / fdiv / fsub in the right sequence
;   3. Proper 16-byte stack alignment before every printf
;   4. Callee-saved registers r12 saved/restored correctly
;   5. All convergence comparisons use fucomip correctly
;   6. .note.GNU-stack section added (suppresses linker warning)
;
; Build:
;   nasm -f elf64 newton_raphson_v2.asm -o newton_raphson_v2.o
;   gcc  -no-pie -m64 newton_raphson_v2.o -o newton_raphson_v2
; Run:
;   ./newton_raphson_v2
; ===========================================================================

        global  main
        extern  printf
                                        ;   export `main` for the C library start-up

                                        ;   the only external function needed
; ---------------------------------------------------------------------------
section .data
; ---------------------------------------------------------------------------

x_cur   dq   1.5                        ; initial guess  x0 = 1.5
c_two   dq   2.0                        ; the constant 2 in f(x)=x^3-2
                                        ;   the starting guess x0. `dq` emits an 8-byte double.
                                        ;   Try 10.0, or -1.0, or 0.0 -- see the header.
c_three dq   3.0                        ; the constant 3 in f'(x)=3x^2
                                        ;   the 2 in f(x) = x^3 - 2
c_tol   dq   1.0e-12                    ; convergence tolerance
                                        ;   the 3 in f'(x) = 3x^2

                                        ;   the convergence tolerance. COMPARING A FLOAT AGAINST
                                        ;   EXACT ZERO IS ALWAYS WRONG -- rounding means f(x) never
                                        ;   reaches 0 exactly, so you need a threshold.
fmt_hdr db  "Newton-Raphson: f(x) = x^3 - 2,  x* = cbrt(2)", 10
        db  "---------------------------------------------------", 10, 0
                                        ;   a two-line header, built from two `db`s with only the
                                        ;   last terminated

fmt_row db  "  iter %2d:  x = %20.15f    f(x) = %20.15e", 10, 0

                                        ;   %2d is an int (in rsi), %20.15f and %20.15e are doubles
                                        ;   (in xmm0 and xmm1). The `e` conversion prints scientific
                                        ;   notation, which is what makes the convergence visible.
fmt_res db  "---------------------------------------------------", 10
        db  "Converged after %d iterations.", 10
                                        ;   the closing summary: an int and a double
        db  "Answer: x = %.15f", 10, 0

; ---------------------------------------------------------------------------
section .bss
                                        ;   zero-filled at load time. These two slots are how the
                                        ;   three helper functions communicate -- no arguments, no
                                        ;   return values, just shared memory.
; ---------------------------------------------------------------------------

fx      resq  1                         ; f(x_cur)
                                        ;   f evaluated at the current guess
dfx     resq  1                         ; f'(x_cur)
                                        ;   f' evaluated at the current guess

; ---------------------------------------------------------------------------
; Mark stack as non-executable (suppresses gcc/ld warning)
; ---------------------------------------------------------------------------
section .note.GNU-stack noalloc noexec nowrite progbits
                                        ;   the "no executable stack" marker, with the full set of
                                        ;   attributes

; ---------------------------------------------------------------------------
section .text
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; eval_f:
;   Computes f(x) = x^3 - 2  using the value in memory x_cur.
;   Stores result in memory fx.
;   FPU stack: EMPTY on entry, EMPTY on exit.
; ---------------------------------------------------------------------------
eval_f:
                                        ;   reads x_cur from memory, writes fx. No arguments, no
                                        ;   return value -- see the header.
        fld     qword [x_cur]           ; ST0 = x
                                        ;   push x.  FPU stack:  x
        fld     st0                     ; ST0 = x,   ST1 = x      (copy x)
                                        ;   DUPLICATE the top -- the RPN idiom for "use this twice".
                                        ;   stack:  x  x
        fmul    st0, st0                ; ST0 = x^2, ST1 = x
                                        ;   st0 := st0 * st0.  stack:  x  x^2
        fmulp   st1, st0                ; ST0 = x * x^2 = x^3    (st1*=st0, pop)
                                        ;   st1 := st1 * st0, then POP.  stack:  x^3
                                        ;   The `p` suffix always means "and pop".
        fsub    qword [c_two]           ; ST0 = x^3 - 2
                                        ;   st0 := st0 - [c_two].  stack:  x^3 - 2 = f(x)
        fstp    qword [fx]              ; [fx] = f(x),  pop → stack EMPTY
                                        ;   store and pop.  stack: EMPTY -- the contract is kept
        ret
                                        ;   back to the caller

; ---------------------------------------------------------------------------
; eval_df:
;   Computes f'(x) = 3*x^2  using the value in memory x_cur.
;   Stores result in memory dfx.
;   FPU stack: EMPTY on entry, EMPTY on exit.
; ---------------------------------------------------------------------------
eval_df:
                                        ;   reads x_cur, writes dfx. Same contract.
        fld     qword [x_cur]           ; ST0 = x
                                        ;   push x.  stack:  x
        fmul    st0, st0                ; ST0 = x^2
                                        ;   st0 := st0 * st0.  stack:  x^2
        fmul    qword [c_three]         ; ST0 = 3*x^2
                                        ;   st0 := st0 * 3.  stack:  3x^2 = f'(x)
        fstp    qword [dfx]             ; [dfx] = f'(x), pop → stack EMPTY
                                        ;   store and pop.  stack: EMPTY
        ret
                                        ;   back to the caller

; ---------------------------------------------------------------------------
; do_newton_step:
;   Computes x_cur = x_cur - f(x_cur) / f'(x_cur)
;   Reads fx and dfx from memory (call eval_f and eval_df first).
;   FPU stack: EMPTY on entry, EMPTY on exit.
;
                                        ;   THE BLOCK BELOW IS THE AUTHOR GETTING THE OPERAND ORDER
                                        ;   WRONG FOUR TIMES AND THEN RIGHT. Read it -- it is the
                                        ;   single most useful thing in the file. See the header.
;   Stack trace:
;       fld  [fx]   → ST0 = f(x)
;       fld  [dfx]  → ST0 = f'(x), ST1 = f(x)
;       fdivp       → ST0 = f(x)/f'(x)          [fdivp: ST1 /= ST0, pop]
;                     WAIT — fdivp does ST1/ST0 then pops.
;                     We want f(x)/f'(x), so load f(x) first, then f'(x):
;                       fld fx   → ST0=f(x)
;                       fld dfx  → ST0=f'(x), ST1=f(x)
;                       fdivr    → ST0 = ST1/ST0 = f(x)/f'(x)  (no pop)
;                       fld x    → ST0=x, ST1=ratio
;                       fsubrp   → ST0 = ST1-ST0 = ratio - x  WRONG
;
;   Cleaner approach: compute step = f/f', then subtract from x:
;       fld  [dfx]   → ST0 = f'(x)
;       fld  [fx]    → ST0 = f(x),   ST1 = f'(x)
;       fdivp        → ST0 = f'(x)/f(x)   NO — fdivp: ST1/=ST0 pop
;                                           ST0 = f'(x)/f(x)  STILL WRONG
;
;   CORRECT sequence (see below):
;       fld  [fx]    → ST0 = f(x)
;       fdiv [dfx]   → ST0 = f(x)/f'(x)      (divide ST0 by memory)
;       fld  [x_cur] → ST0 = x, ST1 = f(x)/f'(x)
;       fsubrp       → ST0 = ST1 - ST0 = (f/f') - x   WRONG sign
;
;   SIMPLEST correct approach:
;       fld  [x_cur] → ST0 = x
;       fld  [fx]    → ST0 = f(x),    ST1 = x
;       fld  [dfx]   → ST0 = f'(x),   ST1 = f(x),  ST2 = x
;       fdivp        → ST0 = f(x)/f'(x),  ST1 = x   [ST1/=ST0, pop]
;       fsubp        → ST0 = x - f(x)/f'(x)           [ST1-=ST0, pop]
;       fstp [x_cur] → store new x, pop → EMPTY  ✓
; ---------------------------------------------------------------------------
do_newton_step:
                                        ;   reads x_cur, fx and dfx; writes x_cur. Same contract.
        fld     qword [x_cur]           ; ST0 = x
                                        ;   push x FIRST, so it ends up DEEPEST and the two pops
                                        ;   below unwind in the right order.  stack:  x
        fld     qword [fx]              ; ST0 = f(x),    ST1 = x
                                        ;   stack:  x  f(x)
        fld     qword [dfx]             ; ST0 = f'(x),   ST1 = f(x),   ST2 = x
                                        ;   stack:  x  f(x)  f'(x)
        fdivp                           ; ST1 /= ST0, pop  → ST0 = f(x)/f'(x), ST1 = x
                                        ;   st1 := st1 / st0, then pop. The value pushed EARLIER is
                                        ;   the numerator.  stack:  x  f(x)/f'(x)
        fsubp                           ; ST1 -= ST0, pop  → ST0 = x - f(x)/f'(x)
                                        ;   st1 := st1 - st0, then pop.  stack:  x - f(x)/f'(x)
                                        ;   The Newton step, at last.
        fstp    qword [x_cur]           ; store, pop → EMPTY
                                        ;   store the new guess and pop.  stack: EMPTY
        ret
                                        ;   back to the caller

; ---------------------------------------------------------------------------
; main
; ---------------------------------------------------------------------------
main:
                                        ;   int main(void)
        push    rbp
                                        ;   prologue: save the caller's frame pointer. rsp: 8 -> 0 mod 16.
        mov     rbp, rsp
                                        ;   anchor the frame
        push    r12                     ; r12 = iteration counter (callee-saved)
                                        ;   r12 is CALLEE-SAVED, so it must be preserved -- and that
                                        ;   is exactly why it is safe to keep the loop counter there
                                        ;   across the printf calls. rsp: 0 -> 8 mod 16.
        sub     rsp, 8                  ; align rsp to 16 bytes
                                        ;   re-align: rsp back to 0 mod 16, so every `call` below
                                        ;   sees the 8 mod 16 the ABI promises. The author's
                                        ;   arithmetic in the next three lines is correct -- verify
                                        ;   it with `p $rsp % 16` at a breakpoint on printf.
                                        ; (8 from push rbp, 8 from push r12,
                                        ;  8 from sub = total 24 from rbp,
                                        ;  +8 ret addr = 32 → rsp is 16-aligned)

                                        ; --- print header ---
        mov     rdi,  fmt_hdr
                                        ;   printf argument 1: the format string
        xor     eax,  eax               ; 0 xmm register args
                                        ;   THE VARIADIC RULE: 0 vector registers carry arguments
                                        ;   for this call -- the header has no conversions.
        call    printf

                                        ; --- initialise iteration counter ---
        xor     r12d, r12d              ; r12 = 0
                                        ;   the iteration counter starts at 0. The 32-bit name also
                                        ;   zeroes the upper half of r12.

; ── Main Newton-Raphson loop ────────────────────────────────────────────────
.loop:
                                        ;   one pass = one Newton iteration. `.loop` is LOCAL to
                                        ;   main.
                                        ; -- evaluate f(x) and f'(x) --
        call    eval_f                  ; [fx]  ← f(x_cur)
                                        ;   fill [fx]
        call    eval_df                 ; [dfx] ← f'(x_cur)
                                        ;   fill [dfx]

                                        ; -- print this iteration --
                                        ; printf(fmt_row, iter:int, x_cur:double, fx:double)
        mov     rdi,  fmt_row
                                        ;   printf argument 1
        mov     esi,  r12d              ; arg2 = iteration (int in rsi)
                                        ;   argument 2: the iteration number, an INT, so it goes in
                                        ;   an integer register
        movsd   xmm0, [x_cur]           ; arg3 = x  (double)
                                        ;   argument 3: x, a DOUBLE, so it goes in xmm0
        movsd   xmm1, [fx]              ; arg4 = f(x) (double)
                                        ;   argument 4: f(x), in xmm1. Integer and float arguments
                                        ;   are counted in SEPARATE sequences -- rsi is the first
                                        ;   integer, xmm0 the first float.
        mov     eax,  2                 ; 2 xmm args used
                                        ;   TWO vector registers carry arguments this time
        call    printf

                                        ; -- convergence test: |f(x)| < tolerance --
        fld     qword [fx]              ; ST0 = f(x)
                                        ;   push f(x).  stack:  f(x)
        fabs                            ; ST0 = |f(x)|
                                        ;   absolute value, in place.  stack:  |f(x)|
        fld     qword [c_tol]           ; ST0 = tol,  ST1 = |f(x)|
                                        ;   push the tolerance.  stack:  |f(x)|  tol
        fucomip st0, st1                ; compare tol with |f(x)|
                                        ;   compare st0 with st1, set the ORDINARY integer flags,
                                        ;   and POP ONCE. This is the bridge from the FPU back into
                                        ;   the branch machinery.  stack:  |f(x)|
                                        ;   fucomip sets:
                                        ;     ZF=1,CF=0  if ST0 == ST1   (tol == |f(x)|)
                                        ;     CF=0       if ST0 > ST1    (tol > |f(x)|)  → CONVERGED
                                        ;     CF=1       if ST0 < ST1    (tol < |f(x)|)  → not yet
        fstp    st0                     ; pop tol → stack EMPTY
                                        ;   pop the remaining value and discard it.  stack: EMPTY
                                        ;   (the original comment says "pop tol", but fucomip
                                        ;   already popped tol -- this pops |f(x)|. The net effect,
                                        ;   an empty stack, is what matters.)
        jnc     .converged              ; CF=0 → tol >= |f(x)| → done
                                        ;   CF = 0 means tol >= |f(x)|: close enough, stop

                                        ; -- guard: stop after 20 iterations --
        inc     r12d
                                        ;   one more iteration done
        cmp     r12d, 20
                                        ;   THE GUARD. Newton's method does not always converge --
                                        ;   an iteration cap is not optional in real numerical code.
        jge     .converged
                                        ;   give up and report whatever we have

                                        ; -- Newton step: x = x - f(x)/f'(x) --
        call    do_newton_step
                                        ;   x := x - f(x)/f'(x)

        jmp     .loop
                                        ;   round again

; ── Done ────────────────────────────────────────────────────────────────────
.converged:
                                        ;   the shared exit, reached either by convergence or by the
                                        ;   iteration cap
        mov     rdi,  fmt_res
                                        ;   printf argument 1
        mov     esi,  r12d              ; number of iterations
                                        ;   argument 2: how many iterations (an int)
        movsd   xmm0, [x_cur]           ; final x
                                        ;   argument 3: the final answer (a double, in xmm0)
        mov     eax,  1
                                        ;   ONE vector register this time
        call    printf

        xor     eax, eax                ; return 0
                                        ;   main's return value: 0 = success
        add     rsp, 8
                                        ;   undo the alignment padding...
        pop     r12
                                        ;   ...restore the callee-saved register...
        pop     rbp
                                        ;   ...and the caller's frame pointer. IN REVERSE ORDER to
                                        ;   the prologue -- the stack is last-in first-out.
        ret
                                        ;   pop the return address into rip

