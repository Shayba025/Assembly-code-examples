; loads.asm  --  Aligned vs unaligned packed loads (pure asm program).
; ===========================================================================
; The move instructions come in an ALIGNED and an UNALIGNED form:
;   vmovaps   ALIGNED   -- FAULTS unless the address is 32-byte aligned.
;   vmovups   UNALIGNED -- works at ANY address.
; On modern CPUs both cost the same when the data IS aligned, so unaligned is
; the safe default. This program sums an aligned array both ways (same total),
; then does a vmovups from a deliberately MISALIGNED address (arr+1 float),
; which succeeds -- a vmovaps there would fault.
;
; ---------------------------------------------------------------------------
; DEBUGGING -- watch a vector LOAD populate ymm1, and see the misaligned case
;
;   nasm -f elf64 -g -F dwarf loads.asm -o loads.o
;   gcc -g -o loads loads.o
;   gdb -q ./loads
;     (gdb) break dbg_aligned      # inside sum_aligned, on the vmovaps
;     (gdb) run
;     (gdb) print $ymm1.v8_float   # stale, before the load
;     (gdb) stepi                  # vmovaps fills ymm1 with 8 aligned floats
;     (gdb) print $ymm1.v8_float   # {1,1,1,1,1,1,1,1}
;     (gdb) display $ymm0.v8_float # the running sum across iterations
;
;     (gdb) break dbg_misaligned   # the vmovups from arr+1 (NOT 32-aligned)
;     (gdb) continue
;     (gdb) stepi                  # unaligned load succeeds; lane 0 = arr[1]
;     (gdb) print $ymm0.v8_float
;   Or non-interactively:  make inspect PROG=loads
; ---------------------------------------------------------------------------
; Build:  nasm -f elf64 loads.asm -o loads.o && gcc loads.o -o loads
; ===========================================================================

            global main
            global dbg_aligned            ; breakpoint: the vmovaps load
            global dbg_misaligned         ; breakpoint: the misaligned vmovups
            extern printf

            section .bss
            align 32
N           equ 4096
arr:        resd N
onef:       resd 1

            section .rodata
hdr:        db "Summing 4096 aligned floats, two ways:", 10, 0
fmt:        db "  %-22s = %.1f", 10, 0
l_a:        db "vmovaps (aligned)", 0
l_u:        db "vmovups (unaligned)", 0
fmt2:       db 10, "  vmovups from misaligned arr+1 -> lane0 = %.1f", 10, 0
note:       db "  (a vmovaps at arr+1 would have faulted -- hence prefer unaligned)", 10, 0

            section .text
; float sum_aligned(rdi=a, rsi=n)
; (unique non-local labels so dbg_aligned does not split a local-label scope)
sum_aligned:    vxorps  ymm0, ymm0, ymm0
            xor     rax, rax
al_loop:    cmp     rax, rsi
            jge     al_done
dbg_aligned:                              ; <-- break: about to ALIGNED-load 8 floats
            vmovaps ymm1, [rdi + rax*4]
            vaddps  ymm0, ymm0, ymm1
            add     rax, 8
            jmp     al_loop
al_done:    vextractf128 xmm1, ymm0, 1
            vaddps  xmm0, xmm0, xmm1
            vhaddps xmm0, xmm0, xmm0
            vhaddps xmm0, xmm0, xmm0
            vzeroupper
            ret

; float sum_unaligned(rdi=a, rsi=n)
sum_unaligned:  vxorps  ymm0, ymm0, ymm0
            xor     rax, rax
.l:         cmp     rax, rsi
            jge     .r
            vmovups ymm1, [rdi + rax*4]
            vaddps  ymm0, ymm0, ymm1
            add     rax, 8
            jmp     .l
.r:         vextractf128 xmm1, ymm0, 1
            vaddps  xmm0, xmm0, xmm1
            vhaddps xmm0, xmm0, xmm0
            vhaddps xmm0, xmm0, xmm0
            vzeroupper
            ret

main:       push    rbp
            mov     rbp, rsp
            and     rsp, -16

            ; fill arr[i] = 1.0f
            lea     rdi, [rel arr]
            xor     rax, rax
            mov     dword [rel onef], 0x3f800000
            movss   xmm1, [rel onef]
.fill:      cmp     rax, N
            jge     .done
            movss   [rdi + rax*4], xmm1
            inc     rax
            jmp     .fill
.done:
            lea     rdi, [rel hdr]
            xor     eax, eax
            call    printf wrt ..plt

            lea     rdi, [rel arr]
            mov     rsi, N
            call    sum_aligned
            cvtss2sd xmm0, xmm0
            lea     rdi, [rel fmt]
            lea     rsi, [rel l_a]
            mov     eax, 1
            call    printf wrt ..plt

            lea     rdi, [rel arr]
            mov     rsi, N
            call    sum_unaligned
            cvtss2sd xmm0, xmm0
            lea     rdi, [rel fmt]
            lea     rsi, [rel l_u]
            mov     eax, 1
            call    printf wrt ..plt

            lea     rdi, [rel arr]
dbg_misaligned:                           ; <-- break: unaligned load from arr+1
            vmovups ymm0, [rdi + 4]       ; arr + 1 float : NOT 32-byte aligned
            vzeroupper
            cvtss2sd xmm0, xmm0
            lea     rdi, [rel fmt2]
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
