; dotprod.asm  --  Dot product: packed FMA, then a cross-lane fold (pure asm).
; ===========================================================================
; A dot product is  sum of a[i]*b[i]  -> a single number. Two phases:
;
; PHASE 1 -- VERTICAL (lane-parallel, easy):
;   Sweep 8 elements at a time. One vfmadd231ps does, for all 8 lanes:
;       acc[lane] <- a[lane]*b[lane] + acc[lane]
;   ("231": op1 <- op2*op3 + op1.)  After the loop, acc holds 8 PARTIAL sums.
;
; PHASE 2 -- CROSS-LANE FOLD (the interesting part):
;   We need ONE number, but the sum is spread across 8 lanes. Combining lanes
;   means moving data BETWEEN lanes. Done once, at the end:
;       vextractf128 : upper 128 bits (lanes 4..7) down to an xmm
;       vaddps       : add to lanes 0..3        -> 4 partials
;       vhaddps      : horizontal add pairs     -> 2 partials
;       vhaddps      : again                    -> 1 final sum (lane 0)
;
; ---------------------------------------------------------------------------
; DEBUGGING -- watch 8 partial sums accumulate, then collapse to 1
;
;   nasm -f elf64 -g -F dwarf dotprod.asm -o dotprod.o
;   gcc -g -o dotprod dotprod.o
;   gdb -q ./dotprod
;     (gdb) break dbg_dot_acc      # the vfmadd231ps in the inner loop
;     (gdb) run
;     (gdb) display $ymm0.v8_float # the 8 running partial sums
;     (gdb) stepi                  # one FMA folds in 8 more products
;     (gdb) continue               # next 8 elements (breakpoint again)
;
;     (gdb) break dbg_dot_fold     # first instruction of the reduction
;     (gdb) continue
;     (gdb) print $ymm0.v8_float   # 8 partials, just before folding
;     (gdb) stepi                  # vextractf128
;     (gdb) print $xmm0.v4_float   # watch 8 -> 4 -> 2 -> 1 as you step
;   Or non-interactively:  make inspect PROG=dotprod
; ---------------------------------------------------------------------------
; Build:  nasm -f elf64 dotprod.asm -o dotprod.o && gcc dotprod.o -o dotprod
; ===========================================================================

            global main
            global dbg_dot_acc            ; breakpoint: the accumulating FMA
            global dbg_dot_fold           ; breakpoint: start of the fold
            extern printf

            section .bss
            align 32
N           equ 4096
a:          resd N
b:          resd N

            section .rodata
hdr:        db "Dot product of two length-4096 vectors:", 10, 0
fmt:        db "  %-26s = %.1f", 10, 0
l_simd:     db "AVX+FMA (8 lanes + fold)", 0
l_ref:      db "scalar reference", 0
note:       db 10, "Inner loop: one vfmadd231ps per 8 elements; lanes folded once.", 10, 0

            section .text
; float dot_avx(rdi=a, rsi=b, rdx=n)  -- n multiple of 8
; (unique non-local labels: the exported dbg_ labels must not split a local scope)
dot_avx:    vxorps  ymm0, ymm0, ymm0      ; acc = 0 (8 lanes)
            xor     rax, rax
dot_loop:   cmp     rax, rdx
            jge     dot_reduce
            vmovups ymm1, [rdi + rax*4]
            vmovups ymm2, [rsi + rax*4]
dbg_dot_acc:                              ; <-- break: acc, a, b before the FMA
            vfmadd231ps ymm0, ymm1, ymm2  ; acc += a*b (8 lanes)
            add     rax, 8
            jmp     dot_loop
dot_reduce:
dbg_dot_fold:                             ; <-- break: 8 partials, about to fold
            vextractf128 xmm1, ymm0, 1    ; lanes 4..7
            vaddps  xmm0, xmm0, xmm1      ; -> 4 partials
            vhaddps xmm0, xmm0, xmm0      ; -> 2
            vhaddps xmm0, xmm0, xmm0      ; -> 1 (lane 0)
            vzeroupper
            ret

; float dot_scalar(rdi=a, rsi=b, rdx=n)
dot_scalar: vxorps  xmm0, xmm0, xmm0
            xor     rax, rax
.l:         cmp     rax, rdx
            jge     .d
            movss   xmm1, [rdi + rax*4]
            mulss   xmm1, [rsi + rax*4]
            addss   xmm0, xmm1
            inc     rax
            jmp     .l
.d:         ret

main:       push    rbp
            mov     rbp, rsp
            and     rsp, -16

            ; fill a[i] = (i % 7) + 1,  b[i] = 2.0
            lea     rdi, [rel a]
            lea     rsi, [rel b]
            xor     r10, r10
            mov     ecx, 7
.fill:      cmp     r10, N
            jge     .filled
            mov     rax, r10
            xor     rdx, rdx
            div     rcx
            lea     eax, [rdx + 1]
            cvtsi2ss xmm0, eax
            movss   [rdi + r10*4], xmm0
            mov     dword [rsi + r10*4], 0x40000000   ; 2.0f
            inc     r10
            jmp     .fill
.filled:
            lea     rdi, [rel hdr]
            xor     eax, eax
            call    printf wrt ..plt

            lea     rdi, [rel a]
            lea     rsi, [rel b]
            mov     rdx, N
            call    dot_avx
            cvtss2sd xmm0, xmm0
            lea     rdi, [rel fmt]
            lea     rsi, [rel l_simd]
            mov     eax, 1
            call    printf wrt ..plt

            lea     rdi, [rel a]
            lea     rsi, [rel b]
            mov     rdx, N
            call    dot_scalar
            cvtss2sd xmm0, xmm0
            lea     rdi, [rel fmt]
            lea     rsi, [rel l_ref]
            mov     eax, 1
            call    printf wrt ..plt

            lea     rdi, [rel note]
            xor     eax, eax
            call    printf wrt ..plt

            xor     eax, eax
            mov     rsp, rbp
            pop     rbp
            ret

section .note.GNU-stack noalloc noexec nowrite progbits
