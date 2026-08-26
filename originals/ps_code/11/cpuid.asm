; cpuid.asm  --  detect SSE/AVX support with the CPUID instruction (pure asm).
; ===========================================================================
; WHY THIS PROGRAM IS FIRST
;   The AVX/FMA demos later need a CPU that supports those features. CPUID is
;   the hardware's own answer to "what can I do?". Run this first.
;
; HOW CPUID WORKS
;   Put a "leaf" number in EAX, run the single instruction `cpuid`, and the CPU
;   writes feature bits back into EAX/EBX/ECX/EDX. One bit = one feature.
;     leaf 1 : EDX[25]=SSE  EDX[26]=SSE2   ECX[28]=AVX  ECX[12]=FMA
;     leaf 7 : EBX[5]=AVX2  EBX[16]=AVX-512F   (set ECX=0 first)
;   cpuid clobbers all four registers, so we save the words to memory and only
;   then test bits (shift the bit down to position 0, AND with 1).
;
; ---------------------------------------------------------------------------
; DEBUGGING -- watch the GENERAL-PURPOSE registers cpuid fills in
;   (cpuid produces integer flag words, not vector data -- a useful contrast
;    with the SSE/AVX programs, which is why we inspect eax/ebx/ecx/edx here.)
;
;   nasm -f elf64 -g -F dwarf cpuid.asm -o cpuid.o
;   gcc -g -o cpuid cpuid.o
;   gdb -q ./cpuid
;     (gdb) break dbg_cpuid        # stops right AFTER the leaf-1 cpuid
;     (gdb) run
;     (gdb) info registers eax ebx ecx edx   # the raw feature words
;     (gdb) print/t $ecx           # ECX in BINARY: bit 28 (AVX), bit 12 (FMA)
;     (gdb) print/t $edx           # EDX in binary: bit 25 (SSE), bit 26 (SSE2)
;     (gdb) display/t $eax         # sticky binary view, updates on each step
;     (gdb) stepi                  # step one instruction; watch eax/ecx/edx
;     (gdb) continue
;   Or non-interactively:  make inspect PROG=cpuid
; ---------------------------------------------------------------------------
; Build:  nasm -f elf64 cpuid.asm -o cpuid.o && gcc cpuid.o -o cpuid
; ===========================================================================

            global main
            global dbg_cpuid              ; exported so gdb can break by name
            extern printf

            section .bss
edx1:       resd 1                        ; saved EDX from leaf 1 (SSE / SSE2)
ecx1:       resd 1                        ; saved ECX from leaf 1 (AVX / FMA)
ebx7:       resd 1                        ; saved EBX from leaf 7 (AVX2 / AVX-512F)

            section .rodata
hdr:        db "SIMD support (read straight from CPUID):", 10, 0
fmt:        db "  %-9s: %s", 10, 0
yes:        db "yes", 0
no:         db "no", 0
n_sse:      db "sse", 0
n_sse2:     db "sse2", 0
n_avx:      db "avx", 0
n_fma:      db "fma", 0
n_avx2:     db "avx2", 0
n_avx512:   db "avx512f", 0

            section .text
; report(rdi = name, esi = flag) : prints "  name : yes/no"
report:     push    rbp
            mov     rbp, rsp
            and     rsp, -16
            lea     rdx, [rel no]
            test    esi, esi
            jz      .go
            lea     rdx, [rel yes]
.go:        mov     rsi, rdi
            lea     rdi, [rel fmt]
            xor     eax, eax              ; no vector args -> AL = 0
            call    printf wrt ..plt
            mov     rsp, rbp
            pop     rbp
            ret

main:       push    rbp
            mov     rbp, rsp
            and     rsp, -16

            mov     eax, 1                ; leaf 1
            cpuid                         ; -> EAX EBX ECX EDX (all clobbered)
dbg_cpuid:                                ; <-- breakpoint: ECX/EDX hold the flags
            mov     [rel edx1], edx       ; SSE / SSE2
            mov     [rel ecx1], ecx       ; AVX / FMA

            mov     eax, 7                ; leaf 7
            xor     ecx, ecx              ; sub-leaf 0 (required)
            cpuid
            mov     [rel ebx7], ebx       ; AVX2 / AVX-512F

            lea     rdi, [rel hdr]
            xor     eax, eax
            call    printf wrt ..plt

            mov     eax, [rel edx1]       ; sse = EDX[25]
            shr     eax, 25
            and     eax, 1
            mov     esi, eax
            lea     rdi, [rel n_sse]
            call    report

            mov     eax, [rel edx1]       ; sse2 = EDX[26]
            shr     eax, 26
            and     eax, 1
            mov     esi, eax
            lea     rdi, [rel n_sse2]
            call    report

            mov     eax, [rel ecx1]       ; avx = ECX[28]
            shr     eax, 28
            and     eax, 1
            mov     esi, eax
            lea     rdi, [rel n_avx]
            call    report

            mov     eax, [rel ecx1]       ; fma = ECX[12]
            shr     eax, 12
            and     eax, 1
            mov     esi, eax
            lea     rdi, [rel n_fma]
            call    report

            mov     eax, [rel ebx7]       ; avx2 = EBX[5]
            shr     eax, 5
            and     eax, 1
            mov     esi, eax
            lea     rdi, [rel n_avx2]
            call    report

            mov     eax, [rel ebx7]       ; avx512f = EBX[16]
            shr     eax, 16
            and     eax, 1
            mov     esi, eax
            lea     rdi, [rel n_avx512]
            call    report

            xor     eax, eax
            mov     rsp, rbp
            pop     rbp
            ret

section .note.GNU-stack noalloc noexec nowrite progbits
