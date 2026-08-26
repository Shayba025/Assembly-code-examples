; regview.asm  --  load a known pattern into ymm0 and view it many ways.
; ===========================================================================
; THE BIG IDEA: a ymm register is just 256 bits. Nothing in the bits says what
; TYPE they are. The same bits can be read as
;     4 x int64   8 x int32   16 x int16   32 x byte   4 x double   8 x float
; Nothing is converted -- each is a different LENS, exactly like a C union.
;
; THE SETUP:
;     A: dq 1, 2, 3, 4        ; four 64-bit integers in memory
;     vmovdqu ymm0, [A]       ; load all 256 bits  (move-double-quad-unaligned)
;
; ---------------------------------------------------------------------------
; DEBUGGING -- read the SAME live register through many type "lenses"
;
;   nasm -f elf64 -g -F dwarf regview.asm -o regview.o
;   gcc -g -o regview regview.o
;   gdb -q ./regview
;     (gdb) break after_load       # right AFTER vmovdqu : ymm0 is loaded
;     (gdb) run
;     (gdb) print $ymm0.v4_int64   # {1, 2, 3, 4}            the stored view
;     (gdb) print $ymm0.v8_int32   # {1,0, 2,0, 3,0, 4,0}
;     (gdb) print $ymm0.v8_float   # tiny denormals: same bits as float
;     (gdb) print $xmm0.v2_int64   # {1, 2}  -- the low 128 bits only
;     (gdb) info registers ymm0    # every view at once (the whole union)
;     (gdb) display $ymm0.v4_int64 # sticky view
;     (gdb) continue
;   Or non-interactively:  make inspect            (regview is the default)
;                          make inspect PROG=regview
; ---------------------------------------------------------------------------
; Build:  nasm -f elf64 regview.asm -o regview.o && gcc regview.o -o regview
;   debug build:  nasm -f elf64 -g -F dwarf ... ; gcc -g ...   (see Makefile)
; ===========================================================================

            global main
            global after_load             ; gdb breaks here (ymm0 already loaded)
            extern printf

            section .data
            align 32
A:          dq 1, 2, 3, 4

            section .bss
            align 32
buf:        resb 32

            section .rodata
hdr:        db "ymm0 <- A: dq 1,2,3,4  -- the same 256 bits, many views:", 10, 0
L_i64:      db "  v4_int64 = ", 0
L_i32:      db "  v8_int32 = ", 0
L_f32:      db "  v8_float = ", 0
lblfmt:     db "%s", 0
f_i64:      db "%ld ", 0
f_i32:      db "%d ", 0
f_f32:      db "%.3e ", 0
nl:         db 10, 0
note:       db 10, "int32 view {1,0,2,0,...}: each int64 = low half + zero high half.", 10
            db "float view reads the SAME bits -> tiny denormals. Nothing converted.", 10, 0

            section .text
pr_i64:     push rbp
            mov  rbp, rsp
            push r12
            push r13
            push rbx
            and  rsp, -16
            mov  r12, rdi
            mov  r13, rsi
            xor  rbx, rbx
.l:         cmp  rbx, r13
            jge  .d
            mov  rsi, [r12 + rbx*8]
            lea  rdi, [rel f_i64]
            xor  eax, eax
            call printf wrt ..plt
            inc  rbx
            jmp  .l
.d:         lea  rdi, [rel nl]
            xor  eax, eax
            call printf wrt ..plt
            lea  rsp, [rbp-24]
            pop  rbx
            pop  r13
            pop  r12
            pop  rbp
            ret

pr_i32:     push rbp
            mov  rbp, rsp
            push r12
            push r13
            push rbx
            and  rsp, -16
            mov  r12, rdi
            mov  r13, rsi
            xor  rbx, rbx
.l:         cmp  rbx, r13
            jge  .d
            mov  esi, [r12 + rbx*4]
            lea  rdi, [rel f_i32]
            xor  eax, eax
            call printf wrt ..plt
            inc  rbx
            jmp  .l
.d:         lea  rdi, [rel nl]
            xor  eax, eax
            call printf wrt ..plt
            lea  rsp, [rbp-24]
            pop  rbx
            pop  r13
            pop  r12
            pop  rbp
            ret

pr_f32:     push rbp
            mov  rbp, rsp
            push r12
            push r13
            push rbx
            and  rsp, -16
            mov  r12, rdi
            mov  r13, rsi
            xor  rbx, rbx
.l:         cmp  rbx, r13
            jge  .d
            movss xmm0, [r12 + rbx*4]
            cvtss2sd xmm0, xmm0
            lea  rdi, [rel f_f32]
            mov  eax, 1
            call printf wrt ..plt
            inc  rbx
            jmp  .l
.d:         lea  rdi, [rel nl]
            xor  eax, eax
            call printf wrt ..plt
            lea  rsp, [rbp-24]
            pop  rbx
            pop  r13
            pop  r12
            pop  rbp
            ret

prlabel:    push rbp
            mov  rbp, rsp
            and  rsp, -16
            mov  rsi, rdi
            lea  rdi, [rel lblfmt]
            xor  eax, eax
            call printf wrt ..plt
            mov  rsp, rbp
            pop  rbp
            ret

main:       push rbp
            mov  rbp, rsp
            and  rsp, -16

            vmovdqu ymm0, [rel A]         ; load the 256-bit pattern
after_load:                               ; <-- gdb breakpoint target
            vmovdqu [rel buf], ymm0       ; copy bytes out to print
            vzeroupper

            lea  rdi, [rel hdr]
            xor  eax, eax
            call printf wrt ..plt

            lea  rdi, [rel L_i64]
            call prlabel
            lea  rdi, [rel buf]
            mov  rsi, 4
            call pr_i64

            lea  rdi, [rel L_i32]
            call prlabel
            lea  rdi, [rel buf]
            mov  rsi, 8
            call pr_i32

            lea  rdi, [rel L_f32]
            call prlabel
            lea  rdi, [rel buf]
            mov  rsi, 8
            call pr_f32

            lea  rdi, [rel note]
            xor  eax, eax
            call printf wrt ..plt

            xor  eax, eax
            mov  rsp, rbp
            pop  rbp
            ret

section .note.GNU-stack noalloc noexec nowrite progbits
