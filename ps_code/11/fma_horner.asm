;;; ============================================================================
;;; fma_horner.asm -- Horner's rule, one FMA per term, checked against libm
;;; Practice session 11                      (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Approximates e^x with an eleventh-degree Taylor polynomial at five points,
;;;   and prints its answer beside libm's `expf` so you can see how close it is.
;;;   (Verified: agrees to six decimals except at x = -2, where the truncated
;;;   series is off in the fifth: 0.135328 against 0.135335.)
;;;
;;;   HORNER'S RULE turns a polynomial into nothing but multiply-adds:
;;;       a0 + a1*x + a2*x^2 + ... + an*x^n
;;;     = a0 + x*(a1 + x*(a2 + x*(... )))
;;;   Start the accumulator at the TOP coefficient and walk downwards, repeating
;;;       acc := x*acc + coef[i]
;;;   n multiplications and n additions, with no powers computed at all. The
;;;   naive form needs about n^2/2 multiplications and loses far more precision.
;;;   You have met Horner before, in base 16: code-0016.asm and code-0019.asm in
;;;   "lectures code " read hex digits with exactly this recurrence.
;;;
;;;   *** AND THAT STEP IS PRECISELY ONE INSTRUCTION. ***
;;;       vfmadd213ss xmm1, xmm0, [rdi + rax*4]
;;;   means  xmm1 := xmm0*xmm1 + [mem].  Decode the "213": the operands are
;;;   numbered 1, 2, 3 in the order written, and the digits say which are
;;;   multiplied and which is added -- operand 2 times operand 1, plus operand 3,
;;;   into operand 1. The variants exist so that whichever register already holds
;;;   the value you want to keep can be the destination:
;;;       132   op1 := op1*op3 + op2
;;;       213   op1 := op2*op1 + op3     <- this file: acc is op1
;;;       231   op1 := op2*op3 + op1     <- dotprod.asm: the accumulator is op1
;;;   FUSED means the multiply and the add are rounded ONCE between them, not
;;;   twice. That is why an FMA is both faster and strictly more accurate than a
;;;   separate `mulss` and `addss`.
;;;
;;;   NOTE THE `ss` SUFFIX: this is the SCALAR form, one lane. The same
;;;   instruction exists as `vfmadd213ps` for eight lanes at once -- see
;;;   dotprod.asm in this folder. Horner is inherently sequential (each step
;;;   needs the previous accumulator), so vectorising it means evaluating
;;;   several DIFFERENT x values in parallel, one per lane, rather than several
;;;   terms.
;;;
;;;   THE COEFFICIENTS ARE 1/k!, PRECOMPUTED. Note 0.16666667 rather than a
;;;   division by 6: a 32-bit float carries only about seven significant digits,
;;;   so the constants are given to that precision and no more. The visible error
;;;   at x = -2 is the TRUNCATION of the series at degree 11, not a bug -- try
;;;   raising NTERMS and adding the next coefficient.
;;;
;;;   `call expf wrt ..plt` IS A REAL LIBRARY CALL, and the reason the ./asm
;;;   script passes `-lm`: `expf` lives in libm, not in the main C library.
;;;   Notice that it takes its argument in xmm0 and returns in xmm0, exactly like
;;;   the assembly function above it -- the ABI does not distinguish.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/11/fma_horner.asm"
;;;
;;;   Compare against Python, which uses doubles throughout:
;;;   python3 -c "
;;;   import math
;;;   for x in (-2,-1,0,1,2): print('%5.1f %14.6f' % (x, math.exp(x)))"
;;;
;;;   Change `xs` to include 5.0 or 10.0 and watch the truncated series diverge
;;;   badly -- a Taylor polynomial about 0 is only good NEAR 0. That is exactly
;;;   why exp_x87.asm in ps_code/8 uses a range reduction instead.
;;;
;;; DEBUG IT   -- the author's own session, adapted to this course's scripts
;;;   ./debug "ps_code/11/fma_horner.asm"
;;;
;;;   Watch the accumulator climb one term at a time:
;;;     break dbg_fma
;;;     c
;;;     p $xmm0.v4_float[0]       x, the point being evaluated
;;;     display $xmm1.v4_float[0] the accumulator, sticky
;;;     si                        ONE fma folds in one more coefficient
;;;     c                         next term
;;;     c 11                      skip a whole polynomial in one go
;;;
;;;   Prove the FMA really is one instruction doing two operations:
;;;     break dbg_fma
;;;     c
;;;     p $xmm1.v4_float[0]       acc
;;;     p $xmm0.v4_float[0]       x
;;;     p $rax                    which coefficient is next
;;;     si
;;;     p $xmm1.v4_float[0]       and check it equals x*acc + coef[rax]
;;;
;;;   And see that a library call obeys exactly the same convention:
;;;     break expf
;;;     c
;;;     p $xmm0.v4_float[0]       the argument, in xmm0 -- just like horner_fma
;;;     finish
;;;     p $xmm0.v4_float[0]       the result, in xmm0
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   `horner_fma` HAS NO PROLOGUE -- no frame, no saved registers. It is a LEAF
;;;   function: it calls nothing, has no locals, and uses only caller-saved
;;;   registers (rax, xmm0, xmm1). The only stack it touches is the 8-byte return
;;;   address. Confirm it with `p $rsp` before and after a `finish`.
;;;
;;;   `main`, BY CONTRAST, NEEDS EVERYTHING, and the reason is instructive. Its
;;;   loop calls THREE functions per iteration -- horner_fma, expf and printf --
;;;   and it must keep the array pointer and the loop index alive across all
;;;   three. So it pushes r12 and rbx, which are CALLEE-SAVED and therefore the
;;;   only registers that survive a call:
;;;       push rbp / mov rbp, rsp / push r12 / push rbx / and rsp, -16
;;;   Verify the promise:
;;;       break expf
;;;       c
;;;       info registers rbx r12
;;;       finish
;;;       info registers rbx r12     unchanged
;;;
;;;   *** AND NOW LOOK AT WHAT MAIN HAS TO DO WITH THE FLOATS, because this is
;;;   the sharpest illustration in the course of a rule you have been told
;;;   repeatedly. *** It needs three doubles alive at the same moment for the
;;;   final printf -- x, the approximation, and expf's answer -- but they are
;;;   produced by three separate calls, and ALL SIXTEEN xmm REGISTERS ARE
;;;   CALLER-SAVED. There is no floating-point equivalent of r12. So each result
;;;   is spilled to .bss the instant it arrives:
;;;       call horner_fma / cvtss2sd / movsd [t_app], xmm0
;;;       call expf       / cvtss2sd / movsd [t_exa], xmm0
;;;       ...             / cvtss2sd / movsd [t_x],   xmm0
;;;   and only then are all three reloaded into xmm0, xmm1, xmm2 for the call.
;;;   Watch it:
;;;       break printf
;;;       c   c
;;;       p $xmm0.v2_double[0]      x
;;;       p $xmm1.v2_double[0]      the approximation
;;;       p $xmm2.v2_double[0]      expf's answer
;;;       p $rax                    3 -- three vector registers carry arguments
;;;   THREE VALUES, THREE MEMORY SLOTS, because there was nowhere else to put
;;;   them. Compare dotprod.asm, whose inner loop contains no calls at all
;;;   precisely so its accumulator can stay in a register.
;;;
;;;   The epilogue's `lea rsp, [rbp-16]` is the same trick as packed.asm's
;;;   `[rbp-24]`: land exactly on the last thing pushed -- TWO registers here, so
;;;   16 rather than 24 -- then pop them in REVERSE order before the frame
;;;   pointer. Count the pushes and the number follows.
;;; ============================================================================

; fma_horner.asm  --  Taylor series for e^x by Horner's rule, using FMA.
; ===========================================================================
; GOAL: approximate e^x = 1 + x + x^2/2! + ... and check against libm expf().
;
; HORNER'S RULE evaluates a polynomial with only multiplies and adds:
;     e^x ~= a0 + x*(a1 + x*(a2 + ...))
; Start the accumulator at the top coefficient, then repeat:
;     acc <- x*acc + coef[i]
; THAT STEP IS EXACTLY ONE FMA:
;     vfmadd213ss xmm1, xmm0, [mem]   means   xmm1 <- (xmm0 * xmm1) + [mem]
;   "213" names the operand order: op1 <- op2*op1 + op3.  "Fused" = one rounding
;   for the whole multiply-add: faster and more accurate than mulss + addss.
;
; ---------------------------------------------------------------------------
; DEBUGGING -- watch the accumulator xmm1 update once per Horner step
;
;   nasm -f elf64 -g -F dwarf fma_horner.asm -o fma_horner.o
;   gcc -g -o fma_horner fma_horner.o -lm
;   gdb -q ./fma_horner
;     (gdb) break dbg_fma          # stops in the loop, on the vfmadd213ss
;     (gdb) run
;     (gdb) print $xmm0.v4_float   # x (the point being evaluated)
;     (gdb) print $xmm1.v4_float   # acc BEFORE this term
;     (gdb) display $xmm1.v4_float # sticky view of the accumulator
;     (gdb) stepi                  # do one FMA ; acc <- x*acc + coef[i]
;     (gdb) continue               # next iteration hits the breakpoint again
;     (gdb) continue 11            # skip ahead 11 hits (one full polynomial)
;   Or non-interactively:  make inspect PROG=fma_horner
; ---------------------------------------------------------------------------
; Build:  nasm -f elf64 fma_horner.asm -o fma_horner.o && gcc fma_horner.o -o fma_horner -lm
; ===========================================================================

            global main
                                                   ;   export `main` for the C library start-up
            global dbg_fma                         ; breakpoint target (the FMA step)
                                                   ;   exported ONLY so gdb has a name to break on
            extern printf
                                                   ;   from the C library
            extern expf                            ; libm (-lm)
                                                   ;   from libm -- which is why the ./asm script passes -lm

            section .rodata
                                                   ;   READ-ONLY data: constants that are never written
            align 4
                                                   ;   pad to a 4-byte boundary, the natural alignment of a float
NTERMS      equ 12                                 ; degree-11 polynomial
                                                   ;   `equ` = an assemble-time constant: twelve coefficients,
                                                   ;   hence a degree-11 polynomial
coef:       dd 1.0, 1.0, 0.5, 0.16666667, 0.041666668, 0.008333334
                                                   ;   the Taylor coefficients 1/k! for k = 0..11, given to about
                                                   ;   seven significant digits -- which is all a 32-bit float
                                                   ;   carries. `dd` emits 32-bit floats.
            dd 0.0013888889, 0.00019841270, 2.4801588e-05, 2.7557319e-06
            dd 2.7557319e-07, 2.5052108e-08
xs:         dd -2.0, -1.0, 0.0, 1.0, 2.0
                                                   ;   the five points to evaluate at
NX          equ 5
                                                   ;   ...and how many there are
hdr:        db "e^x via FMA-Horner (degree 11) vs libm expf():", 10
                                                   ;   a two-line header, only the last `db` terminated
            db "    x        horner_fma         expf", 10, 0
fmt:        db "  %5.1f   %14.6f   %14.6f", 10, 0
                                                   ;   THREE doubles: %5.1f, %14.6f, %14.6f. That is why AL = 3
                                                   ;   at the call below.
note:       db 10, "Each Horner step was one vfmadd213ss: acc <- x*acc + coef[i].", 10, 0
                                                   ;   the closing note

            section .bss
                                                   ;   zero-filled at load time. THREE SPILL SLOTS -- see the
                                                   ;   call-stack notes: there is no callee-saved xmm register,
                                                   ;   so results must go to memory between calls.
t_x:        resq 1
t_app:      resq 1
t_exa:      resq 1

            section .text
                                                   ;   the executable-code section
; float horner_fma(rdi = coef, rsi = n, xmm0 = x) -> xmm0
                                                   ;   float horner_fma(const float *coef, long n, float x)
                                                   ;   coef in rdi, n in rsi, x in xmm0 -- integer and float
                                                   ;   arguments are counted in SEPARATE sequences.
; (uses unique non-local labels so the exported dbg_fma label does not split a
;  local-label scope -- a NASM rule: any non-local label ends the local scope.)
horner_fma: test    rsi, rsi
                                                   ;   `test x, x` is the idiomatic "is this zero?": an AND that
                                                   ;   keeps only the flags. NOTE: no prologue -- a LEAF function.
            jle     horner_zero
                                                   ;   `jle` = jump if less or equal, signed
            mov     rax, rsi
                                                   ;   walk the coefficients from the TOP down
            dec     rax                            ; rax = n-1
                                                   ;   rax = n-1, the highest index
            movss   xmm1, [rdi + rax*4]            ; acc = coef[n-1]
                                                   ;   acc = coef[n-1]. base + 4*index, with 4 because the
                                                   ;   elements are 32-bit floats.
            test    rax, rax
                                                   ;   only one coefficient? then it is already the answer
            jz      horner_done
horner_loop:
                                                   ;   non-local labels, deliberately: an exported `dbg_` label
                                                   ;   would otherwise split the local-label scope
            dec     rax
                                                   ;   move down to the next coefficient
dbg_fma:                                           ; <-- break: about to fold in coef[rax]
                                                   ;   a label at the SAME address, exported for gdb
            vfmadd213ss xmm1, xmm0, [rdi + rax*4]  ; acc <- x*acc + coef[rax]
                                                   ;   THE HORNER STEP, AS ONE INSTRUCTION: acc := x*acc +
                                                   ;   coef[rax]. "213" names the operand roles -- operand 2
                                                   ;   times operand 1, plus operand 3, into operand 1. FUSED:
                                                   ;   one rounding for the whole multiply-add, so it is faster
                                                   ;   AND more accurate than a separate mulss and addss.
            test    rax, rax
                                                   ;   reached index 0?
            jnz     horner_loop
                                                   ;   ...if not, fold in another term
horner_done:
            movss   xmm0, xmm1
                                                   ;   the ABI puts the return value in xmm0
            ret
                                                   ;   pop the return address into rip
horner_zero:
                                                   ;   the degenerate case: no coefficients at all
            xorps   xmm0, xmm0
                                                   ;   return 0.0. XOR with itself is the idiomatic clear.
            ret

main:       push    rbp
                                                   ;   int main(void)
            mov     rbp, rsp
                                                   ;   prologue: save the caller's frame pointer
            push    r12
                                                   ;   r12 and rbx are CALLEE-SAVED, and therefore the only
                                                   ;   registers that survive the three calls in the loop below
            push    rbx
            and     rsp, -16
                                                   ;   round rsp DOWN to a multiple of 16, for the calls

            lea     rdi, [rel hdr]
                                                   ;   the header line
            xor     eax, eax
                                                   ;   0 vector registers
            call    printf wrt ..plt

            lea     r12, [rel xs]
                                                   ;   the array of x values, parked in a callee-saved register
            xor     rbx, rbx
                                                   ;   the loop index, likewise
.next:      cmp     rbx, NX
                                                   ;   `.next` is LOCAL to main
            jge     .end

            movss   xmm0, [r12 + rbx*4]            ; x
                                                   ;   load one x. Its own argument register, xmm0.
            lea     rdi, [rel coef]
                                                   ;   horner_fma's first integer argument: the coefficients
            mov     rsi, NTERMS
                                                   ;   ...and its second: how many
            call    horner_fma                     ; approx
                                                   ;   -> the approximation, in xmm0
            cvtss2sd xmm0, xmm0
                                                   ;   widen to double, because %f reads a DOUBLE
            movsd   [rel t_app], xmm0
                                                   ;   SPILL IT. The next call would destroy xmm0, and there is
                                                   ;   no callee-saved vector register to hide it in.

            movss   xmm0, [r12 + rbx*4]            ; expf(x)
                                                   ;   reload x for the library call
            call    expf wrt ..plt
                                                   ;   a real libm call -- and note it uses exactly the same
                                                   ;   convention as the assembly function above: argument in
                                                   ;   xmm0, result in xmm0
            cvtss2sd xmm0, xmm0
                                                   ;   widen to double
            movsd   [rel t_exa], xmm0
                                                   ;   spill this one too

            movss   xmm0, [r12 + rbx*4]            ; x as double
                                                   ;   and x itself, as a double
            cvtss2sd xmm0, xmm0
            movsd   [rel t_x], xmm0

            movsd   xmm0, [rel t_x]
                                                   ;   now reload all three, into the registers the ABI wants
            movsd   xmm1, [rel t_app]
            movsd   xmm2, [rel t_exa]
            lea     rdi, [rel fmt]
                                                   ;   printf argument 1: the format string
            mov     eax, 3                         ; AL = 3 vector args
                                                   ;   THREE vector registers carry arguments
            call    printf wrt ..plt

            inc     rbx
                                                   ;   next x
            jmp     .next
.end:
                                                   ;   all five done
            lea     rdi, [rel note]
                                                   ;   the closing note
            xor     eax, eax
            call    printf wrt ..plt

            xor     eax, eax
                                                   ;   main's return value: 0 = success
            lea     rsp, [rbp-16]
                                                   ;   land exactly on the last thing pushed -- TWO registers, so
                                                   ;   16. `mov rsp, rbp` would skip past them.
            pop     rbx
                                                   ;   restore them IN REVERSE ORDER to the pushes
            pop     r12
            pop     rbp
                                                   ;   ...and finally the caller's frame pointer
            ret
                                                   ;   pop the return address into rip

section .note.GNU-stack noalloc noexec nowrite progbits
                                                   ;   the "no executable stack" marker

