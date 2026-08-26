; packed.asm  --  Packed (vertical) parallel arithmetic (pure asm program).
; ===========================================================================
; The heart of SIMD: the PACKED suffix "ps".
;   A scalar add (addss) touches ONE lane.
;   A packed add (addps) touches EVERY lane in one instruction:
;       for all lanes i:  v[i] = a[i] + b[i]
;   The lanes are independent, so the hardware computes them simultaneously.
;   Wider register -> more lanes:
;       addps  on xmm (128-bit) = 4 floats at once
;       vaddps on ymm (256-bit) = 8 floats at once
;
; ---------------------------------------------------------------------------
; DEBUGGING -- watch ALL lanes change at once on a single packed instruction
;
;   nasm -f elf64 -g -F dwarf packed.asm -o packed.o
;   gcc -g -o packed packed.o
;   gdb -q ./packed
;     (gdb) break dbg_addps        # inside add4_ps, just before addps (xmm)
;     (gdb) run
;     (gdb) print $xmm0.v4_float   # a = {1, 2, 3, 4}
;     (gdb) print $xmm1.v4_float   # b = {10, 20, 30, 40}
;     (gdb) stepi                  # ONE addps updates all 4 lanes
;     (gdb) print $xmm0.v4_float   # {11, 22, 33, 44}
;
;     (gdb) break dbg_vaddps       # inside add8_ps, just before vaddps (ymm)
;     (gdb) continue
;     (gdb) print $ymm0.v8_float   # a = {1..8}
;     (gdb) display $ymm0.v8_float # sticky
;     (gdb) stepi                  # ONE vaddps updates all 8 lanes
;   Or non-interactively:  make inspect PROG=packed
; ---------------------------------------------------------------------------
; Build:  nasm -f elf64 packed.asm -o packed.o && gcc packed.o -o packed
; ===========================================================================

            global main
            global dbg_addps              ; breakpoint: the 4-lane addps
            global dbg_vaddps             ; breakpoint: the 8-lane vaddps
            extern printf

            section .data
            align 32
a8:         dd 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0
b8:         dd 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0
res:        times 8 dd 0.0

            section .rodata
h_sse:      db "SSE: one instruction, 4 lanes (xmm, 128-bit)", 10, 0
h_avx:      db 10, "AVX: one instruction, 8 lanes (ymm, 256-bit)", 10, 0
l_a:        db "  a       :", 0
l_b:        db "  b       :", 0
l_add:      db "  addps   :", 0
l_sub:      db "  subps   :", 0
l_mul:      db "  mulps   :", 0
l_vadd:     db "  vaddps  :", 0
fmt_f:      db " %7.1f", 0
lblfmt:     db "%s", 0
nl:         db 10, 0
note:       db 10, "No loop ran outside the packed instruction itself.", 10, 0

            section .text
; rdi=dst rsi=a rdx=b
add4_ps:    movups  xmm0, [rsi]
            movups  xmm1, [rdx]
dbg_addps:                                ; <-- break: xmm0=a, xmm1=b, before add
            addps   xmm0, xmm1            ; 4 parallel adds
            movups  [rdi], xmm0
            ret
sub4_ps:    movups  xmm0, [rsi]
            movups  xmm1, [rdx]
            subps   xmm0, xmm1
            movups  [rdi], xmm0
            ret
mul4_ps:    movups  xmm0, [rsi]
            movups  xmm1, [rdx]
            mulps   xmm0, xmm1
            movups  [rdi], xmm0
            ret
add8_ps:    vmovups ymm0, [rsi]
            vmovups ymm1, [rdx]
dbg_vaddps:                               ; <-- break: ymm0=a, ymm1=b, before add
            vaddps  ymm0, ymm0, ymm1      ; 8 parallel adds
            vmovups [rdi], ymm0
            vzeroupper
            ret

; print_vec(rdi=label, rsi=ptr, rdx=count)
print_vec:  push    rbp
            mov     rbp, rsp
            push    r12
            push    r13
            push    rbx
            and     rsp, -16
            mov     r12, rsi
            mov     r13, rdx
            mov     rsi, rdi
            lea     rdi, [rel lblfmt]
            xor     eax, eax
            call    printf wrt ..plt
            xor     rbx, rbx
.l:         cmp     rbx, r13
            jge     .done
            movss   xmm0, [r12 + rbx*4]
            cvtss2sd xmm0, xmm0
            lea     rdi, [rel fmt_f]
            mov     eax, 1
            call    printf wrt ..plt
            inc     rbx
            jmp     .l
.done:      lea     rdi, [rel nl]
            xor     eax, eax
            call    printf wrt ..plt
            lea     rsp, [rbp-24]
            pop     rbx
            pop     r13
            pop     r12
            pop     rbp
            ret

main:       push    rbp
            mov     rbp, rsp
            and     rsp, -16

            lea     rdi, [rel h_sse]
            xor     eax, eax
            call    printf wrt ..plt

            lea     rdi, [rel l_a]
            lea     rsi, [rel a8]
            mov     rdx, 4
            call    print_vec
            lea     rdi, [rel l_b]
            lea     rsi, [rel b8]
            mov     rdx, 4
            call    print_vec

            lea     rdi, [rel res]
            lea     rsi, [rel a8]
            lea     rdx, [rel b8]
            call    add4_ps
            lea     rdi, [rel l_add]
            lea     rsi, [rel res]
            mov     rdx, 4
            call    print_vec

            lea     rdi, [rel res]
            lea     rsi, [rel a8]
            lea     rdx, [rel b8]
            call    sub4_ps
            lea     rdi, [rel l_sub]
            lea     rsi, [rel res]
            mov     rdx, 4
            call    print_vec

            lea     rdi, [rel res]
            lea     rsi, [rel a8]
            lea     rdx, [rel b8]
            call    mul4_ps
            lea     rdi, [rel l_mul]
            lea     rsi, [rel res]
            mov     rdx, 4
            call    print_vec

            lea     rdi, [rel h_avx]
            xor     eax, eax
            call    printf wrt ..plt

            lea     rdi, [rel res]
            lea     rsi, [rel a8]
            lea     rdx, [rel b8]
            call    add8_ps
            lea     rdi, [rel l_vadd]
            lea     rsi, [rel res]
            mov     rdx, 8
            call    print_vec

            lea     rdi, [rel note]
            xor     eax, eax
            call    printf wrt ..plt

            xor     eax, eax
            mov     rsp, rbp
            pop     rbp
            ret

section .note.GNU-stack noalloc noexec nowrite progbits
