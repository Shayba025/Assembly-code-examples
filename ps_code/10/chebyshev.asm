;;; ============================================================================
;;; chebyshev.asm -- build T_2N by recurrence, then find ALL its roots
;;; Practice session 10                      (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Three jobs, in order, and each is worth studying on its own:
;;;     1. BUILD the Chebyshev polynomial T_d (d = 2N) from the recurrence
;;;        T_{k+1} = 2x*T_k - T_{k-1}, as a vector of coefficients.
;;;     2. FIND every root with Muller's method, DEFLATING the polynomial after
;;;        each one so the next search cannot rediscover it.
;;;     3. PRINT each computed root beside the exact value cos((2k-1)pi/2d), so
;;;        you can see the error.
;;;   (Verified: runs and produces the table.)
;;;
;;;   *** IT IS THE LARGEST PROGRAM IN THE COURSE, AND IT IS BUILT ENTIRELY FROM
;;;   PIECES YOU HAVE ALREADY MET. *** Read it as an assembly of parts:
;;;     the complex helpers        -> muller_demo.asm in this folder, identical
;;;     Muller's method            -> muller_demo.asm, same algebra
;;;     Horner evaluation          -> fma_horner.asm, code-0016.asm
;;;     the hand-written atoi      -> cheb_root_round.asm, code-0016.asm
;;;     bubble sort                -> code-0021.asm in "lectures code "
;;;     array indexing base+8*i    -> code-0020.asm and everywhere else
;;;   Nothing here is new except the SCALE, and that is the point: a big program
;;;   is small programs stacked up.
;;;
;;;   THE THREE ALGORITHMS, briefly:
;;;
;;;   RECURRENCE. T0 = 1, T1 = x, T_{k+1} = 2x*T_k - T_{k-1}. On coefficient
;;;   vectors, multiplying by x is a SHIFT BY ONE POSITION, so the step is
;;;       next[0] = -prev[0]
;;;       next[i] = 2*cur[i-1] - prev[i]
;;;   and the three buffers are ROTATED rather than copied -- prev, cur and next
;;;   are pointers that get shuffled, which costs three `mov`s instead of
;;;   copying 65 doubles.
;;;
;;;   DEFLATION. Once you have a root r, dividing the polynomial by (x - r)
;;;   leaves a polynomial of degree one less with the same remaining roots. The
;;;   division is SYNTHETIC DIVISION and is astonishingly short:
;;;       carry = c[deg];  q[deg-1] = carry
;;;       for i = deg-1 down to 1:  carry = c[i] + r*carry;  q[i-1] = carry
;;;   Four lines, and it saves the root-finder from converging on the same root
;;;   over and over. The cost is error accumulation -- each deflation is done
;;;   with the PREVIOUS root's rounding baked in, so later roots are less
;;;   accurate. Look at the error column and see whether that shows.
;;;
;;;   MULLER. See muller_demo.asm's header for the full derivation. The one
;;;   difference here is the STARTING TRIPLE:
;;;       s0 = -0.10 + 0.00i,  s1 = 0.00 + 0.20i,  s2 = 0.10 + 0.00i
;;;   Note s1's imaginary part. The author's comment explains it: T_2N is an EVEN
;;;   polynomial, so a purely real symmetric triple can leave the iteration
;;;   stalled on the axis. A small imaginary nudge breaks the symmetry. That is
;;;   the kind of detail that separates a numerical routine that works from one
;;;   that mysteriously does not.
;;;
;;;   ONE INSTRUCTION HERE APPEARS NOWHERE ELSE IN THE COURSE:
;;;       rep stosq
;;;   STOre String Quadword, REPeated: write rax to [rdi], advance rdi by 8,
;;;   decrement rcx, repeat until rcx is zero. One instruction that zeroes an
;;;   arbitrary block of memory -- here all three recurrence buffers at once,
;;;   because they are contiguous. Its siblings are `rep movsq` (block copy) and
;;;   `repne scasb` (which is what strlen compiles to). NOTE it depends on the
;;;   DIRECTION FLAG: `cld` means ascending, `std` descending. The ABI requires
;;;   the flag to be clear on entry to any function, which is why this code does
;;;   not bother setting it -- but a function that sets it MUST clear it again,
;;;   exactly like a callee-saved register.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/10/chebyshev.asm"          # N = 2, so degree 4
;;;   ./asm "ps_code/10/chebyshev.asm" 4        # degree 8
;;;   ./asm "ps_code/10/chebyshev.asm" 8        # degree 16
;;;   ./asm "ps_code/10/chebyshev.asm" 16       # degree 32
;;;
;;;   WATCH THE ERROR COLUMN GROW WITH THE DEGREE. That is deflation error
;;;   accumulating, and it is a real phenomenon rather than a bug in this code.
;;;
;;;   Check the exact roots:
;;;   python3 -c "
;;;   import math
;;;   d = 4
;;;   for k in range(1, d+1): print('%+.16f' % math.cos((2*k-1)*math.pi/(2*d)))"
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/10/chebyshev.asm" 4
;;;
;;;   Watch the polynomial being built:
;;;     break chebyshev.asm:NN    NN on the `.bdone` label's first line
;;;     c
;;;     p (int)Dorig              the degree
;;;     x/9fg &coef               the coefficients of T_8, low order first.
;;;                               For T_4 you should see 1, 0, -8, 0, 8.
;;;
;;;   Watch a root being found and then deflated away:
;;;     break deflate
;;;     c
;;;     p (double)rootr           the root just found
;;;     p (long)deg               the degree before
;;;     x/9fg &coef               the coefficients before
;;;     finish
;;;     p (long)deg               one lower
;;;     x/8fg &coef               ...and a shorter polynomial
;;;
;;;   Watch Muller converge on one root:
;;;     break muller
;;;     c
;;;     break chebyshev.asm:NN    NN on the `test bl, bl` line near .conv_done
;;;     c
;;;     p *(double*)&mx3          the current approximation
;;;     p $bl                     the convergence flag
;;;     c                         and again
;;;
;;;   And see the buffers being rotated rather than copied:
;;;     break chebyshev.asm:NN    NN on the `.ikd` label
;;;     c
;;;     info registers r12 r13 r14
;;;     si si si si               the four movs
;;;     info registers r12 r13 r14    the same three addresses, rotated
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   *** LOOK AT MAIN'S PROLOGUE. IT IS THE BIGGEST IN THE COURSE. ***
;;;       push rbp / mov rbp, rsp
;;;       push rbx / push r12 / push r13 / push r14 / push r15
;;;       sub  rsp, 8
;;;   FIVE callee-saved registers, plus the frame pointer, plus an alignment pad.
;;;   And every one of them earns its place: rbx is the print index, r12/r13/r14
;;;   are the three rotating buffer pointers, r13 later becomes the root count,
;;;   r15 is N. All of them must survive the calls to `muller`, `deflate` and
;;;   `printf` -- and CALLEE-SAVED IS THE ONLY KIND OF REGISTER THAT DOES.
;;;
;;;   Count the arithmetic yourself: six pushes is 48 bytes, and main starts at
;;;   8 mod 16, so 8 - 48 = -40 = 8 mod 16 -- still wrong. Hence `sub rsp, 8`,
;;;   taking it to 0, which is what the ABI requires at a `call`. The author's
;;;   comment says "6 pushes -> realign to 16" and is correct. Verify:
;;;       break printf
;;;       c
;;;       p $rsp % 16             8, as promised at a callee's first instruction
;;;
;;;   AND THE EPILOGUE UNDOES IT ALL IN EXACTLY REVERSE ORDER -- pad, then r15,
;;;   r14, r13, r12, rbx, rbp. Get that sequence wrong and you hand the caller
;;;   two of its registers swapped, which is a spectacularly confusing bug.
;;;
;;;   NOW THE DEEPEST NESTING IN THE COURSE. Break on `cmul` and type `bt`:
;;;       #0  cmul
;;;       #1  ceval
;;;       #2  muller
;;;       #3  main
;;;   Four frames. That is as deep as this program ever goes -- there is no
;;;   recursion anywhere. Compare code-0017.asm (Hanoi), which reaches n frames,
;;;   and is_even.asm in ps_code/5, which can reach half a million and crash.
;;;   DEPTH MEASURES NESTING, NOT WORK: this program does far more computing than
;;;   Hanoi and uses a fraction of the stack.
;;;
;;;   THE COMMENT ON `deflate` IS THE SHARPEST ABI OBSERVATION IN THE FILE:
;;;       "(uses only caller-saved registers, so the find-loop's r13 is safe)"
;;;   The root count lives in r13 across the `call deflate`, and that is safe for
;;;   two independent reasons: r13 is callee-saved so `deflate` would have to
;;;   restore it, AND `deflate` never touches it in the first place. The author
;;;   checked, and wrote down why. That habit -- stating which registers a
;;;   function may destroy, and then keeping the promise -- is what makes a
;;;   program this size possible at all.
;;;
;;;   FINALLY, THE .bss BLOCK. Twenty-four complex temporaries for Muller, four
;;;   arrays of 65 doubles, and a dozen scalars. None on the stack, and none
;;;   could be: the FPU stack holds eight values and none survive a call, ALL
;;;   SIXTEEN xmm registers are caller-saved, and a complex number is 16 bytes
;;;   and must be passed by pointer. When you have more live values than
;;;   registers and every call destroys the registers you have, STATIC MEMORY IS
;;;   NOT A FALLBACK -- IT IS THE DESIGN. The price is that none of this is
;;;   reentrant, which is exactly the trade lagrange_final.asm and
;;;   gauss_chebyshev.asm make too.
;;; ============================================================================

; ============================================================================
;  chebyshev.asm -- Build the Chebyshev polynomial T_{2N} by its recurrence,
;                   then find ALL of its (real) roots with MULLER'S METHOD,
;                   deflating after each root.  Every floating-point operation
;                   is done on the x87 FPU.
;
;  Build (Linux, x86-64):
;       nasm -f elf64 chebyshev.asm -o chebyshev.o
;       gcc  -no-pie  chebyshev.o   -o chebyshev
;       ./chebyshev 4            <-- N (defaults to 2 if omitted); degree = 2N
;
;  Recurrence used to build the coefficient vector:
;       T0 = 1 ,  T1 = x ,  T_{k+1} = 2*x*T_k - T_{k-1}
;
;  Müller's method (quadratic interpolation through 3 points, complex-safe):
;       h0 = x1-x0 , h1 = x2-x1
;       d0 = (f1-f0)/h0 , d1 = (f2-f1)/h1
;       A  = (d1-d0)/(h1+h0) ,  B = A*h1 + d1 ,  C = f2
;       x3 = x2 - 2C / ( B +/- sqrt(B^2-4AC) )   [sign chosen for max |denom|]
;
;  All roots of T_m are known exactly:  cos((2k-1)*pi/(2m)), k=1..m.
;  The program prints that exact value next to each computed root so you can
;  see the error.
; ============================================================================

global  main
                                           ;   export `main` for the C library start-up
extern  printf
                                           ;   the only external function needed

%define MAXD 64                            ; maximum supported degree (N <= 32)
                                           ;   a preprocessor substitution: the largest degree the fixed
                                           ;   arrays can hold
%define MAXIT 400                          ; Müller iteration cap
                                           ;   the Muller iteration cap -- no root-finder is guaranteed
                                           ;   to converge

; ----------------------------------------------------------------------------
section .rodata
                                           ;   READ-ONLY data: strings that are never written
banner  db 10,"Chebyshev T_%d  (degree d = 2N = %d).  Leading coeff = 2^(d-1).",10
                                           ;   THREE ints, so 0 vector registers
        db    "Finding all %d real roots by recurrence + Muller + deflation.",10,10,0
col_hd  db    "  k        computed root        exact cos((2k-1)pi/2d)        error",10
        db    " ---  ----------------------  ----------------------  ------------",10,0
                                           ;   the column headings, no conversions
row_fmt db    " %3d   %+.16f   %+.16f   %+.2e",10,0
done_ln db 10,"All %d roots found.  (compare 'computed' vs 'exact').",10,0
                                           ;   an int and THREE doubles. Integer and float arguments are
                                           ;   counted in SEPARATE sequences, so esi holds k and
                                           ;   xmm0..xmm2 the three values.

                                           ;   the closing line: one int
section .data
align 8
                                           ;   initialised, writable data
; --- Müller starting triple (a small imaginary part breaks the symmetry of
                                           ;   pad to an 8-byte boundary
;     the even polynomial so the iteration never stalls on the real axis) ---
s0r dq -0.10
s0i dq  0.00
                                           ;   THE STARTING TRIPLE. Note s1's imaginary part of 0.2 --
                                           ;   T_2N is an EVEN polynomial, so a purely real symmetric
                                           ;   triple can leave the iteration stalled on the axis. The
                                           ;   nudge breaks the symmetry. See the header.
s1r dq  0.00
s1i dq  0.20
s2r dq  0.10
s2i dq  0.00

two   dq 2.0
four  dq 4.0
tol2  dq 1.0e-26                           ; convergence: |x3-x2|^2 below this
                                           ;   x87 cannot take an immediate, so the constants live here
ftol2 dq 1.0e-28                           ; or |f(x3)|^2 below this

                                           ;   convergence: |x3-x2|^2 below this. SQUARED, so the test
                                           ;   can skip a square root.
section .bss
                                           ;   ...or |f(x3)|^2 below this. Two independent criteria.
align 8
Dorig   resd 1                             ; original degree d = 2N
                                           ;   zero-filled at load time
deg     resq 1                             ; current (deflating) degree
                                           ;   pad to an 8-byte boundary
coef    resq MAXD+1                        ; working polynomial coefficients c[0..deg]
                                           ;   the ORIGINAL degree d = 2N, kept for printing
buf0    resq MAXD+1                        ; recurrence scratch (3 rotating buffers)
                                           ;   the CURRENT degree, which shrinks with every deflation
buf1    resq MAXD+1
                                           ;   the working polynomial, low order first. MAXD+1 slots.
buf2    resq MAXD+1
                                           ;   three rotating buffers for the recurrence. They are
                                           ;   CONTIGUOUS, which is what lets one `rep stosq` clear all
                                           ;   three.
qb      resq MAXD+1                        ; deflation quotient
roots   resq MAXD+1                        ; collected roots
rootr   resq 1                             ; current root (real)
                                           ;   the deflation quotient
carry   resq 1                             ; synthetic-division accumulator
                                           ;   the roots, collected as they are found
inum    resd 1                             ; integer scratch for exact-value formula
                                           ;   the root currently being deflated out
iden    resd 1
                                           ;   the synthetic-division accumulator
exactv  resq 1
                                           ;   integer scratch, because `fild` needs a MEMORY operand
errv    resq 1

                                           ;   the exact root, for comparison
; complex scratch cells (re at +0, im at +8) used by helper routines
                                           ;   computed minus exact
ev_acc  resq 2                             ; Horner accumulator for ceval
cdiv_den resq 1                            ; |denominator|^2 for cdiv
csqrt_m resq 1                             ; |.| for csqrt
                                           ;   *** EVERY `resq 2` BELOW IS ONE COMPLEX NUMBER: sixteen
                                           ;   bytes, real part at [z] and imaginary at [z+8]. ***
mret    resq 1                             ; muller result (real part of converged root)
                                           ;   `ceval`'s Horner accumulator

                                           ;   |denominator|^2 inside cdiv, reused as scratch elsewhere
; complex working set for Müller
                                           ;   |z| inside csqrt
mx0 resq 2
                                           ;   where `muller` leaves its answer
mx1 resq 2
mx2 resq 2
                                           ;   the twenty-four complex working cells. See the call-stack
                                           ;   notes for why none of these can be stack locals.
mx3 resq 2
mf0 resq 2
mf1 resq 2
mf2 resq 2
mf3 resq 2
mh0 resq 2
mh1 resq 2
md0 resq 2
md1 resq 2
mA  resq 2
mB  resq 2
mC  resq 2
mdsc resq 2
mden resq 2
mt1 resq 2
mt2 resq 2
mbp resq 2
mbm resq 2
mnum resq 2
mq  resq 2
mdel resq 2

; ============================================================================
;  COMPLEX HELPERS   (rdi = dst, rsi = a, rdx = b ; all 16-byte complex)
;  Inputs are fully loaded before any store, so dst may alias a or b.
; ============================================================================
section .text
                                           ;   the executable-code section

; dst = a + b
                                           ;   void cadd(complex *dst, const complex *a, const complex *b)
                                           ;   (a+bi)+(c+di) = (a+c)+(b+d)i. The result travels through a
                                           ;   POINTER -- 16 bytes will not fit in a register.
cadd:
        fld     qword [rsi]
                                           ;   push a.re
        fadd    qword [rdx]
                                           ;   st0 := a.re + b.re
        fld     qword [rsi+8]
                                           ;   push a.im.  FPU stack:  re-sum   a.im
        fadd    qword [rdx+8]
                                           ;   st0 := a.im + b.im
        fstp    qword [rdi+8]
                                           ;   store the IMAGINARY part first, because `fstp` always pops
                                           ;   the TOP of the FPU stack
        fstp    qword [rdi]
                                           ;   ...then the real part.  stack: EMPTY
        ret
                                           ;   pop the return address into rip. No frame at all.

; dst = a - b
csub:
                                           ;   void csub(...) -- identical, with subtraction
        fld     qword [rsi]
        fsub    qword [rdx]
        fld     qword [rsi+8]
        fsub    qword [rdx+8]
        fstp    qword [rdi+8]
        fstp    qword [rdi]
        ret

; dst = a * b
cmul:
                                           ;   void cmul(...) -- four multiplications, one subtraction,
                                           ;   one addition. Check it against the algebra by hand once.
        fld     qword [rsi]                ; ar
        fmul    qword [rdx]                ; ar*br
        fld     qword [rsi+8]              ; ai
        fmul    qword [rdx+8]              ; ai*bi
        fsubp   st1, st0                   ; re = ar*br - ai*bi
                                           ;   st1 := st1 - st0, then POP -- two slots become one
        fld     qword [rsi]                ; ar
        fmul    qword [rdx+8]              ; ar*bi
        fld     qword [rsi+8]              ; ai
        fmul    qword [rdx]                ; ai*br
        faddp   st1, st0                   ; im = ar*bi + ai*br   (st0=im, st1=re)
                                           ;   st1 := st1 + st0, then pop
        fstp    qword [rdi+8]
                                           ;   the imaginary part is on top, so it stores first
        fstp    qword [rdi]
        ret

; dst = a / b
cdiv:
                                           ;   void cdiv(...) -- multiply top and bottom by the CONJUGATE
                                           ;   of b, which makes the denominator the REAL number
                                           ;   |b|^2 = br^2 + bi^2
                                           ; denom = br^2 + bi^2  -> [cdiv_den]
        fld     qword [rdx]
        fmul    st0, st0
        fld     qword [rdx+8]
        fmul    st0, st0
        faddp   st1, st0
        fstp    qword [cdiv_den]
                                           ;   park the (real) denominator in memory -- it is needed
                                           ;   twice below
                                           ; re = (ar*br + ai*bi)/denom
        fld     qword [rsi]
        fmul    qword [rdx]
        fld     qword [rsi+8]
        fmul    qword [rdx+8]
        faddp   st1, st0
        fdiv    qword [cdiv_den]
                                           ; im = (ai*br - ar*bi)/denom
        fld     qword [rsi+8]
        fmul    qword [rdx]
        fld     qword [rsi]
        fmul    qword [rdx+8]
        fsubp   st1, st0
        fdiv    qword [cdiv_den]           ; st0=im, st1=re
        fstp    qword [rdi+8]
        fstp    qword [rdi]
        ret

; dst = sqrt(a)     principal branch
csqrt:
                                           ;   void csqrt(complex *dst, const complex *a) -- the PRINCIPAL
                                           ;   square root, by the half-angle formulae
                                           ; m = |a| = sqrt(u^2+v^2)
        fld     qword [rsi]
        fmul    st0, st0
        fld     qword [rsi+8]
        fmul    st0, st0
        faddp   st1, st0
        fsqrt
        fst     qword [csqrt_m]            ; keep m
                                           ;   `fst`, NOT `fstp`: store to memory and KEEP the value, so
                                           ;   the imaginary half can reuse it
                                           ; re = sqrt((m+u)/2)
        fadd    qword [rsi]                ; m+u
        fld1
                                           ;   push 1.0...
        fld1
                                           ;   ...and another...
        faddp   st1, st0                   ; 2.0
                                           ;   ...and add: st0 = 2.0. x87 cannot take an immediate, so
                                           ;   this is how you get the constant 2 without a memory slot.
        fdivp   st1, st0                   ; (m+u)/2
                                           ;   st1 /= st0, pop
        fsqrt
        fstp    qword [rdi]                ; store re
                                           ; |im| = sqrt((m-u)/2)
        fld     qword [csqrt_m]
        fsub    qword [rsi]                ; m-u
        fld1
        fld1
        faddp   st1, st0
        fdivp   st1, st0
        fsqrt                              ; |im|
                                           ; apply sign of v
        fld     qword [rsi+8]              ; v   (st0=v, st1=|im|)
        ftst
                                           ;   THE OLD WAY OF BRANCHING ON A FLOAT. `ftst` compares st0
                                           ;   with zero and sets the FPU's OWN status word.
        fnstsw  ax
                                           ;   copy that status word into ax -- the ordinary FLAGS
                                           ;   register cannot see it directly
        fstp    st0                        ; drop v -> st0=|im|
        sahf
                                           ;   Store AH into Flags. NOW `jnc` can read the comparison.
                                           ;   FOUR instructions to do what `fcomip` (used twice below)
                                           ;   does in ONE. Worth comparing them directly.
        jnc     .pos                       ; CF=0 -> v>=0
        fchs
                                           ;   v < 0, so negate: the principal root's imaginary part
                                           ;   takes the sign of the input's
.pos:
        fstp    qword [rdi+8]
                                           ;   store the imaginary part.  stack: EMPTY
        ret

; |a|^2 in st0   (rsi = a)
cmag2:
                                           ;   double cmag2(const complex *a) -- |a|^2, LEFT ON THE FPU
                                           ;   STACK rather than stored. The one helper with a different
                                           ;   convention, because callers always compare it immediately.
        fld     qword [rsi]
        fmul    st0, st0
        fld     qword [rsi+8]
        fmul    st0, st0
        faddp   st1, st0
                                           ;   st1 += st0, pop.  stack:  |a|^2, for the caller
        ret

; ----------------------------------------------------------------------------
; ceval: dst(rdi) = P(z),  z = (rsi).  Horner over global coef[0..deg].
;        preserves rbx,r14,r15 (callee-saved) which it uses.
; ----------------------------------------------------------------------------
ceval:
                                           ;   void ceval(complex *dst, const complex *z) -- HORNER'S RULE
                                           ;   over the CURRENT coef[0..deg], with complex arithmetic
        push    rbx
                                           ;   three CALLEE-SAVED registers, because this function calls
                                           ;   cmul in its loop and needs three values to survive
        push    r14
        push    r15
        mov     rbx, rdi                   ; dst
                                           ;   park the destination...
        mov     r14, rsi                   ; z
                                           ;   ...and the point
        mov     rax, [deg]
                                           ;   start Horner at the TOP coefficient
        fld     qword [coef + rax*8]
        fstp    qword [ev_acc]             ; acc.re = coef[deg]
                                           ;   acc.re = coef[deg]
        fldz
        fstp    qword [ev_acc+8]           ; acc.im = 0
                                           ;   acc.im = 0 -- the coefficients are all real
        mov     r15, rax
        dec     r15                        ; i = deg-1
                                           ;   i = deg-1, walking downwards
.loop:
                                           ;   `.loop` is LOCAL to ceval
        test    r15, r15
        js      .done                      ; i < 0
                                           ;   `js` = jump if SIGN, i.e. i went negative: done
        lea     rdi, [ev_acc]              ; acc = acc * z
                                           ;   acc := acc * z. dst and src1 are THE SAME cell -- safe
                                           ;   because cmul loads both operands fully before storing, as
                                           ;   the header at the top of the helpers promises.
        lea     rsi, [ev_acc]
        mov     rdx, r14
        call    cmul
        fld     qword [ev_acc]             ; acc.re += coef[i]
                                           ;   ...then add the next coefficient to the REAL part only
        fadd    qword [coef + r15*8]
        fstp    qword [ev_acc]
        dec     r15
        jmp     .loop
                                           ;   next coefficient down
.done:
        mov     rax, [ev_acc]              ; *dst = acc
                                           ;   copy the accumulator out, sixteen bytes in two moves
        mov     [rbx], rax
        mov     rax, [ev_acc+8]
        mov     [rbx+8], rax
        pop     r15
                                           ;   restore the callee-saved registers IN REVERSE ORDER
        pop     r14
        pop     rbx
        ret
                                           ;   pop the return address into rip

; ============================================================================
;  muller: find one root of the current coef[0..deg]; real part -> [mret]
; ============================================================================
muller:
                                           ;   void muller(void) -- find ONE root of the current
                                           ;   coef[0..deg]; the real part lands in [mret]
        push    rbx
                                           ;   two CALLEE-SAVED registers: rbx is the convergence flag,
                                           ;   r12 the iteration counter, and both must survive the
                                           ;   helper calls
        push    r12
                                           ; load starting triple
        mov     rax,[s0r]
                                           ;   load the starting triple, sixteen bytes at a time
        mov     [mx0],rax
        mov     rax,[s0i]
        mov     [mx0+8],rax
        mov     rax,[s1r]
        mov     [mx1],rax
        mov     rax,[s1i]
        mov     [mx1+8],rax
        mov     rax,[s2r]
        mov     [mx2],rax
        mov     rax,[s2i]
        mov     [mx2+8],rax
        lea     rdi,[mf0]
                                           ;   f0 = P(x0)
        lea     rsi,[mx0]
        call    ceval
        lea     rdi,[mf1]
                                           ;   f1 = P(x1)
        lea     rsi,[mx1]
        call    ceval
        lea     rdi,[mf2]
                                           ;   f2 = P(x2)
        lea     rsi,[mx2]
        call    ceval
        mov     r12d, MAXIT
                                           ;   the iteration cap
.iter:
                                           ;   one pass = one Muller step. `.iter` is LOCAL to muller.
                                           ; h0 = x1-x0 ; h1 = x2-x1
        lea     rdi,[mh0]
        lea     rsi,[mx1]
        lea     rdx,[mx0]
        call    csub
                                           ;   h0 = x1 - x0
        lea     rdi,[mh1]
        lea     rsi,[mx2]
        lea     rdx,[mx1]
        call    csub
                                           ;   h1 = x2 - x1
                                           ; d0 = (f1-f0)/h0
        lea     rdi,[mt1]
        lea     rsi,[mf1]
        lea     rdx,[mf0]
        call    csub
                                           ;   t1 = f1 - f0
        lea     rdi,[md0]
        lea     rsi,[mt1]
        lea     rdx,[mh0]
        call    cdiv
                                           ;   d0 = (f1-f0)/h0 -- the first divided difference
                                           ; d1 = (f2-f1)/h1
        lea     rdi,[mt1]
        lea     rsi,[mf2]
        lea     rdx,[mf1]
        call    csub
                                           ;   t1 = f2 - f1
        lea     rdi,[md1]
        lea     rsi,[mt1]
        lea     rdx,[mh1]
        call    cdiv
                                           ;   d1 = (f2-f1)/h1
                                           ; A = (d1-d0)/(h1+h0)
        lea     rdi,[mt1]
        lea     rsi,[md1]
        lea     rdx,[md0]
        call    csub
                                           ;   t1 = d1 - d0
        lea     rdi,[mt2]
        lea     rsi,[mh1]
        lea     rdx,[mh0]
        call    cadd
                                           ;   t2 = h1 + h0
        lea     rdi,[mA]
        lea     rsi,[mt1]
        lea     rdx,[mt2]
        call    cdiv
                                           ;   A = (d1-d0)/(h1+h0), the parabola's leading coefficient
                                           ; B = A*h1 + d1
        lea     rdi,[mt1]
        lea     rsi,[mA]
        lea     rdx,[mh1]
        call    cmul
                                           ;   t1 = A*h1
        lea     rdi,[mB]
        lea     rsi,[mt1]
        lea     rdx,[md1]
        call    cadd
                                           ;   B = A*h1 + d1
                                           ; C = f2
        mov     rax,[mf2]
                                           ;   C = f2, copied sixteen bytes at a time
        mov     [mC],rax
        mov     rax,[mf2+8]
        mov     [mC+8],rax
                                           ; disc = sqrt(B*B - 4*A*C)
        lea     rdi,[mt1]
        lea     rsi,[mB]
        lea     rdx,[mB]
        call    cmul                       ; B^2
        lea     rdi,[mt2]
        lea     rsi,[mA]
        lea     rdx,[mC]
        call    cmul                       ; A*C
        fld     qword [mt2]                ; *4
                                           ;   multiply A*C by 4, one component at a time -- there is no
                                           ;   complex scalar-multiply helper
        fmul    qword [four]
        fstp    qword [mt2]
        fld     qword [mt2+8]
        fmul    qword [four]
        fstp    qword [mt2+8]
        lea     rdi,[mt1]
        lea     rsi,[mt1]
        lea     rdx,[mt2]
        call    csub                       ; B^2 - 4AC
                                           ;   t1 = B^2 - 4AC, the discriminant
        lea     rdi,[mdsc]
        lea     rsi,[mt1]
        call    csqrt
                                           ;   disc = sqrt(B^2-4AC). MAY BE COMPLEX, and that is exactly
                                           ;   how Muller reaches complex roots from real seeds.
                                           ; bp = B+disc ; bm = B-disc
        lea     rdi,[mbp]
        lea     rsi,[mB]
        lea     rdx,[mdsc]
        call    cadd
                                           ;   bp = B + disc
        lea     rdi,[mbm]
        lea     rsi,[mB]
        lea     rdx,[mdsc]
        call    csub
                                           ;   bm = B - disc
                                           ; choose den = whichever of bp,bm has larger magnitude
        lea     rsi,[mbp]
        call    cmag2                      ; st0=|bp|^2
                                           ;   |bp|^2, on the FPU stack
        fstp    qword [cdiv_den]           ; (reuse scratch) save |bp|^2
                                           ;   park it (reusing cdiv's scratch, which is free right now)
        lea     rsi,[mbm]
        call    cmag2                      ; st0=|bm|^2
                                           ;   |bm|^2, on the FPU stack
        fld     qword [cdiv_den]           ; st0=|bp|^2, st1=|bm|^2
                                           ;   reload the other.  stack:  |bm|^2   |bp|^2
        fcomip  st0, st1                   ; CF=1 if |bp|^2 < |bm|^2 ; pops |bp|^2
                                           ;   compare st0 with st1, set the ORDINARY flags, and POP.
                                           ;   ONE instruction -- contrast the four-instruction
                                           ;   ftst/fnstsw/sahf sequence in csqrt above.
        fstp    st0                        ; drop |bm|^2
                                           ;   discard the survivor.  stack: EMPTY
        jb      .use_bm
                                           ;   *** THE NUMERICALLY IMPORTANT CHOICE: take whichever
                                           ;   denominator is LARGER in magnitude. The form 2C/(B+/-disc)
                                           ;   avoids the catastrophic cancellation that the usual
                                           ;   (-b+/-sqrt)/2a suffers when b and sqrt(disc) are close. ***
        mov     rax,[mbp]
        mov     [mden],rax
        mov     rax,[mbp+8]
        mov     [mden+8],rax
        jmp     .den_done
.use_bm:
        mov     rax,[mbm]
        mov     [mden],rax
        mov     rax,[mbm+8]
        mov     [mden+8],rax
.den_done:
                                           ; num = 2*C
                                           ;   num = 2C. `fadd st0, st0` doubles by adding a value to
                                           ;   itself -- exact, and cheaper than a multiply.
        fld     qword [mC]
        fadd    st0, st0
        fstp    qword [mnum]
        fld     qword [mC+8]
        fadd    st0, st0
        fstp    qword [mnum+8]
                                           ; q = num/den
        lea     rdi,[mq]
        lea     rsi,[mnum]
        lea     rdx,[mden]
        call    cdiv
                                           ;   q = 2C/den, the correction
                                           ; x3 = x2 - q
        lea     rdi,[mx3]
        lea     rsi,[mx2]
        lea     rdx,[mq]
        call    csub
                                           ;   x3 = x2 - q, the new approximation
                                           ; f3 = f(x3)
        lea     rdi,[mf3]
        lea     rsi,[mx3]
        call    ceval
                                           ;   f3 = P(x3)
                                           ; delta = x3 - x2
        lea     rdi,[mdel]
        lea     rsi,[mx3]
        lea     rdx,[mx2]
        call    csub
                                           ;   delta = x3 - x2, the step size

                                           ; ---- convergence test ----
        xor     ebx, ebx                   ; conv flag = 0
                                           ;   the convergence flag starts at 0 -- and rbx is
                                           ;   callee-saved, so it survives the cmag2 calls below
                                           ; |f3|^2 < ftol2 ?
        lea     rsi,[mf3]
                                           ;   |f3|^2, on the FPU stack
        call    cmag2
        fld     qword [ftol2]
                                           ;   push the residual tolerance
        fcomip  st0, st1                   ; CF=1 if ftol2 < |f3|^2
                                           ;   compare and pop
        fstp    st0
                                           ;   discard the survivor
        jb      .chk_delta
                                           ;   ftol2 < |f3|^2, so the residual is still too big
        mov     bl, 1
                                           ;   ...otherwise converged
        jmp     .conv_done
.chk_delta:
                                           ;   the second criterion: has the STEP become small?
        lea     rsi,[mdel]
        call    cmag2
        fld     qword [tol2]
                                           ;   push the step tolerance
        fcomip  st0, st1                   ; CF=1 if tol2 < |delta|^2  (not converged)
                                           ;   compare and pop
        fstp    st0
        jb      .conv_done                 ; not converged -> bl stays 0
                                           ;   still moving, so not converged -- bl stays 0
        mov     bl, 1
                                           ;   converged
.conv_done:
                                           ; ---- shift x0<-x1<-x2<-x3 and f's ----
                                           ;   SLIDE THE WINDOW: (x0,x1,x2) := (x1,x2,x3), and the f
                                           ;   values with them. Sixteen bytes each, two 8-byte moves at
                                           ;   a time -- there is no 16-byte integer move.
        mov     rax,[mx1]
        mov     [mx0],rax
        mov     rax,[mx1+8]
        mov     [mx0+8],rax
        mov     rax,[mf1]
        mov     [mf0],rax
        mov     rax,[mf1+8]
        mov     [mf0+8],rax
        mov     rax,[mx2]
        mov     [mx1],rax
        mov     rax,[mx2+8]
        mov     [mx1+8],rax
        mov     rax,[mf2]
        mov     [mf1],rax
        mov     rax,[mf2+8]
        mov     [mf1+8],rax
        mov     rax,[mx3]
        mov     [mx2],rax
        mov     rax,[mx3+8]
        mov     [mx2+8],rax
        mov     rax,[mf3]
        mov     [mf2],rax
        mov     rax,[mf3+8]
        mov     [mf2+8],rax

        test    bl, bl
                                           ;   converged?
        jnz     .done
        dec     r12d
                                           ;   one fewer iteration allowed
        jnz     .iter
                                           ;   ...and stop if exhausted
.done:
                                           ;   reached either by convergence or by the cap
        mov     rax,[mx2]                  ; real part of converged root
                                           ;   the real part of the converged root is the answer
        mov     [mret],rax
        pop     r12
                                           ;   restore the callee-saved registers IN REVERSE ORDER
        pop     rbx
        ret
                                           ;   pop the return address into rip

; ============================================================================
;  deflate: divide coef[0..deg] by (x - rootr); quotient -> coef; deg--
;  (uses only caller-saved registers, so the find-loop's r13 is safe)
; ============================================================================
deflate:
                                           ;   void deflate(void) -- SYNTHETIC DIVISION by (x - rootr).
                                           ;   Four lines of arithmetic that shorten the polynomial by
                                           ;   one degree and remove the root just found, so the next
                                           ;   search cannot rediscover it.
        mov     r8, [deg]
                                           ;   the current degree
        fld     qword [coef + r8*8]
                                           ;   carry = coef[deg]...
        fstp    qword [carry]              ; carry = coef[deg] = q[deg-1]
                                           ;   ...which is also the quotient's leading coefficient
        mov     rax, r8
        dec     rax                        ; deg-1
        mov     rdx, [carry]
                                           ;   q[deg-1] = carry
        mov     [qb + rax*8], rdx
        mov     rcx, rax                   ; i = deg-1
                                           ;   i = deg-1
.dl:
                                           ;   `.dl` is LOCAL to deflate
        test    rcx, rcx
                                           ;   reached the constant term?
        jz      .dd
        fld     qword [carry]
                                           ;   push the carry
        fmul    qword [rootr]
                                           ;   st0 := carry * r
        fadd    qword [coef + rcx*8]
                                           ;   st0 := coef[i] + r*carry -- the synthetic-division step
        fstp    qword [carry]              ; carry = coef[i] + r*carry
                                           ;   store the new carry
        mov     rax, rcx
        dec     rax
        mov     rdx, [carry]
        mov     [qb + rax*8], rdx          ; q[i-1] = carry
                                           ;   q[i-1] = carry
        dec     rcx
                                           ;   next coefficient down
        jmp     .dl
.dd:
                                           ;   the polynomial is now one degree shorter
        dec     qword [deg]                ; degree drops by one
        mov     rcx, [deg]                 ; new degree
                                           ;   copy the quotient back over coef[0..new_deg]
.cp:
        mov     rdx, [qb + rcx*8]
        mov     [coef + rcx*8], rdx
        dec     rcx
        jns     .cp                        ; copy indices new_deg..0
                                           ;   `jns` = jump if NOT sign: keep going while rcx >= 0
        ret
                                           ;   pop the return address into rip. NO callee-saved register
                                           ;   is touched -- which is exactly what the header comment
                                           ;   promises, and why main's r13 is safe across this call.

; ============================================================================
;  main(argc=edi, argv=rsi)
; ============================================================================
main:
                                           ;   int main(int argc, char *argv[])
        push    rbp
                                           ;   prologue: save the caller's frame pointer
        mov     rbp, rsp
        push    rbx
                                           ;   FIVE CALLEE-SAVED REGISTERS -- the biggest prologue in the
                                           ;   course, and every one of them is needed across a call.
                                           ;   See the call-stack notes.
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 8                     ; 6 pushes -> realign to 16
                                           ;   six pushes is 48 bytes; main started at 8 mod 16, so
                                           ;   8-48 is still 8 mod 16. This pad takes it to 0, which is
                                           ;   what the ABI requires at a `call`.

                                           ; ---- parse N from argv[1] (default 2) ----
        mov     r14, rsi                   ; argv
                                           ;   park argv, out of the volatile rsi
        mov     r15d, 2                    ; default N
                                           ;   the default N
        cmp     edi, 2
                                           ;   argc < 2? then there is no argv[1]
        jl      .haveN
        mov     rdi, [r14 + 8]             ; argv[1]
                                           ;   argv[1] -- element 1 of the array
        xor     eax, eax
        xor     ecx, ecx                   ; accumulator
                                           ;   the accumulator for the hand-written atoi
.atoi:
                                           ;   A HAND-WRITTEN atoi, using Horner in base 10 -- the same
                                           ;   recurrence as code-0016.asm
        movzx   edx, byte [rdi]
                                           ;   load one character, zero-extended
        test    dl, dl
                                           ;   the NUL terminator?
        jz      .atoi_done
        sub     dl, '0'
                                           ;   convert ASCII to a digit value by subtracting 48
        cmp     dl, 9
                                           ;   THE NEAT TEST: `ja` is UNSIGNED, so a character BELOW '0'
                                           ;   has wrapped to a huge value and fails too. One comparison
                                           ;   catches both ends.
        ja      .atoi_done
        imul    ecx, ecx, 10
                                           ;   acc *= 10 -- the three-operand `imul`, no hidden registers
        movzx   edx, dl
        add     ecx, edx
                                           ;   ...plus the new digit
        inc     rdi
                                           ;   advance one BYTE
        jmp     .atoi
.atoi_done:
                                           ;   end of the number
        test    ecx, ecx
        jz      .haveN                     ; ignore garbage / zero -> default
                                           ;   a leading non-digit gives 0, so fall back to the default
        mov     r15d, ecx
.haveN:
                                           ;   the shared continuation
                                           ; clamp 2N <= MAXD
        mov     eax, r15d
                                           ;   d = 2N
        add     eax, eax                   ; d = 2N
        cmp     eax, MAXD
                                           ;   would it overflow the fixed arrays?
        jle     .dok
        mov     eax, MAXD
                                           ;   clamp to MAXD...
        shr     eax, 1
                                           ;   ...and recompute N from it
        mov     r15d, eax                  ; N = MAXD/2
        add     eax, eax
.dok:
                                           ;   the shared continuation
        mov     [Dorig], eax               ; d
                                           ;   publish the original degree, for printing
        movsxd  rax, eax
                                           ;   `movsxd` sign-extends a 32-bit value into 64 bits -- the
                                           ;   signed counterpart of the automatic zero-extension you
                                           ;   get from writing a 32-bit register
        mov     [deg], rax

                                           ; ---- zero the three recurrence buffers ----
                                           ;   zero all three recurrence buffers
        lea     rdi, [buf0]
                                           ;   the destination -- `stos` insists on rdi
        mov     ecx, (MAXD+1)*3            ; buf0,buf1,buf2 are contiguous
                                           ;   the count, in QUADWORDS. The three buffers are contiguous,
                                           ;   so one instruction clears all of them.
        xor     eax, eax
                                           ;   the value to store -- `stos` insists on rax
        rep     stosq
                                           ;   STOre String Quadword, REPeated: write rax to [rdi],
                                           ;   advance rdi by 8, decrement rcx, repeat until rcx is 0.
                                           ;   ONE INSTRUCTION that zeroes a whole block. Its siblings
                                           ;   are `rep movsq` (block copy) and `repne scasb` (strlen).
                                           ;   It depends on the DIRECTION FLAG, which the ABI requires
                                           ;   to be clear on entry -- so this code need not set it.

                                           ; ---- seed T0 (buf0) and T1 (buf1) ----
        fld1
                                           ;   T0 = 1: the constant polynomial
        fstp    qword [buf0]               ; T0 = 1
        fld1
                                           ;   T1 = x: coefficient 1 at index 1, and index 0 already zero
        fstp    qword [buf1 + 8]           ; T1 = x

                                           ; pointers: r12=prev(T_{k-2}), r13=cur(T_{k-1}), r14=next
                                           ;   three POINTERS, rotated each iteration instead of copying
                                           ;   65 doubles
        lea     r12, [buf0]
        lea     r13, [buf1]
        lea     r14, [buf2]

        movsxd  r15, dword [Dorig]         ; d  (loop target)
                                           ;   the loop target
        mov     ebx, 2                     ; k = 2
                                           ;   k = 2, since T0 and T1 are already seeded
.bk:
                                           ;   `.bk` is LOCAL to main
        cmp     ebx, r15d
        jg      .bdone
                                           ; next[0] = -prev[0]
                                           ;   next[0] = -prev[0]
        fld     qword [r12]
        fchs
        fstp    qword [r14]
                                           ; next[i] = 2*cur[i-1] - prev[i] ,  i = 1..k
                                           ;   next[i] = 2*cur[i-1] - prev[i], for i = 1..k.
                                           ;   Multiplying a polynomial by x is a SHIFT of the
                                           ;   coefficient vector -- which is why `cur[i-1]` appears
                                           ;   where you might have expected `cur[i]`.
        mov     eax, 1
.ik:
                                           ;   `.ik` is the inner loop
        cmp     eax, ebx
        jg      .ikd
        fld     qword [r13 + rax*8 - 8]    ; cur[i-1]
                                           ;   cur[i-1] -- base + 8*index, minus one element
        fadd    st0, st0                   ; 2*cur[i-1]
                                           ;   2*cur[i-1], by adding the value to itself
        fsub    qword [r12 + rax*8]        ; - prev[i]
                                           ;   ...minus prev[i]
        fstp    qword [r14 + rax*8]
        inc     eax
        jmp     .ik
.ikd:
                                           ;   ROTATE THE THREE POINTERS: prev<-cur, cur<-next,
                                           ;   next<-old prev. Three moves and a temporary, instead of
                                           ;   copying hundreds of bytes.
                                           ; rotate prev<-cur, cur<-next, next<-old prev
        mov     rax, r12
        mov     r12, r13
        mov     r13, r14
        mov     r14, rax
                                           ;   next k
        inc     ebx
        jmp     .bk
                                           ;   the final T_d is in `cur`; copy it to coef[0..d]
.bdone:
                                           ; final T_d is in cur (r13); copy to coef[0..d]
        movsxd  rcx, dword [Dorig]
.cpc:
        mov     rax, [r13 + rcx*8]
        mov     [coef + rcx*8], rax
                                           ;   the banner: three ints, so 0 vector registers
        dec     rcx
        jns     .cpc

                                           ; ---- banner ----
        lea     rdi, [banner]
        mov     esi, [Dorig]
        mov     edx, [Dorig]
                                           ;   the root count -- in r13, which is CALLEE-SAVED and
                                           ;   therefore survives `call muller` and `call deflate`
        mov     ecx, [Dorig]
                                           ;   one pass per root
        xor     eax, eax
        call    printf
                                           ;   degree 1 left? then the root is trivial

                                           ; ---- find all d roots ----
                                           ;   root = -coef[0]/coef[1], done directly
        xor     r13d, r13d                 ; root count
.findloop:
        mov     eax, [deg]
        cmp     eax, 1
        jg      .use_muller
                                           ; deg == 1: root = -coef[0]/coef[1]
                                           ;   otherwise use the full Muller machinery
        fld     qword [coef]
        fchs
        fdiv    qword [coef + 8]
        fstp    qword [rootr]
                                           ;   record the root
        jmp     .store
.use_muller:
        call    muller
                                           ;   was that the last one?
        mov     rax, [mret]
        mov     [rootr], rax
.store:
                                           ;   divide it out, so the next search cannot find it again
        mov     rax, [rootr]
        mov     [roots + r13*8], rax
        inc     r13d
                                           ;   all roots collected
        mov     eax, [deg]
        cmp     eax, 1
                                           ;   BUBBLE SORT, descending, so root k lines up with the k-th
                                           ;   exact value. The same algorithm as code-0021.asm in
                                           ;   "lectures code " -- read that file's notes for it.
        jle     .findone
        call    deflate
                                           ;   the outer pass
        jmp     .findloop
.findone:

                                           ;   the inner index
                                           ; ---- sort roots descending (bubble) so k=1 matches largest cos ----
                                           ;   `.sort_i` is the inner loop
        movsxd  r12, dword [Dorig]         ; n
.sort_o:
        dec     r12
                                           ;   b = roots[i+1]
        jle     .sorted
                                           ;   a = roots[i].  stack:  b   a
        xor     esi, esi                   ; i
                                           ;   compare and POP: CF is set if a < b
.sort_i:
                                           ;   discard b.  stack: EMPTY
        cmp     rsi, r12
                                           ;   a >= b, so they are already in order
        jge     .sort_o
                                           ;   otherwise swap the two eight-byte values
        fld     qword [roots + rsi*8 + 8]  ; b = roots[i+1]
        fld     qword [roots + rsi*8]      ; a = roots[i]  (st0=a, st1=b)
        fcomip  st0, st1                   ; CF=1 if a<b ; pops a
        fstp    st0                        ; drop b
        jnc     .nosw                      ; a>=b: ok
                                           ;   where the no-swap case lands
        mov     rax, [roots + rsi*8]       ; swap
        mov     rdx, [roots + rsi*8 + 8]
        mov     [roots + rsi*8], rdx
        mov     [roots + rsi*8 + 8], rax
                                           ;   sorted
.nosw:
        inc     esi
        jmp     .sort_i
                                           ;   the column headings
.sorted:

                                           ; ---- print table ----
        lea     rdi, [col_hd]
                                           ;   k = 1..d -- rbx is callee-saved, so it survives the printf
        xor     eax, eax
                                           ;   `.ploop` is LOCAL to main
        call    printf

        mov     ebx, 1                     ; k = 1..d
                                           ;   exact = cos((2k-1)*pi/(2d))
.ploop:
                                           ;   push pi
        cmp     ebx, [Dorig]
        jg      .pdone
                                           ;   2k...
                                           ; exact = cos((2k-1)*pi/(2d))
                                           ;   ...minus one
        fldpi
                                           ;   parked in memory, because `fild` needs a MEMORY operand
        mov     eax, ebx
                                           ;   push it, CONVERTED from integer to float
        add     eax, eax
                                           ;   st1 *= st0, pop: pi*(2k-1)
        dec     eax                        ; 2k-1
        mov     [inum], eax
                                           ;   2d...
        fild    dword [inum]
        fmulp   st1, st0                   ; pi*(2k-1)
                                           ;   ...likewise parked and loaded
        mov     eax, [Dorig]
        add     eax, eax                   ; 2d
                                           ;   st1 /= st0, pop: the angle
        mov     [iden], eax
                                           ;   cosine, in place, argument in RADIANS
        fild    dword [iden]
                                           ;   store and pop.  stack: EMPTY
        fdivp   st1, st0                   ; angle
        fcos                               ; cos(angle)
                                           ;   err = computed - exact
        fstp    qword [exactv]
                                           ; err = computed - exact
        mov     eax, ebx
        dec     eax                        ; index k-1
        fld     qword [roots + rax*8]
        fsub    qword [exactv]
        fstp    qword [errv]
                                           ;   the computed root, in xmm0...
                                           ; printf(row_fmt, k, computed, exact, err)
                                           ;   ...the exact value, in xmm1...
        mov     eax, ebx
                                           ;   ...and the error, in xmm2
        dec     eax
                                           ;   k, an INT, in esi -- counted in a SEPARATE sequence from
                                           ;   the floats
        movsd   xmm0, [roots + rax*8]
        movsd   xmm1, [exactv]
                                           ;   THREE vector registers carry arguments
        movsd   xmm2, [errv]
        mov     esi, ebx
                                           ;   next k
        lea     rdi, [row_fmt]
        mov     al, 3
                                           ;   all printed
        call    printf
        inc     ebx
        jmp     .ploop
                                           ;   the closing line: one int
.pdone:
        lea     rdi, [done_ln]
        mov     esi, [Dorig]
                                           ;   main's return value: 0 = success
        xor     eax, eax
                                           ;   undo the alignment pad, then restore the five
                                           ;   callee-saved registers IN EXACTLY REVERSE ORDER to the
                                           ;   pushes. Get this sequence wrong and the caller gets two
                                           ;   of its registers swapped.
        call    printf

        xor     eax, eax
        add     rsp, 8
        pop     r15
        pop     r14
                                           ;   pop the return address into rip
        pop     r13
        pop     r12
        pop     rbx
        pop     rbp
        ret

