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
            global dbg_fma                ; breakpoint target (the FMA step)
            extern printf
            extern expf                   ; libm (-lm)

            section .rodata
            align 4
NTERMS      equ 12                        ; degree-11 polynomial
coef:       dd 1.0, 1.0, 0.5, 0.16666667, 0.041666668, 0.008333334
            dd 0.0013888889, 0.00019841270, 2.4801588e-05, 2.7557319e-06
            dd 2.7557319e-07, 2.5052108e-08
xs:         dd -2.0, -1.0, 0.0, 1.0, 2.0
NX          equ 5
hdr:        db "e^x via FMA-Horner (degree 11) vs libm expf():", 10
            db "    x        horner_fma         expf", 10, 0
fmt:        db "  %5.1f   %14.6f   %14.6f", 10, 0
note:       db 10, "Each Horner step was one vfmadd213ss: acc <- x*acc + coef[i].", 10, 0

            section .bss
t_x:        resq 1
t_app:      resq 1
t_exa:      resq 1

            section .text
; float horner_fma(rdi = coef, rsi = n, xmm0 = x) -> xmm0
; (uses unique non-local labels so the exported dbg_fma label does not split a
;  local-label scope -- a NASM rule: any non-local label ends the local scope.)
horner_fma: test    rsi, rsi
            jle     horner_zero
            mov     rax, rsi
            dec     rax                   ; rax = n-1
            movss   xmm1, [rdi + rax*4]   ; acc = coef[n-1]
            test    rax, rax
            jz      horner_done
horner_loop:
            dec     rax
dbg_fma:                                  ; <-- break: about to fold in coef[rax]
            vfmadd213ss xmm1, xmm0, [rdi + rax*4]  ; acc <- x*acc + coef[rax]
            test    rax, rax
            jnz     horner_loop
horner_done:
            movss   xmm0, xmm1
            ret
horner_zero:
            xorps   xmm0, xmm0
            ret

main:       push    rbp
            mov     rbp, rsp
            push    r12
            push    rbx
            and     rsp, -16

            lea     rdi, [rel hdr]
            xor     eax, eax
            call    printf wrt ..plt

            lea     r12, [rel xs]
            xor     rbx, rbx
.next:      cmp     rbx, NX
            jge     .end

            movss   xmm0, [r12 + rbx*4]   ; x
            lea     rdi, [rel coef]
            mov     rsi, NTERMS
            call    horner_fma            ; approx
            cvtss2sd xmm0, xmm0
            movsd   [rel t_app], xmm0

            movss   xmm0, [r12 + rbx*4]   ; expf(x)
            call    expf wrt ..plt
            cvtss2sd xmm0, xmm0
            movsd   [rel t_exa], xmm0

            movss   xmm0, [r12 + rbx*4]   ; x as double
            cvtss2sd xmm0, xmm0
            movsd   [rel t_x], xmm0

            movsd   xmm0, [rel t_x]
            movsd   xmm1, [rel t_app]
            movsd   xmm2, [rel t_exa]
            lea     rdi, [rel fmt]
            mov     eax, 3                ; AL = 3 vector args
            call    printf wrt ..plt

            inc     rbx
            jmp     .next
.end:
            lea     rdi, [rel note]
            xor     eax, eax
            call    printf wrt ..plt

            xor     eax, eax
            lea     rsp, [rbp-16]
            pop     rbx
            pop     r12
            pop     rbp
            ret

section .note.GNU-stack noalloc noexec nowrite progbits
