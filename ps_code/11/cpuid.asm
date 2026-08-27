;;; ============================================================================
;;; cpuid.asm -- asking the CPU what it can do
;;; Practice session 11                      (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints yes or no for each of sse, sse2, avx, fma, avx2 and avx512f, read
;;;   straight out of the hardware.
;;;   (Verified under this course's Docker setup: sse, sse2, avx, fma and avx2
;;;   all yes -- which is why every other file in ps_code/11 runs. Note qemu is
;;;   EMULATING an x86-64 CPU here, so what you are seeing is qemu's answer, not
;;;   your Mac's.)
;;;
;;;   RUN THIS ONE FIRST, as the author says. If `avx` came back `no`, the other
;;;   programs in this folder would die with SIGILL -- an illegal instruction --
;;;   and the reason would be entirely non-obvious.
;;;
;;;   HOW `cpuid` WORKS. Put a LEAF number in eax, execute the single instruction
;;;   `cpuid`, and the CPU overwrites eax, ebx, ecx and edx with information.
;;;   Different leaves answer different questions:
;;;       leaf 0   the vendor string, in ebx:edx:ecx (try it -- see below)
;;;       leaf 1   edx[25]=SSE  edx[26]=SSE2  ecx[28]=AVX  ecx[12]=FMA
;;;       leaf 7   ebx[5]=AVX2  ebx[16]=AVX-512F   (ecx must be 0 first)
;;;   One bit per feature, packed into 32-bit words. This is how every program on
;;;   your machine -- your browser, your video player, glibc's own memcpy --
;;;   decides at run time which code path to use.
;;;
;;;   THE BIT-TESTING IDIOM is worth memorising, because it appears everywhere:
;;;       mov eax, [flags]
;;;       shr eax, 28          ; shift the bit you want down to position 0
;;;       and eax, 1           ; discard everything above it
;;;   Shift-then-mask. The alternative is `bt eax, 28` followed by `jc`, which
;;;   you met in onbit.asm in ps_code/2 -- that puts the answer in the carry flag
;;;   instead of a register. Both are correct; this one is easier when you want
;;;   the result as a VALUE rather than as a branch.
;;;
;;;   WHY THE WORDS ARE SAVED TO MEMORY FIRST: `cpuid` clobbers ALL FOUR of eax,
;;;   ebx, ecx and edx, so the second `cpuid` for leaf 7 would destroy leaf 1's
;;;   answers before you had finished testing them. Storing them to .bss is the
;;;   simple fix. (ebx is also callee-saved, so a function that used `cpuid`
;;;   without saving it would break the ABI -- worth noticing.)
;;;
;;;   THE ONE SUBTLETY THIS FILE GLOSSES OVER: `cpuid` telling you the CPU has
;;;   AVX is not quite the same as being ALLOWED to use it. The operating system
;;;   must also have enabled the wide register state, which you check with
;;;   ecx[27] (OSXSAVE) and then the `xgetbv` instruction. Production feature
;;;   detection does both. For this course, leaf 1 is enough.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/11/cpuid.asm"
;;;
;;;   Compare with what your Mac's own CPU reports -- they need not agree, since
;;;   the programs above run under emulation:
;;;   sysctl -a | grep -i "machdep.cpu.features" 2>/dev/null || sysctl -n machdep.cpu.brand_string
;;;
;;; DEBUG IT   -- the author's own session, adapted to this course's scripts
;;;   ./debug "ps_code/11/cpuid.asm"
;;;
;;;   THE session for this file -- read the raw feature words:
;;;     break dbg_cpuid           stops right AFTER the leaf-1 cpuid
;;;     c
;;;     info registers eax ebx ecx edx
;;;     p/t $edx                  EDX in BINARY -- count to bit 25 (SSE) and 26
;;;     p/t $ecx                  ECX in binary -- bit 28 (AVX), bit 12 (FMA)
;;;     p ($ecx >> 28) & 1        the AVX bit, extracted by hand
;;;     p ($ecx >> 12) & 1        the FMA bit
;;;     p ($edx >> 25) & 1        SSE
;;;
;;;   Try the vendor-string leaf, which this program does not use:
;;;     break main
;;;     c
;;;     # leaf 0 returns the twelve-character vendor id in ebx, edx, ecx
;;;     # ("GenuineIntel" or "AuthenticAMD"); under qemu you may see something
;;;     # else entirely, which is itself worth knowing
;;;
;;;   And watch cpuid clobber everything:
;;;     break cpuid.asm:NN        NN on the `cpuid` line for leaf 1
;;;     c
;;;     info registers eax ebx ecx edx    before
;;;     si
;;;     info registers eax ebx ecx edx    ALL FOUR have changed
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   NOTHING HAPPENS ON IT, and the contrast with the rest of the folder is the
;;;   point. `cpuid` is not a `call`: it is a single instruction that consults
;;;   the hardware and returns in the next cycle. Check it:
;;;       break cpuid.asm:NN      NN on the `cpuid` line
;;;       c
;;;       p $rsp
;;;       bt
;;;       si
;;;       p $rsp                  unchanged
;;;       bt                      unchanged
;;;   Compare `syscall` in code-0008.asm, which also does not touch your stack
;;;   but for a different reason -- it transfers to the KERNEL, which has its own
;;;   stack you cannot see. And compare `call printf`, which pushes 8 bytes.
;;;   Three ways of "going somewhere", three different costs:
;;;       cpuid     no transfer at all -- the CPU answers in place
;;;       syscall   transfer to the kernel; rip goes in rcx, flags in r11
;;;       call      transfer within your program; rip goes on YOUR stack
;;;
;;;   THE ABI POINT WORTH NOTICING is that `cpuid` clobbers ebx, and ebx is
;;;   CALLEE-SAVED. `main` gets away with it because nothing downstream depends
;;;   on ebx -- but a library function offering feature detection would have to
;;;   push rbx first and pop it afterwards. That is a real and slightly famous
;;;   nuisance: on 32-bit position-independent code ebx held the GOT pointer, and
;;;   the interaction with `cpuid` caused years of subtle bugs.
;;;
;;;   Finally, look at how `report` is written: it takes a string in rdi and a
;;;   flag in esi, chooses between two constant strings with a branch, and calls
;;;   printf. It builds a frame purely to align the stack -- `push rbp / mov rbp,
;;;   rsp / and rsp, -16` and the matching epilogue -- because the ABI requires
;;;   16-byte alignment at every `call` and `main` has already disturbed it.
;;;   Three instructions of overhead for a function whose real work is one call.
;;; ============================================================================

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
                                        ;   export `main` for the C library start-up
            global dbg_cpuid            ; exported so gdb can break by name
                                        ;   exported ONLY so gdb has a name to break on
            extern printf
                                        ;   the only external function needed

            section .bss
                                        ;   zero-filled at load time
edx1:       resd 1                      ; saved EDX from leaf 1 (SSE / SSE2)
                                        ;   `cpuid` CLOBBERS ALL FOUR of eax/ebx/ecx/edx, so leaf 1's
                                        ;   answers must be saved before leaf 7 is asked
ecx1:       resd 1                      ; saved ECX from leaf 1 (AVX / FMA)
ebx7:       resd 1                      ; saved EBX from leaf 7 (AVX2 / AVX-512F)

            section .rodata
                                        ;   READ-ONLY data: strings that are never written
hdr:        db "SIMD support (read straight from CPUID):", 10, 0
fmt:        db "  %-9s: %s", 10, 0
                                        ;   %-9s left-aligns the feature name; %s prints yes or no
yes:        db "yes", 0
no:         db "no", 0
n_sse:      db "sse", 0
n_sse2:     db "sse2", 0
n_avx:      db "avx", 0
n_fma:      db "fma", 0
n_avx2:     db "avx2", 0
n_avx512:   db "avx512f", 0

            section .text
                                        ;   the executable-code section
; report(rdi = name, esi = flag) : prints "  name : yes/no"
                                        ;   void report(const char *name, int flag)
report:     push    rbp
                                        ;   prologue: save the caller's frame pointer
            mov     rbp, rsp
                                        ;   anchor the frame
            and     rsp, -16
                                        ;   round rsp DOWN to a multiple of 16 -- required at every
                                        ;   `call`, and `main` has already disturbed the alignment
            lea     rdx, [rel no]
                                        ;   assume "no"...
            test    esi, esi
                                        ;   `test x, x` is the idiomatic zero test: an AND keeping
                                        ;   only the flags
            jz      .go
                                        ;   ...and if the flag is zero, keep that assumption
            lea     rdx, [rel yes]
                                        ;   otherwise point at "yes". A branch, rather than a
                                        ;   conditional move -- either would do.
.go:        mov     rsi, rdi
                                        ;   printf argument 2: the name. Moved FIRST, because rdi is
                                        ;   about to be overwritten.
            lea     rdi, [rel fmt]
                                        ;   printf argument 1: the format string
            xor     eax, eax            ; no vector args -> AL = 0
                                        ;   0 vector registers: this call passes no floats
            call    printf wrt ..plt
            mov     rsp, rbp
                                        ;   epilogue: restore rsp, undoing the alignment
            pop     rbp
                                        ;   restore the caller's frame pointer
            ret
                                        ;   pop the return address into rip

main:       push    rbp
                                        ;   int main(void). Prologue and alignment as usual.
            mov     rbp, rsp
            and     rsp, -16

            mov     eax, 1              ; leaf 1
                                        ;   select LEAF 1: the basic feature word
            cpuid                       ; -> EAX EBX ECX EDX (all clobbered)
                                        ;   ONE INSTRUCTION that consults the hardware and returns in
                                        ;   the next cycle. It is NOT a call: nothing is pushed and
                                        ;   rsp does not move. It overwrites all four of eax, ebx,
                                        ;   ecx and edx.
dbg_cpuid:                              ; <-- breakpoint: ECX/EDX hold the flags
                                        ;   a label at the SAME address, exported for gdb -- the
                                        ;   feature words are live at this point
            mov     [rel edx1], edx     ; SSE / SSE2
                                        ;   save EDX: bit 25 is SSE, bit 26 is SSE2
            mov     [rel ecx1], ecx     ; AVX / FMA
                                        ;   save ECX: bit 28 is AVX, bit 12 is FMA

            mov     eax, 7              ; leaf 7
                                        ;   select LEAF 7: the extended feature word
            xor     ecx, ecx            ; sub-leaf 0 (required)
                                        ;   sub-leaf 0. REQUIRED -- leaf 7 reads ecx as an input, and
                                        ;   junk there returns a different (or empty) answer.
            cpuid
                                        ;   ask again. (Note this clobbers ebx, which is CALLEE-SAVED
                                        ;   -- see the call-stack notes.)
            mov     [rel ebx7], ebx     ; AVX2 / AVX-512F
                                        ;   save EBX: bit 5 is AVX2, bit 16 is AVX-512F

            lea     rdi, [rel hdr]
                                        ;   the header line
            xor     eax, eax
            call    printf wrt ..plt

            mov     eax, [rel edx1]     ; sse = EDX[25]
                                        ;   THE BIT-TESTING IDIOM: load the word...
            shr     eax, 25
                                        ;   ...shift the bit you want down to position 0...
            and     eax, 1
                                        ;   ...and mask off everything above it. Now eax is 0 or 1.
                                        ;   (`bt eax, 25` + `jc` is the alternative -- see onbit.asm
                                        ;   in ps_code/2 -- which puts the answer in the carry flag.)
            mov     esi, eax
                                        ;   report's second argument: the flag
            lea     rdi, [rel n_sse]
                                        ;   ...and its first: the name
            call    report

            mov     eax, [rel edx1]     ; sse2 = EDX[26]
                                        ;   sse2 = EDX bit 26, the same idiom
            shr     eax, 26
            and     eax, 1
            mov     esi, eax
            lea     rdi, [rel n_sse2]
            call    report

            mov     eax, [rel ecx1]     ; avx = ECX[28]
                                        ;   avx = ECX bit 28
            shr     eax, 28
            and     eax, 1
            mov     esi, eax
            lea     rdi, [rel n_avx]
            call    report

            mov     eax, [rel ecx1]     ; fma = ECX[12]
                                        ;   fma = ECX bit 12
            shr     eax, 12
            and     eax, 1
            mov     esi, eax
            lea     rdi, [rel n_fma]
            call    report

            mov     eax, [rel ebx7]     ; avx2 = EBX[5]
                                        ;   avx2 = EBX bit 5, from leaf 7
            shr     eax, 5
            and     eax, 1
            mov     esi, eax
            lea     rdi, [rel n_avx2]
            call    report

            mov     eax, [rel ebx7]     ; avx512f = EBX[16]
                                        ;   avx512f = EBX bit 16
            shr     eax, 16
            and     eax, 1
            mov     esi, eax
            lea     rdi, [rel n_avx512]
            call    report

            xor     eax, eax
                                        ;   main's return value: 0 = success
            mov     rsp, rbp
                                        ;   epilogue: restore rsp, then the frame pointer
            pop     rbp
            ret
                                        ;   pop the return address into rip

section .note.GNU-stack noalloc noexec nowrite progbits
                                        ;   the "no executable stack" marker

