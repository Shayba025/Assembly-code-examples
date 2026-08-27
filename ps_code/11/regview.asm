;;; ============================================================================
;;; regview.asm -- 256 bits are just 256 bits: the same register, many lenses
;;; Practice session 11                      (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Loads the four 64-bit integers 1, 2, 3, 4 into ymm0, and then prints those
;;;   same 256 bits three different ways: as four int64s, as eight int32s, and
;;;   as eight floats.
;;;   (Verified output:
;;;      v4_int64 = 1 2 3 4
;;;      v8_int32 = 1 0 2 0 3 0 4 0
;;;      v8_float = 1.401e-45 0.000e+00 2.803e-45 ... )
;;;
;;;   THE AUTHOR'S HEADER SAYS IT EXACTLY: nothing in the bits says what type
;;;   they are. Each view is a different LENS, like a C union, and NOTHING IS
;;;   CONVERTED. Reading the output is the exercise:
;;;
;;;   * v8_int32 gives {1, 0, 2, 0, 3, 0, 4, 0} because each 64-bit integer is
;;;     stored LITTLE-ENDIAN: the low four bytes hold the value and the high four
;;;     are zero. Splitting each int64 in half therefore produces the value
;;;     followed by a zero. THAT PATTERN IS ENDIANNESS, made visible.
;;;
;;;   * v8_float gives absurd tiny numbers -- 1.401e-45 is the smallest denormal
;;;     a 32-bit float can represent -- because the bit pattern 0x00000001 read
;;;     as an integer means 1 and read as a float means "the smallest nonzero
;;;     value there is". Same bits, wildly different meaning.
;;;
;;;   THAT IS THE POINT OF THE WHOLE FILE, and it generalises far beyond SIMD:
;;;   A REGISTER HAS NO TYPE. It has a width. The TYPE lives entirely in the
;;;   INSTRUCTION you choose to apply. `paddd` treats the bits as 32-bit
;;;   integers, `addps` as 32-bit floats, `addpd` as 64-bit doubles -- and every
;;;   one of them is legal on the same register with the same contents. Getting
;;;   the type wrong produces nonsense, not an error, which is exactly what the
;;;   float view above demonstrates.
;;;
;;;   YOU HAVE SEEN THIS BEFORE IN NARROWER FORM. numneg.asm in ps_code/3 shows
;;;   one 16-bit pattern read as signed and unsigned; invert.asm in ps_code/2
;;;   shows one 64-bit register viewed as rax, eax, ax and al. This file is the
;;;   same idea at 256 bits, and gdb's `info registers ymm0` prints ALL the
;;;   lenses at once, which makes it the clearest of the three.
;;;
;;;   `vmovdqu` is MOVe Double Quadword, Unaligned -- the INTEGER-flavoured
;;;   256-bit load. Its float counterparts are `vmovups`/`vmovaps`. On most CPUs
;;;   they move identical bits at identical speed, but keeping the domain
;;;   consistent with your data avoids a bypass-delay stall.
;;;
;;;   WHY THE VALUE IS COPIED TO `buf` BEFORE PRINTING: printf is scalar and
;;;   knows nothing about vector registers, so each lane has to be handed to it
;;;   one at a time from memory. The register is spilled once with `vmovdqu
;;;   [buf], ymm0` and then read back with three different element widths --
;;;   which is the same union trick, performed in RAM.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/11/regview.asm"
;;;
;;;   Change `A: dq 1, 2, 3, 4` to something with interesting high bits, e.g.
;;;   `dq 0x3FF0000000000000, 0, 0, 0`, and look at the views again -- that
;;;   pattern is 1.0 as a DOUBLE, and the int64 view will show
;;;   4607182418800017408.
;;;
;;; DEBUG IT   -- the author's own session, adapted to this course's scripts
;;;   ./debug "ps_code/11/regview.asm"
;;;
;;;   THE session for this file -- one register, six lenses:
;;;     break after_load
;;;     c
;;;     p $ymm0.v4_int64          {1, 2, 3, 4}          -- the stored view
;;;     p $ymm0.v8_int32          {1,0, 2,0, 3,0, 4,0}  -- endianness, visible
;;;     p $ymm0.v16_int16         sixteen lanes
;;;     p $ymm0.v32_int8          thirty-two bytes
;;;     p $ymm0.v8_float          tiny denormals -- same bits as float
;;;     p $ymm0.v4_double         and as doubles
;;;     info registers ymm0       EVERY view at once, which is the whole union
;;;
;;;   And prove the narrow register is a window onto the wide one:
;;;     p $xmm0.v2_int64          {1, 2} -- the LOW 128 bits only
;;;     set $xmm0.v2_int64[0] = 99
;;;     p $ymm0.v4_int64          {99, 2, 3, 4} -- the wide register changed too
;;;
;;;   See the same trick performed in memory rather than in a register:
;;;     x/4gd &buf                as four int64s
;;;     x/8dw &buf                as eight int32s
;;;     x/8fw &buf                as eight floats
;;;     x/32xb &buf               as raw bytes -- and there is the endianness
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE FOUR PRINT HELPERS ALL SHARE THE SAME PROLOGUE AND EPILOGUE, and it is
;;;   worth reading once carefully because it is the most complete example of the
;;;   ABI's register rules in the course:
;;;       push rbp / mov rbp, rsp        the frame
;;;       push r12 / push r13 / push rbx three CALLEE-SAVED registers
;;;       and rsp, -16                   alignment for printf
;;;       ...
;;;       lea rsp, [rbp-24]              land exactly on the last push
;;;       pop rbx / pop r13 / pop r12 / pop rbp
;;;
;;;   Why three callee-saved registers? Because each loop needs the array
;;;   pointer, the count and the index to survive `call printf`, and printf may
;;;   destroy every caller-saved register. Verify:
;;;       break printf
;;;       c
;;;       info registers rbx r12 r13
;;;       finish
;;;       info registers rbx r12 r13     unchanged
;;;
;;;   Why `lea rsp, [rbp-24]` and not `mov rsp, rbp`? Because `mov rsp, rbp`
;;;   would land ABOVE the three pushed registers and the three pops would then
;;;   retrieve rubbish. rbp-24 is exactly three eight-byte slots below the
;;;   anchor -- COUNT THE PUSHES AND THE NUMBER FOLLOWS. Check it:
;;;       break regview.asm:NN      NN on a `lea rsp, [rbp-24]` line
;;;       c
;;;       si
;;;       x/4gx $rsp                rbx, r13, r12, then the saved rbp
;;;
;;;   THE ASYMMETRY WORTH NOTICING: there is no callee-saved VECTOR register.
;;;   All sixteen of xmm0-xmm15 are caller-saved, so no equivalent trick exists
;;;   for floats -- which is exactly why `main` spills ymm0 to `buf` before doing
;;;   any printing at all. The vector value could not have survived the first
;;;   `call printf` in a register, and there is nowhere to push it to either
;;;   (`push` does not take a vector operand). Memory is the only option.
;;;
;;;   Finally, `vzeroupper` after the spill. Mixing 256-bit AVX with 128-bit
;;;   legacy SSE -- which the C library certainly uses inside printf -- costs a
;;;   stall of tens of cycles per transition unless the upper halves have been
;;;   zeroed. Issue it before returning from, or calling out of, any code that
;;;   touched ymm registers.
;;; ============================================================================

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
                                        ;   export `main` for the C library start-up
            global after_load           ; gdb breaks here (ymm0 already loaded)
                                        ;   exported ONLY so gdb has a name to break on, right after
                                        ;   the load
            extern printf
                                        ;   the only external function needed

            section .data
                                        ;   initialised, writable data
            align 32
                                        ;   pad to a 32-byte boundary, so the 256-bit load never
                                        ;   straddles two cache lines
A:          dq 1, 2, 3, 4
                                        ;   FOUR 64-bit integers = 256 bits exactly, which is one ymm
                                        ;   register. Stored LITTLE-ENDIAN, which is what makes the
                                        ;   int32 view come out as {1,0,2,0,3,0,4,0}.

            section .bss
                                        ;   zero-filled at load time
            align 32
buf:        resb 32
                                        ;   32 bytes -- somewhere to spill ymm0 so printf can read it
                                        ;   one lane at a time

            section .rodata
                                        ;   READ-ONLY data: strings that are never written
hdr:        db "ymm0 <- A: dq 1,2,3,4  -- the same 256 bits, many views:", 10, 0
L_i64:      db "  v4_int64 = ", 0
L_i32:      db "  v8_int32 = ", 0
L_f32:      db "  v8_float = ", 0
lblfmt:     db "%s", 0
f_i64:      db "%ld ", 0
                                        ;   %ld prints a 64-bit signed integer...
f_i32:      db "%d ", 0
                                        ;   ...%d a 32-bit one...
f_f32:      db "%.3e ", 0
                                        ;   ...and %.3e a DOUBLE in scientific notation
nl:         db 10, 0
note:       db 10, "int32 view {1,0,2,0,...}: each int64 = low half + zero high half.", 10
            db "float view reads the SAME bits -> tiny denormals. Nothing converted.", 10, 0

            section .text
                                        ;   the executable-code section
pr_i64:     push rbp
                                        ;   prologue: save the caller's frame pointer
            mov  rbp, rsp
                                        ;   anchor the frame
            push r12
                                        ;   r12, r13 and rbx are CALLEE-SAVED -- the only registers
                                        ;   that survive `call printf`, which is why the three loop
                                        ;   variables live there
            push r13
            push rbx
            and  rsp, -16
                                        ;   round rsp DOWN to a multiple of 16, for the printf calls
            mov  r12, rdi
                                        ;   park the array pointer out of rdi, which printf destroys
            mov  r13, rsi
                                        ;   ...and the element count
            xor  rbx, rbx
                                        ;   the index starts at 0
.l:         cmp  rbx, r13
                                        ;   a LOCAL label, so all the helpers can reuse the name
            jge  .d
            mov  rsi, [r12 + rbx*8]
                                        ;   load one element. base + 8*index -- 8 because the
                                        ;   lane width is 8 bytes
            lea  rdi, [rel f_i64]
            xor  eax, eax
            call printf wrt ..plt
            inc  rbx
                                        ;   next lane
            jmp  .l
                                        ;   round again
.d:         lea  rdi, [rel nl]
                                        ;   end the line
            xor  eax, eax
            call printf wrt ..plt
            lea  rsp, [rbp-24]
                                        ;   THE CLEVER LINE: rbp-24 lands exactly on the last thing
                                        ;   pushed -- three registers of eight bytes. `mov rsp, rbp`
                                        ;   would skip past them and the pops would get rubbish.
            pop  rbx
                                        ;   restore the three IN REVERSE ORDER to the pushes
            pop  r13
            pop  r12
            pop  rbp
                                        ;   pop the return address into rip
            ret

pr_i32:     push rbp
                                        ;   prologue: save the caller's frame pointer
            mov  rbp, rsp
                                        ;   anchor the frame
            push r12
                                        ;   r12, r13 and rbx are CALLEE-SAVED -- the only registers
                                        ;   that survive `call printf`, which is why the three loop
                                        ;   variables live there
            push r13
            push rbx
            and  rsp, -16
                                        ;   round rsp DOWN to a multiple of 16, for the printf calls
            mov  r12, rdi
                                        ;   park the array pointer out of rdi, which printf destroys
            mov  r13, rsi
                                        ;   ...and the element count
            xor  rbx, rbx
                                        ;   the index starts at 0
.l:         cmp  rbx, r13
                                        ;   a LOCAL label, so all the helpers can reuse the name
            jge  .d
            mov  esi, [r12 + rbx*4]
                                        ;   load one element. base + 4*index -- 4 because the
                                        ;   lane width is 4 bytes
            lea  rdi, [rel f_i32]
            xor  eax, eax
            call printf wrt ..plt
            inc  rbx
                                        ;   next lane
            jmp  .l
                                        ;   round again
.d:         lea  rdi, [rel nl]
                                        ;   end the line
            xor  eax, eax
            call printf wrt ..plt
            lea  rsp, [rbp-24]
                                        ;   THE CLEVER LINE: rbp-24 lands exactly on the last thing
                                        ;   pushed -- three registers of eight bytes. `mov rsp, rbp`
                                        ;   would skip past them and the pops would get rubbish.
            pop  rbx
                                        ;   restore the three IN REVERSE ORDER to the pushes
            pop  r13
            pop  r12
            pop  rbp
                                        ;   pop the return address into rip
            ret

pr_f32:     push rbp
                                        ;   prologue: save the caller's frame pointer
            mov  rbp, rsp
                                        ;   anchor the frame
            push r12
                                        ;   r12, r13 and rbx are CALLEE-SAVED -- the only registers
                                        ;   that survive `call printf`, which is why the three loop
                                        ;   variables live there
            push r13
            push rbx
            and  rsp, -16
                                        ;   round rsp DOWN to a multiple of 16, for the printf calls
            mov  r12, rdi
                                        ;   park the array pointer out of rdi, which printf destroys
            mov  r13, rsi
                                        ;   ...and the element count
            xor  rbx, rbx
                                        ;   the index starts at 0
.l:         cmp  rbx, r13
                                        ;   a LOCAL label, so all the helpers can reuse the name
            jge  .d
            movss xmm0, [r12 + rbx*4]
                                        ;   load one element. base + 4*index -- 4 because the
                                        ;   lane width is 4 bytes
            cvtss2sd xmm0, xmm0
                                        ;   widen to double: %f and %e read a DOUBLE, always
            lea  rdi, [rel f_f32]
            mov  eax, 1
            call printf wrt ..plt
                                        ;   next lane
            inc  rbx
                                        ;   round again
            jmp  .l
                                        ;   end the line
.d:         lea  rdi, [rel nl]
            xor  eax, eax
            call printf wrt ..plt
                                        ;   THE CLEVER LINE: rbp-24 lands exactly on the last thing
                                        ;   pushed -- three registers of eight bytes. `mov rsp, rbp`
                                        ;   would skip past them and the pops would get rubbish.
            lea  rsp, [rbp-24]
                                        ;   restore the three IN REVERSE ORDER to the pushes
            pop  rbx
            pop  r13
            pop  r12
                                        ;   pop the return address into rip
            pop  rbp
            ret

prlabel:    push rbp
                                        ;   void prlabel(const char *s) -- print a string with no
                                        ;   conversion of its own
            mov  rbp, rsp
            and  rsp, -16
            mov  rsi, rdi
                                        ;   printf argument 2: the label. Moved FIRST, because rdi is
                                        ;   about to be overwritten.
            lea  rdi, [rel lblfmt]
                                        ;   printf argument 1: just "%s"
            xor  eax, eax
                                        ;   0 vector registers
            call printf wrt ..plt
            mov  rsp, rbp
            pop  rbp
            ret

main:       push rbp
                                        ;   int main(void). Prologue and alignment as usual.
            mov  rbp, rsp
            and  rsp, -16

            vmovdqu ymm0, [rel A]       ; load the 256-bit pattern
                                        ;   load all 256 bits. `vmovdqu` = MOVe Double Quadword,
                                        ;   Unaligned -- the INTEGER-flavoured 256-bit load. Its
                                        ;   float twin is `vmovups`; on most CPUs they move identical
                                        ;   bits, but matching the domain to the data avoids a stall.
after_load:                             ; <-- gdb breakpoint target
                                        ;   a label at the SAME address, exported for gdb. THE
                                        ;   REGISTER IS LOADED AT THIS POINT -- break here and look
                                        ;   at it through every lens.
            vmovdqu [rel buf], ymm0     ; copy bytes out to print
                                        ;   SPILL the register to memory, because printf is scalar and
                                        ;   cannot read a vector register. The three helpers below
                                        ;   then read these same 32 bytes with three different
                                        ;   element widths -- the union trick, performed in RAM.
            vzeroupper
                                        ;   ZERO THE UPPER HALVES. Mixing 256-bit AVX with the
                                        ;   128-bit SSE the C library uses inside printf costs a stall
                                        ;   of tens of cycles per transition without this.

            lea  rdi, [rel hdr]
                                        ;   the header line
            xor  eax, eax
                                        ;   0 vector registers
            call printf wrt ..plt

            lea  rdi, [rel L_i64]
                                        ;   print the label, then...
            call prlabel
            lea  rdi, [rel buf]
                                        ;   ...the same 32 bytes as FOUR int64s
            mov  rsi, 4
            call pr_i64

            lea  rdi, [rel L_i32]
                                        ;   ...as EIGHT int32s -- note the count changes, not the data
            call prlabel
            lea  rdi, [rel buf]
            mov  rsi, 8
            call pr_i32

            lea  rdi, [rel L_f32]
                                        ;   ...and as EIGHT floats
            call prlabel
            lea  rdi, [rel buf]
            mov  rsi, 8
            call pr_f32

            lea  rdi, [rel note]
                                        ;   the closing explanation
            xor  eax, eax
            call printf wrt ..plt

            xor  eax, eax
                                        ;   main's return value: 0 = success
            mov  rsp, rbp
                                        ;   epilogue: restore rsp, then the frame pointer
            pop  rbp
            ret
                                        ;   pop the return address into rip

section .note.GNU-stack noalloc noexec nowrite progbits
                                        ;   the "no executable stack" marker

