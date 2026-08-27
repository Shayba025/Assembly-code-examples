;;; ============================================================================
;;; muller_demo.asm -- Muller's method, and COMPLEX ARITHMETIC written by hand
;;; Practice session 10                      (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Finds a root of T3(x) = 4x^3 - 3x by Muller's method, printing every
;;;   iteration so you can watch it converge.
;;;   (Verified: reaches 0.866025403613409 by iteration 3 and 0.8660254037844386
;;;   -- the exact cos(pi/6) to sixteen digits -- shortly after.)
;;;
;;;   MULLER'S METHOD IN ONE PARAGRAPH. Newton's method (see newton_raphson.asm
;;;   in ps_code/9) fits a straight LINE through one point using the derivative.
;;;   The secant method fits a line through two points and needs no derivative.
;;;   Muller fits a PARABOLA through THREE points and takes its root nearest the
;;;   newest one. More work per step, but it converges at order ~1.84 instead of
;;;   1.62, and -- the real prize -- IT CAN FIND COMPLEX ROOTS FROM REAL
;;;   STARTING POINTS, because the parabola's discriminant may be negative.
;;;
;;;   THE STEP, in the same order the code performs it:
;;;       h0 = x1 - x0            h1  = x2 - x1
;;;       d0 = (f1-f0)/h0         d1  = (f2-f1)/h1
;;;       A  = (d1-d0)/(h1+h0)    B   = A*h1 + d1        C = f2
;;;       disc = sqrt(B^2 - 4AC)
;;;       den  = whichever of B+disc, B-disc is LARGER in magnitude
;;;       x3 = x2 - 2C/den
;;;   Then slide the window along -- x0,x1,x2 := x1,x2,x3 -- and repeat.
;;;
;;;   *** WHY `den` IS THE LARGER OF THE TWO. *** The quadratic formula is
;;;   usually written (-b +/- sqrt(disc))/2a, but that form CANCELS
;;;   CATASTROPHICALLY when b and sqrt(disc) are nearly equal: you subtract two
;;;   close numbers and lose most of your significant digits. The equivalent form
;;;   2C/(B +/- disc) has no such cancellation PROVIDED you pick the sign that
;;;   makes the denominator BIG. That is what the `cmag2`/`fcomip`/`jb .use_bm`
;;;   block does, and it is a genuine numerical-analysis technique rather than
;;;   an implementation detail.
;;;
;;;   ------------------------------------------------------------------
;;;   THE OTHER HALF OF THE FILE: COMPLEX ARITHMETIC FROM NOTHING
;;;   ------------------------------------------------------------------
;;;   x86 has no complex type. So this file builds one:
;;;
;;;   A COMPLEX NUMBER IS SIXTEEN BYTES -- two doubles, real part first:
;;;       [z]     the real part
;;;       [z+8]   the imaginary part
;;;   Every variable in .bss is declared `resq 2` for exactly this reason. That
;;;   convention, and nothing else, is what makes `mx0` a complex number.
;;;
;;;   AND SIX FUNCTIONS IMPLEMENT THE ARITHMETIC, all with the same signature
;;;   rdi = destination, rsi = first operand, rdx = second:
;;;       cadd   (a+bi) + (c+di) = (a+c) + (b+d)i
;;;       csub   likewise
;;;       cmul   (a+bi)(c+di) = (ac - bd) + (ad + bc)i
;;;       cdiv   multiply top and bottom by the conjugate; the denominator
;;;              becomes the real number c^2+d^2
;;;       csqrt  the principal square root, via the half-angle formulae
;;;       cmag2  |z|^2 = a^2 + b^2, returned ON THE FPU STACK
;;;   Read `cmul` and check it against the algebra by hand once -- four
;;;   multiplications, one subtraction, one addition, in exactly that order.
;;;
;;;   NOTE THAT THE RESULT IS RETURNED THROUGH A POINTER, not in a register.
;;;   That is forced: a complex number is 16 bytes, xmm registers are
;;;   caller-saved, and there is nowhere to put a two-part value across a call.
;;;   It is the same reasoning that makes C return large structs through a hidden
;;;   pointer argument.
;;;
;;;   `ceval` EVALUATES THE POLYNOMIAL AT A COMPLEX POINT, by Horner's rule --
;;;   the same recurrence as fma_horner.asm in ps_code/11 and code-0016.asm in
;;;   "lectures code ", now with complex multiplication.
;;;
;;;   THE ODDEST FRAGMENT IN THE FILE is inside `csqrt`:
;;;       ftst / fnstsw ax / fstp st0 / sahf / jnc .pos / fchs
;;;   That is the OLD way of branching on a floating-point comparison, from
;;;   before `fcomip` existed. `ftst` compares st0 with zero and sets the FPU's
;;;   own status word; `fnstsw ax` copies that word into ax; `sahf` loads ah into
;;;   the ordinary FLAGS register; and only then can `jnc` work. Four
;;;   instructions to do what `fcomip` does in one -- and the file uses `fcomip`
;;;   elsewhere, so you can compare them directly. It is here to make the sign of
;;;   the imaginary part match the input's, as the principal square root requires.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/10/muller_demo.asm"
;;;
;;;   Check the target:
;;;   python3 -c "import math; print('%.16f' % math.cos(math.pi/6))"
;;;
;;;   Change the seeds `s0r`, `s1r`, `s2r` to -0.9, -0.7, -0.5 and it should find
;;;   the negative root. Seed it near 0 and it finds the root at 0. And if you
;;;   change `coef` to a polynomial with no real roots -- say x^2 + 1, i.e.
;;;   `dq 1.0, 0.0, 1.0` with `deg 2` -- watch the imaginary column come alive.
;;;   THAT is what Muller's method is for.
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/10/muller_demo.asm"
;;;
;;;   Watch one complex multiplication:
;;;     break cmul
;;;     c
;;;     p *(double*)$rsi          the first operand's real part
;;;     p *(double*)($rsi+8)      ...and its imaginary part
;;;     p *(double*)$rdx          the second operand
;;;     finish
;;;     p *(double*)$rdi          the product -- check it against (ac-bd)
;;;     p *(double*)($rdi+8)      ...and (ad+bc)
;;;
;;;   Watch the parabola's coefficients being built:
;;;     break muller_demo.asm:NN  NN on the `call csqrt` line
;;;     c
;;;     p *(double*)&mA           A
;;;     p *(double*)&mB           B
;;;     p *(double*)&mC           C
;;;     p *(double*)&mt1          B^2 - 4AC, the discriminant
;;;
;;;   And catch the numerically important choice:
;;;     break muller_demo.asm:NN  NN on the `jb .use_bm` line
;;;     c
;;;     p $st0                    |B - disc|^2
;;;     p $st1                    |B + disc|^2
;;;     si                        and see which branch is taken -- always the
;;;                               LARGER, to avoid cancellation
;;;
;;;   Watch convergence as a number:
;;;     break printf
;;;     c
;;;     p $xmm2.v2_double[0]      |f(x)| this iteration
;;;     c
;;;     p $xmm2.v2_double[0]      ...and see the exponent collapse
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THIS IS BY FAR THE MOST CALL-HEAVY PROGRAM IN THE COURSE. One Muller
;;;   iteration makes about twenty calls to the complex helpers, and the whole
;;;   thing is built out of them. Count them:
;;;       break cmul
;;;       ignore 1 100000
;;;       c
;;;       info breakpoints        the hit count
;;;
;;;   AND YET `bt` NEVER SHOWS MORE THAN THREE FRAMES. The helpers do not call
;;;   each other, and the deepest nesting is main -> ceval -> cmul. There is no
;;;   recursion anywhere. That is worth noticing because the program FEELS deeply
;;;   nested when you read it -- the nesting is in the DATA FLOW, not in the
;;;   stack. Every intermediate result goes to a named .bss slot and the next
;;;   call reads it back.
;;;
;;;   *** WHICH IS THE REAL LESSON HERE: LOOK AT ALL THOSE .bss VARIABLES. ***
;;;   mh0, mh1, md0, md1, mA, mB, mC, mdsc, mden, mt1, mt2, mbp, mbm, mnum, mq,
;;;   mdel -- sixteen complex temporaries, thirty-two doubles. None of them is a
;;;   stack local, and none could be:
;;;       * the FPU stack has eight slots and none survive a call;
;;;       * ALL SIXTEEN xmm registers are CALLER-SAVED, so no vector register
;;;         survives either;
;;;       * a complex value is 16 bytes, so it needs a pointer to be passed at
;;;         all -- hence rdi as a destination in every helper.
;;;   With more live values than registers and every call destroying what
;;;   registers there are, STATIC MEMORY IS NOT A FALLBACK, IT IS THE DESIGN.
;;;   You met the same conclusion in lagrange_final.asm and gauss_chebyshev.asm.
;;;
;;;   THE PRICE is that none of this is reentrant. Two threads calling `cmul`
;;;   would be fine (it only touches its arguments), but two threads inside the
;;;   Muller loop would trample each other's `mt1`. Turning the .bss block into a
;;;   stack frame -- `sub rsp, 16*16` and offsets from rbp -- is the fix, and it
;;;   is a genuinely good exercise: the frame diagrams in code-0018.asm and
;;;   code-0021.asm show you the shape.
;;;
;;;   Finally, note the helpers' own discipline. `ceval` pushes rbx, r14 and r15
;;;   -- CALLEE-SAVED registers -- because it needs three values to survive the
;;;   `call cmul` in its loop. The other five helpers push nothing at all,
;;;   because they call nothing and use only caller-saved registers and the FPU.
;;;   Prologue size follows from what a function actually needs, and these six
;;;   functions demonstrate both ends of that.
;;; ============================================================================

; ============================================================================
;  muller_demo.asm -- Trace Muller's method, iteration by iteration, on the
;                     Chebyshev polynomial T3(x) = 4x^3 - 3x.
;                     Real roots: 0 and +/- cos(pi/6) = +/- 0.8660254...
;
;  Starting from the three real points 0.5, 0.7, 0.9 the iteration converges
;  to cos(pi/6).  Each line prints the new approximation x and the residual
;  |f(x)|, so you can watch the quadratic (~1.84-order) convergence.
;
;  Build:  nasm -f elf64 muller_demo.asm -o muller_demo.o
;          gcc  -no-pie  muller_demo.o   -o muller_demo  &&  ./muller_demo
; ============================================================================
global  main
                                        ;   export `main` for the C library start-up
extern  printf
                                        ;   the only external function needed

%define MAXIT 40
                                        ;   `%define` is a preprocessor substitution: an iteration cap,
                                        ;   because no root-finder is guaranteed to converge

section .rodata
                                        ;   READ-ONLY data: strings that are never written
hdr  db "Muller on T3(x) = 4x^3 - 3x   (root sought: cos(pi/6) = 0.8660254038)",10
                                        ;   a three-line header, only the last `db` terminated
     db "------------------------------------------------------------------------",10
     db " iter         x (real part)        x (imag part)        | f(x) |",10,0
row  db "  %2d   %+.15f   %+.2e   %.3e",10,0
                                        ;   an int and THREE doubles -- counted in separate sequences,
                                        ;   so esi holds the int and xmm0..xmm2 the doubles
fin  db "------------------------------------------------------------------------",10
                                        ;   the closing line: one double
     db "converged to x = %.16f   (exact cos(pi/6) = 0.8660254037844386)",10,0

section .data
                                        ;   initialised, writable data
align 8
                                        ;   pad to an 8-byte boundary
coef  dq 0.0, -3.0, 0.0, 4.0            ; T3 : c0=0, c1=-3, c2=0, c3=4
                                        ;   T3(x) = 4x^3 - 3x, coefficients LOW ORDER FIRST. Change
                                        ;   this (and `deg`) to hunt a different polynomial.
deg   dq 3
                                        ;   the degree, so `ceval` knows where to start Horner
s0r dq 0.5
                                        ;   the three seed points. Muller needs THREE, not one --
                                        ;   it fits a parabola.
s1r dq 0.7
s2r dq 0.9
four dq 4.0
                                        ;   x87 cannot take an immediate, so 4.0 lives in memory
tol2 dq 1.0e-32
                                        ;   the convergence tolerance, squared -- so the test can
                                        ;   compare against |delta|^2 and skip a square root

section .bss
                                        ;   zero-filled at load time
align 8
                                        ;   pad to an 8-byte boundary
itc  resd 1
                                        ;   the iteration counter, a 32-bit int
mret resq 1
                                        ;   declared and unused
ev_acc resq 2
                                        ;   `ceval`'s Horner accumulator: TWO quadwords, because it is
                                        ;   complex
cdiv_den resq 1
                                        ;   scratch inside cdiv and cmag2
csqrt_m resq 1
                                        ;   scratch inside csqrt
mx0 resq 2
                                        ;   *** EVERY `resq 2` BELOW IS ONE COMPLEX NUMBER: sixteen
                                        ;   bytes, real part at [z] and imaginary part at [z+8]. That
                                        ;   convention is the entire type system. ***
                                        ;   mx0..mx2 are the three current points, mx3 the new one.
mx1 resq 2
mx2 resq 2
mx3 resq 2
mf0 resq 2
                                        ;   the polynomial values at those points
mf1 resq 2
mf2 resq 2
mf3 resq 2
mh0 resq 2
                                        ;   h0 = x1-x0, h1 = x2-x1
mh1 resq 2
md0 resq 2
                                        ;   the divided differences d0 and d1
md1 resq 2
mA  resq 2
                                        ;   the parabola's coefficients A, B, C
mB  resq 2
mC  resq 2
mdsc resq 2
                                        ;   the discriminant sqrt(B^2 - 4AC)
mden resq 2
                                        ;   the chosen denominator
mt1 resq 2
                                        ;   general-purpose temporaries
mt2 resq 2
mbp resq 2
                                        ;   B + disc and B - disc, the two candidate denominators
mbm resq 2
mnum resq 2
                                        ;   2C, the numerator
mq  resq 2
                                        ;   the correction 2C/den
mdel resq 2
                                        ;   x3 - x2, whose magnitude drives the convergence test

section .text
                                        ;   the executable-code section
; ---- complex helpers (rdi=dst, rsi=a, rdx=b) ----
cadd:
                                        ;   void cadd(complex *dst, const complex *a, const complex *b)
                                        ;   (a+bi) + (c+di) = (a+c) + (b+d)i. The result goes through
                                        ;   a POINTER, because 16 bytes will not fit in a register.
        fld qword [rsi]
                                        ;   push a.re
        fadd qword [rdx]
                                        ;   st0 := a.re + b.re
        fld qword [rsi+8]
                                        ;   push a.im.  FPU stack:  re-sum   a.im
        fadd qword [rdx+8]
                                        ;   st0 := a.im + b.im
        fstp qword [rdi+8]
                                        ;   store the IMAGINARY part first -- it is on top of the FPU
                                        ;   stack, and `fstp` always pops the top
        fstp qword [rdi]
                                        ;   ...then the real part.  stack: EMPTY
        ret
                                        ;   pop the return address into rip. No frame at all.
csub:
                                        ;   void csub(...) -- identical, with subtraction
        fld qword [rsi]
        fsub qword [rdx]
        fld qword [rsi+8]
        fsub qword [rdx+8]
        fstp qword [rdi+8]
        fstp qword [rdi]
        ret
cmul:
                                        ;   void cmul(...)  (a+bi)(c+di) = (ac - bd) + (ad + bc)i.
                                        ;   Four multiplications, one subtraction, one addition.
        fld qword [rsi]
                                        ;   push a.re
        fmul qword [rdx]
                                        ;   st0 := a.re * b.re
        fld qword [rsi+8]
                                        ;   push a.im
        fmul qword [rdx+8]
                                        ;   st0 := a.im * b.im.  stack:  ac   bd
        fsubp st1, st0
                                        ;   st1 := st1 - st0, then pop.  stack:  ac - bd = the REAL part
        fld qword [rsi]
                                        ;   push a.re
        fmul qword [rdx+8]
                                        ;   st0 := a.re * b.im
        fld qword [rsi+8]
                                        ;   push a.im
        fmul qword [rdx]
                                        ;   st0 := a.im * b.re.  stack:  (ac-bd)   ad   bc
        faddp st1, st0
                                        ;   st1 := st1 + st0, then pop.  stack:  (ac-bd)   (ad+bc)
        fstp qword [rdi+8]
                                        ;   store the imaginary part (on top)...
        fstp qword [rdi]
                                        ;   ...then the real part.  stack: EMPTY
        ret
cdiv:
                                        ;   void cdiv(...) -- multiply top and bottom by the CONJUGATE
                                        ;   of b, which makes the denominator the real number c^2+d^2
        fld qword [rdx]
                                        ;   push b.re
        fmul st0, st0
                                        ;   st0 := b.re^2
        fld qword [rdx+8]
                                        ;   push b.im
        fmul st0, st0
                                        ;   st0 := b.im^2
        faddp st1, st0
                                        ;   st1 += st0, pop.  stack:  |b|^2
        fstp qword [cdiv_den]
                                        ;   park the (real) denominator in memory
        fld qword [rsi]
                                        ;   push a.re
        fmul qword [rdx]
                                        ;   st0 := a.re * b.re
        fld qword [rsi+8]
                                        ;   push a.im
        fmul qword [rdx+8]
                                        ;   st0 := a.im * b.im
        faddp st1, st0
                                        ;   st1 += st0, pop.  stack:  ac + bd
        fdiv qword [cdiv_den]
                                        ;   ...divided by |b|^2 = the REAL part of the quotient
        fld qword [rsi+8]
                                        ;   push a.im
        fmul qword [rdx]
                                        ;   st0 := a.im * b.re
        fld qword [rsi]
                                        ;   push a.re
        fmul qword [rdx+8]
                                        ;   st0 := a.re * b.im
        fsubp st1, st0
                                        ;   st1 -= st0, pop.  stack:  re-part   (bc - ad)
        fdiv qword [cdiv_den]
                                        ;   ...divided by |b|^2 = the IMAGINARY part
        fstp qword [rdi+8]
                                        ;   store the imaginary part (on top)...
        fstp qword [rdi]
                                        ;   ...then the real part.  stack: EMPTY
        ret
csqrt:
                                        ;   void csqrt(complex *dst, const complex *z) -- the PRINCIPAL
                                        ;   square root, by the half-angle formulae:
                                        ;     re = sqrt((|z| + z.re)/2),  im = +/-sqrt((|z| - z.re)/2)
                                        ;   with the sign of im matching the sign of z.im.
        fld qword [rsi]
                                        ;   push z.re
        fmul st0, st0
                                        ;   st0 := z.re^2
        fld qword [rsi+8]
                                        ;   push z.im
        fmul st0, st0
                                        ;   st0 := z.im^2
        faddp st1, st0
                                        ;   st1 += st0, pop
        fsqrt
                                        ;   st0 := |z|, the modulus
        fst qword [csqrt_m]
                                        ;   `fst`, NOT `fstp`: store to memory and KEEP it, because
                                        ;   the imaginary half needs it too
        fadd qword [rsi]
                                        ;   st0 := |z| + z.re
        fld1
                                        ;   push 1.0...
        fld1
                                        ;   ...and another...
        faddp st1, st0
                                        ;   ...and add them: st0 = 2.0. x87 cannot take an immediate,
                                        ;   so this is how you get the constant 2 without a memory slot.
        fdivp st1, st0
                                        ;   st1 /= st0, pop.  stack:  (|z| + z.re)/2
        fsqrt
                                        ;   st0 := its square root = the REAL part
        fstp qword [rdi]
                                        ;   store and pop
        fld qword [csqrt_m]
                                        ;   reload the modulus that `fst` kept for us
        fsub qword [rsi]
                                        ;   st0 := |z| - z.re
        fld1
                                        ;   build 2.0 again...
        fld1
        faddp st1, st0
        fdivp st1, st0
                                        ;   ...and divide
        fsqrt
                                        ;   st0 := sqrt((|z| - z.re)/2) = the magnitude of the
                                        ;   imaginary part. Its SIGN is decided next.
        fld qword [rsi+8]
                                        ;   push z.im, to look at its sign
        ftst
                                        ;   THE OLD WAY OF BRANCHING ON A FLOAT. `ftst` compares st0
                                        ;   with 0 and sets the FPU's OWN status word.
        fnstsw ax
                                        ;   copy that status word into ax -- the ordinary FLAGS
                                        ;   register cannot see it directly
        fstp st0
                                        ;   discard z.im; we only wanted its sign
        sahf
                                        ;   Store AH into Flags: NOW `jnc` can read the comparison.
                                        ;   FOUR INSTRUCTIONS to do what `fcomip` does in one -- and
                                        ;   this same file uses `fcomip` twice below, so you can
                                        ;   compare them directly.
        jnc .pos
                                        ;   z.im >= 0: keep the positive root
        fchs
                                        ;   otherwise negate, so the sign matches the input
.pos:
        fstp qword [rdi+8]
                                        ;   store the imaginary part.  stack: EMPTY
        ret
cmag2:
                                        ;   double cmag2(const complex *z) -- |z|^2, LEFT ON THE FPU
                                        ;   STACK rather than stored. The one helper with a different
                                        ;   convention, because its caller always wants to compare it
                                        ;   immediately.
        fld qword [rsi]
        fmul st0, st0
        fld qword [rsi+8]
        fmul st0, st0
        faddp st1, st0
                                        ;   st1 += st0, pop.  stack:  |z|^2, for the caller to consume
        ret

ceval:                                  ; rdi=dst, rsi=z  (P over coef[0..deg])
                                        ;   void ceval(complex *dst, const complex *z) -- evaluate the
                                        ;   polynomial at z by HORNER'S RULE, the same recurrence as
                                        ;   fma_horner.asm in ps_code/11 and code-0016.asm.
        push rbx
                                        ;   THREE CALLEE-SAVED REGISTERS pushed, because this function
                                        ;   calls cmul in its loop and needs three values to survive
        push r14
        push r15
        mov rbx, rdi
                                        ;   park the destination...
        mov r14, rsi
                                        ;   ...and the point
        mov rax, [deg]
                                        ;   start Horner at the TOP coefficient
        fld qword [coef + rax*8]
                                        ;   acc.re := coef[deg]
        fstp qword [ev_acc]
        fldz
                                        ;   acc.im := 0 -- the coefficients are real
        fstp qword [ev_acc+8]
        mov r15, rax
                                        ;   the coefficient index, walking downwards
        dec r15
.l:
                                        ;   `.l` is LOCAL to ceval
        test r15, r15
                                        ;   `js` = jump if SIGN, i.e. if r15 went negative: done
        js .d
        lea rdi, [ev_acc]
                                        ;   acc := acc * z. Note dst and src1 are THE SAME slot --
                                        ;   cmul reads both operands fully before writing, so that is
                                        ;   safe.
        lea rsi, [ev_acc]
        mov rdx, r14
        call cmul
        fld qword [ev_acc]
                                        ;   ...then add the next coefficient to the REAL part only
                                        ;   (the coefficients are real, so the imaginary part is
                                        ;   untouched)
        fadd qword [coef + r15*8]
        fstp qword [ev_acc]
        dec r15
                                        ;   next coefficient down
        jmp .l
.d:
                                        ;   copy the accumulator to the destination, sixteen bytes
                                        ;   in two 8-byte moves
        mov rax, [ev_acc]
        mov [rbx], rax
        mov rax, [ev_acc+8]
        mov [rbx+8], rax
        pop r15
                                        ;   restore the callee-saved registers IN REVERSE ORDER
        pop r14
        pop rbx
        ret
                                        ;   pop the return address into rip

; ============================================================================
main:
                                        ;   int main(void)
        push rbp
                                        ;   prologue: save the caller's frame pointer
        mov rbp, rsp
        push rbx
                                        ;   rbx and r12 are CALLEE-SAVED; three pushes take rsp from
                                        ;   8 mod 16 to 0, which is correct at a `call`
        push r12                        ; 3 pushes -> 16-aligned
        and rsp, -16
                                        ;   and round down anyway, belt and braces

        lea rdi, [hdr]
                                        ;   the header
        xor eax, eax
        call printf

                                        ; seed triple (real)
                                        ;   seed the three starting points, all with zero imaginary
                                        ;   part -- Muller will introduce complex values by itself if
                                        ;   the discriminant goes negative
        mov rax, [s0r]
        mov [mx0], rax
        xor rax, rax
        mov [mx0+8], rax
        mov rax, [s1r]
        mov [mx1], rax
        mov qword [mx1+8], 0
        mov rax, [s2r]
        mov [mx2], rax
        mov qword [mx2+8], 0
        lea rdi,[mf0]
                                        ;   f0 = P(x0)
        lea rsi,[mx0]
        call ceval
        lea rdi,[mf1]
                                        ;   f1 = P(x1)
        lea rsi,[mx1]
        call ceval
        lea rdi,[mf2]
                                        ;   f2 = P(x2)
        lea rsi,[mx2]
        call ceval
        mov dword [itc], 0
                                        ;   the iteration counter
        mov r12d, MAXIT
                                        ;   the iteration CAP -- no root-finder is guaranteed to
                                        ;   converge
.iter:
                                        ;   one pass = one Muller step. `.iter` is LOCAL to main.
        lea rdi,[mh0]
        lea rsi,[mx1]
        lea rdx,[mx0]
        call csub
                                        ;   h0 = x1 - x0
        lea rdi,[mh1]
        lea rsi,[mx2]
        lea rdx,[mx1]
        call csub
                                        ;   h1 = x2 - x1
        lea rdi,[mt1]
        lea rsi,[mf1]
        lea rdx,[mf0]
        call csub
                                        ;   t1 = f1 - f0
        lea rdi,[md0]
        lea rsi,[mt1]
        lea rdx,[mh0]
        call cdiv
                                        ;   d0 = (f1-f0)/h0 -- the first divided difference
        lea rdi,[mt1]
        lea rsi,[mf2]
        lea rdx,[mf1]
        call csub
                                        ;   t1 = f2 - f1
        lea rdi,[md1]
        lea rsi,[mt1]
        lea rdx,[mh1]
        call cdiv
                                        ;   d1 = (f2-f1)/h1
        lea rdi,[mt1]
        lea rsi,[md1]
        lea rdx,[md0]
        call csub
                                        ;   t1 = d1 - d0
        lea rdi,[mt2]
        lea rsi,[mh1]
        lea rdx,[mh0]
        call cadd
                                        ;   t2 = h1 + h0
        lea rdi,[mA]
        lea rsi,[mt1]
        lea rdx,[mt2]
        call cdiv
                                        ;   A = (d1-d0)/(h1+h0) -- the parabola's leading coefficient
        lea rdi,[mt1]
        lea rsi,[mA]
        lea rdx,[mh1]
        call cmul
                                        ;   t1 = A * h1
        lea rdi,[mB]
        lea rsi,[mt1]
        lea rdx,[md1]
        call cadd
                                        ;   B = A*h1 + d1
        mov rax,[mf2]
                                        ;   C = f2, copied sixteen bytes at a time
        mov [mC],rax
        mov rax,[mf2+8]
        mov [mC+8],rax
        lea rdi,[mt1]
        lea rsi,[mB]
        lea rdx,[mB]
        call cmul
                                        ;   t1 = B * B
        lea rdi,[mt2]
        lea rsi,[mA]
        lea rdx,[mC]
        call cmul
                                        ;   t2 = A * C
        fld qword [mt2]
                                        ;   ...times 4, one component at a time. There is no complex
                                        ;   scalar-multiply helper, so it is done by hand.
        fmul qword [four]
        fstp qword [mt2]
        fld qword [mt2+8]
        fmul qword [four]
        fstp qword [mt2+8]
        lea rdi,[mt1]
                                        ;   t1 = B^2 - 4AC, the discriminant
        lea rsi,[mt1]
        lea rdx,[mt2]
        call csub
        lea rdi,[mdsc]
        lea rsi,[mt1]
        call csqrt
                                        ;   disc = sqrt(B^2 - 4AC). MAY BE COMPLEX -- and that is
                                        ;   exactly how Muller reaches complex roots from real seeds.
        lea rdi,[mbp]
        lea rsi,[mB]
        lea rdx,[mdsc]
        call cadd
                                        ;   bp = B + disc
        lea rdi,[mbm]
        lea rsi,[mB]
        lea rdx,[mdsc]
        call csub
                                        ;   bm = B - disc
        lea rsi,[mbp]
        call cmag2
                                        ;   |B + disc|^2, left on the FPU stack
        fstp qword [cdiv_den]
                                        ;   park it
        lea rsi,[mbm]
        call cmag2
                                        ;   |B - disc|^2, on the FPU stack
        fld qword [cdiv_den]
                                        ;   reload the other one.  stack:  |bm|^2   |bp|^2
        fcomip st0, st1
                                        ;   compare st0 with st1, set the ORDINARY flags, and POP.
                                        ;   ONE instruction -- contrast the four-instruction
                                        ;   ftst/fnstsw/sahf sequence in csqrt above.
        fstp st0
                                        ;   discard the survivor.  stack: EMPTY
        jb .use_bm
                                        ;   *** THE NUMERICALLY IMPORTANT CHOICE: take whichever
                                        ;   denominator is LARGER in magnitude. The form 2C/(B+/-disc)
                                        ;   avoids the catastrophic cancellation that (-b+/-sqrt)/2a
                                        ;   suffers when b and sqrt(disc) are close. ***
        mov rax,[mbp]
        mov [mden],rax
        mov rax,[mbp+8]
        mov [mden+8],rax
        jmp .den_done
.use_bm:
        mov rax,[mbm]
        mov [mden],rax
        mov rax,[mbm+8]
        mov [mden+8],rax
.den_done:
                                        ;   the shared continuation
        fld qword [mC]
                                        ;   num = 2C. `fadd st0, st0` doubles by adding a value to
                                        ;   itself -- cheaper than a multiply, and exact.
        fadd st0, st0
        fstp qword [mnum]
        fld qword [mC+8]
        fadd st0, st0
        fstp qword [mnum+8]
        lea rdi,[mq]
                                        ;   q = 2C/den, the correction
        lea rsi,[mnum]
        lea rdx,[mden]
        call cdiv
        lea rdi,[mx3]
                                        ;   x3 = x2 - q, the new approximation
        lea rsi,[mx2]
        lea rdx,[mq]
        call csub
        lea rdi,[mf3]
                                        ;   f3 = P(x3)
        lea rsi,[mx3]
        call ceval
        lea rdi,[mdel]
        lea rsi,[mx3]
                                        ;   delta = x3 - x2, the step size
        lea rdx,[mx2]
        call csub

                                        ; ---- print this iteration ----
        inc dword [itc]
                                        ;   one more iteration done
        lea rsi,[mf3]
                                        ;   |f3|^2, on the FPU stack...
        call cmag2
        fsqrt
                                        ;   ...square-rooted to |f3|...
        fstp qword [cdiv_den]           ; |f3|
                                        ;   ...and parked for printf
        mov esi, [itc]
                                        ;   printf argument 2: the iteration number, an INT
        movsd xmm0, [mx3]               ; Re
                                        ;   the real part, in xmm0...
        movsd xmm1, [mx3+8]             ; Im
                                        ;   ...the imaginary part, in xmm1...
        movsd xmm2, [cdiv_den]          ; |f|
                                        ;   ...and the residual, in xmm2
        lea rdi,[row]
        mov al, 3
                                        ;   THREE vector registers carry arguments
        call printf

                                        ; ---- shift window ----
                                        ;   SLIDE THE WINDOW: (x0,x1,x2) := (x1,x2,x3), and likewise
                                        ;   the f values. Sixteen bytes each, two 8-byte moves at a
                                        ;   time -- there is no 16-byte move instruction for integers.
        mov rax,[mx1]
        mov [mx0],rax
        mov rax,[mx1+8]
        mov [mx0+8],rax
        mov rax,[mf1]
        mov [mf0],rax
        mov rax,[mf1+8]
        mov [mf0+8],rax
        mov rax,[mx2]
        mov [mx1],rax
        mov rax,[mx2+8]
        mov [mx1+8],rax
        mov rax,[mf2]
        mov [mf1],rax
        mov rax,[mf2+8]
        mov [mf1+8],rax
        mov rax,[mx3]
        mov [mx2],rax
        mov rax,[mx3+8]
        mov [mx2+8],rax
        mov rax,[mf3]
        mov [mf2],rax
        mov rax,[mf3+8]
        mov [mf2+8],rax

                                        ; ---- converged?  |delta|^2 < tol2 ----
                                        ;   the convergence test: is |delta|^2 still above tolerance?
        lea rsi,[mdel]
        call cmag2
                                        ;   |delta|^2, on the FPU stack
        fld qword [tol2]
                                        ;   push the tolerance
        fcomip st0, st1
                                        ;   compare and pop -- `fcomip` again, the modern one-
                                        ;   instruction form
        fstp st0
                                        ;   discard the survivor.  stack: EMPTY
        jb .cont                        ; tol2 < |delta|^2 -> keep going
                                        ;   tol2 < |delta|^2, so keep going
        jmp .done
                                        ;   otherwise we have converged
.cont:
                                        ;   the iteration cap
        dec r12d
                                        ;   one fewer allowed
        jnz .iter
                                        ;   ...and stop if exhausted
.done:
                                        ;   reached either by convergence or by the cap
        lea rdi,[fin]
                                        ;   the closing line
        movsd xmm0,[mx2]
                                        ;   the final answer, in xmm0
        mov al, 1
                                        ;   ONE vector register
        call printf

        xor eax, eax
                                        ;   main's return value: 0 = success
        lea rsp,[rbp-16]
                                        ;   land exactly on the last thing pushed -- TWO registers, so
                                        ;   16. `mov rsp, rbp` would skip past them and the pops would
                                        ;   get rubbish.
        pop r12
                                        ;   restore them IN REVERSE ORDER to the pushes
        pop rbx
        pop rbp
                                        ;   ...and finally the caller's frame pointer
        ret
                                        ;   pop the return address into rip

