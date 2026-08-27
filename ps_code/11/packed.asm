;;; ============================================================================
;;; packed.asm -- one instruction, every lane: the heart of SIMD
;;; Practice session 11                      (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Adds, subtracts and multiplies two four-element vectors with ONE
;;;   instruction each, then adds two eight-element vectors with one more.
;;;   (Verified: 4 lanes with addps/subps/mulps, then 8 lanes with vaddps.)
;;;
;;;   THE AUTHOR'S HEADER ABOVE STATES THE IDEA PERFECTLY. The notes here explain
;;;   the individual instructions and connect the file to the rest of the course.
;;;
;;;   READ scalar_sse.asm IN THIS FOLDER FIRST. It is the same arithmetic with
;;;   the `ss` (scalar) suffix, touching lane 0 only. The entire difference
;;;   between the two files is one letter:
;;;       addss xmm0, xmm1     lane 0 only          1 float
;;;       addps xmm0, xmm1     ALL FOUR lanes       4 floats, same cycle count
;;;       vaddps ymm0,ymm0,ymm1  ALL EIGHT lanes    8 floats, same cycle count
;;;   Nothing else changes -- not the registers, not the addressing, not the
;;;   cost. That is why SIMD is worth using: the wide form is free.
;;;
;;;   THE REGISTER FAMILY, since this file uses two of the three widths:
;;;       xmm0   128 bits    4 floats  (SSE, 1999)
;;;       ymm0   256 bits    8 floats  (AVX, 2011) -- xmm0 IS its lower half
;;;       zmm0   512 bits   16 floats  (AVX-512)
;;;   They are not separate registers; the narrow name is a window onto the wide
;;;   one. regview.asm in this folder makes that concrete.
;;;
;;;   TWO- VERSUS THREE-OPERAND FORMS. The old SSE encoding is destructive:
;;;       addps  xmm0, xmm1            ; xmm0 := xmm0 + xmm1, xmm0's old value gone
;;;   The AVX encoding (every instruction gaining a `v` prefix) adds a separate
;;;   destination:
;;;       vaddps ymm0, ymm0, ymm1      ; dst := src1 + src2
;;;   which means you can write `vaddps ymm2, ymm0, ymm1` and keep both inputs.
;;;   Fewer register copies, shorter code. Prefer the `v` forms in new code.
;;;
;;;   `vzeroupper` AT THE END OF add8_ps IS NOT DECORATION. Mixing 256-bit AVX
;;;   instructions with 128-bit legacy SSE ones leaves the CPU in a state where
;;;   the SSE instructions must preserve the upper halves of the ymm registers,
;;;   and on many microarchitectures that costs a stall of tens of cycles EVERY
;;;   TIME. `vzeroupper` zeroes the upper halves and clears the condition. THE
;;;   RULE: issue it before returning from any function that used ymm registers,
;;;   and before calling into code that might use SSE. Forgetting it is a classic
;;;   and completely invisible performance bug -- the program is correct and
;;;   mysteriously slow.
;;;
;;;   `movups` VERSUS `movaps`: the `u` is Unaligned. `movaps` would FAULT unless
;;;   the address is 16-byte aligned (32 for `vmovaps`). This file uses `align 32`
;;;   on its data so either would work, and still chooses the unaligned form --
;;;   which is the right default on any CPU since about 2011, where the aligned
;;;   version is no faster when the data happens to be aligned. loads.asm in this
;;;   folder measures exactly this.
;;;
;;;   NOTE THE IRONY IN THE CLOSING MESSAGE. "No loop ran outside the packed
;;;   instruction itself" is true of the ARITHMETIC -- but `print_vec` then loops
;;;   over the lanes one at a time to display them, calling printf per element.
;;;   The computation is vectorised; the printing cannot be, because printf is
;;;   scalar. That asymmetry is completely typical of real vector code.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/11/packed.asm"
;;;
;;;   Try changing `addps` to `addss` in add4_ps, rebuild, and run: only the
;;;   first lane changes and the other three keep b's values. That one-letter
;;;   diff is the clearest demonstration of the suffix there is.
;;;
;;; DEBUG IT   -- the author's own session, adapted to this course's scripts
;;;   ./debug "ps_code/11/packed.asm"
;;;
;;;   THE session for this file -- watch four lanes change in one step:
;;;     break dbg_addps
;;;     c
;;;     p $xmm0.v4_float          a = {1, 2, 3, 4}
;;;     p $xmm1.v4_float          b = {10, 20, 30, 40}
;;;     si                        ONE instruction
;;;     p $xmm0.v4_float          {11, 22, 33, 44} -- all four at once
;;;
;;;   Then eight lanes:
;;;     break dbg_vaddps
;;;     c
;;;     p $ymm0.v8_float          {1, 2, 3, 4, 5, 6, 7, 8}
;;;     p $ymm1.v8_float          {10, 20, ..., 80}
;;;     si
;;;     p $ymm0.v8_float          all eight sums, one instruction
;;;
;;;   Prove xmm0 really is the lower half of ymm0:
;;;     p $ymm0.v8_float          eight values
;;;     p $xmm0.v4_float          the first FOUR of exactly the same values
;;;     set $xmm0.v4_float[0] = 99
;;;     p $ymm0.v8_float          lane 0 of the WIDE register changed too
;;;
;;;   And see vzeroupper do its job:
;;;     break packed.asm:NN       NN on the `vzeroupper` line
;;;     c
;;;     p $ymm0.v8_float          eight live values
;;;     si
;;;     p $ymm0.v8_float          the upper four are now zero
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   LOOK AT THE PROLOGUE OF `print_vec`. It is the most elaborate one in the
;;;   whole course, and every line of it earns its place:
;;;       push rbp / mov rbp, rsp        the frame
;;;       push r12 / push r13 / push rbx three CALLEE-SAVED registers
;;;       and rsp, -16                   alignment for the printf calls
;;;   Why three callee-saved registers? Because the loop needs three values --
;;;   the array pointer, the count, and the index -- to survive `call printf`,
;;;   and printf will destroy any caller-saved register. r12, r13 and rbx are
;;;   the only kind that come back intact. Verify:
;;;       break printf
;;;       c   c
;;;       info registers rbx r12 r13
;;;       finish
;;;       info registers rbx r12 r13     unchanged, as promised
;;;
;;;   AND NOW LOOK AT THE EPILOGUE, which is the clever bit:
;;;       lea rsp, [rbp-24]
;;;       pop rbx / pop r13 / pop r12 / pop rbp
;;;   It cannot simply `mov rsp, rbp`, because that would skip past the three
;;;   pushed registers and pop rubbish. Instead it computes rsp = rbp - 24,
;;;   landing exactly on the last thing pushed, and then pops the three in
;;;   REVERSE ORDER before the frame pointer. Twenty-four is three registers of
;;;   eight bytes -- COUNT THE PUSHES AND THE NUMBER FOLLOWS. Get it wrong by one
;;;   slot and you return with the caller's registers swapped, which is a
;;;   spectacularly confusing bug. Watch the whole thing:
;;;       break packed.asm:NN       NN on the `lea rsp, [rbp-24]` line
;;;       c
;;;       p $rsp                    wherever the alignment left it
;;;       si
;;;       p $rsp                    exactly rbp-24
;;;       x/4gx $rsp                rbx, r13, r12, then the saved rbp
;;;
;;;   *** AND HERE IS THE POINT WORTH TAKING AWAY. *** There is no such thing as
;;;   a callee-saved VECTOR register: all sixteen of xmm0-xmm15 are caller-saved.
;;;   So the same trick is unavailable for floats -- which is exactly why
;;;   `print_vec` reloads each value from memory with `movss [r12 + rbx*4]` on
;;;   every iteration instead of keeping the vector in a register. It has no
;;;   choice. Compare dotprod.asm in this folder, whose vectorised inner loop
;;;   contains NO CALLS AT ALL, precisely so that its ymm accumulators can stay
;;;   in registers from beginning to end.
;;; ============================================================================

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
                                        ;   export `main` for the C library start-up
            global dbg_addps            ; breakpoint: the 4-lane addps
                                        ;   exported ONLY so gdb has a name to break on
            global dbg_vaddps           ; breakpoint: the 8-lane vaddps
                                        ;   ...and another, for the 8-lane version
            extern printf
                                        ;   the only external function needed

            section .data
                                        ;   initialised AND writable -- `res` is written to
            align 32
                                        ;   pad to a 32-byte boundary, so a 256-bit vector load never
                                        ;   straddles two cache lines
a8:         dd 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0
                                        ;   eight 32-bit floats. `dd` = define doubleword.
b8:         dd 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0
                                        ;   ...and eight more
res:        times 8 dd 0.0
                                        ;   `times 8 dd 0.0` repeats the directive eight times at
                                        ;   assembly time -- room for the results

            section .rodata
                                        ;   READ-ONLY data: strings that are never written
h_sse:      db "SSE: one instruction, 4 lanes (xmm, 128-bit)", 10, 0
h_avx:      db 10, "AVX: one instruction, 8 lanes (ymm, 256-bit)", 10, 0
l_a:        db "  a       :", 0
l_b:        db "  b       :", 0
l_add:      db "  addps   :", 0
l_sub:      db "  subps   :", 0
l_mul:      db "  mulps   :", 0
l_vadd:     db "  vaddps  :", 0
fmt_f:      db " %7.1f", 0
                                        ;   %7.1f prints a DOUBLE, right-aligned in seven columns
lblfmt:     db "%s", 0
                                        ;   just "%s" -- used to print a label with no conversion of
                                        ;   its own
nl:         db 10, 0
note:       db 10, "No loop ran outside the packed instruction itself.", 10, 0

            section .text
                                        ;   the executable-code section
; rdi=dst rsi=a rdx=b
add4_ps:    movups  xmm0, [rsi]
                                        ;   void add4_ps(float *dst, const float *a, const float *b)
            movups  xmm1, [rdx]
                                        ;   load FOUR floats. The `u` is Unaligned -- `movaps` would
                                        ;   fault on an address that is not 16-byte aligned.
dbg_addps:                              ; <-- break: xmm0=a, xmm1=b, before add
                                        ;   ...and four more
            addps   xmm0, xmm1          ; 4 parallel adds
                                        ;   a second label at the SAME address, exported for gdb
            movups  [rdi], xmm0
                                        ;   THE POINT OF THE FILE: four independent adds, one
                                        ;   instruction, one cycle. Lane i of xmm0 gets lane i of
                                        ;   xmm1 added to it. The lanes never interact -- which is
                                        ;   why a horizontal sum needs the fold in dotprod.asm.
            ret
                                        ;   store all four results back
sub4_ps:    movups  xmm0, [rsi]
                                        ;   pop the return address into rip
            movups  xmm1, [rdx]
            subps   xmm0, xmm1
                                        ;   identical shape, four parallel subtractions
            movups  [rdi], xmm0
            ret
mul4_ps:    movups  xmm0, [rsi]
            movups  xmm1, [rdx]
            mulps   xmm0, xmm1
                                        ;   ...and four parallel multiplications
            movups  [rdi], xmm0
            ret
add8_ps:    vmovups ymm0, [rsi]
                                        ;   the 256-bit version: EIGHT lanes
            vmovups ymm1, [rdx]
                                        ;   `vmovups` loads 32 bytes into a ymm register
dbg_vaddps:                             ; <-- break: ymm0=a, ymm1=b, before add
            vaddps  ymm0, ymm0, ymm1    ; 8 parallel adds
                                        ;   THREE-OPERAND form: dst, src1, src2. The AVX encoding is
                                        ;   non-destructive, so `vaddps ymm2, ymm0, ymm1` would keep
                                        ;   both inputs. Prefer this over the two-operand SSE form.
            vmovups [rdi], ymm0
                                        ;   store all eight results
            vzeroupper
                                        ;   ZERO THE UPPER HALVES of every ymm register. Not
                                        ;   decoration: mixing 256-bit AVX with 128-bit SSE without
                                        ;   this costs a stall of tens of cycles on many CPUs, every
                                        ;   time. Issue it before returning from any function that
                                        ;   used ymm registers. See the header.
            ret

; print_vec(rdi=label, rsi=ptr, rdx=count)
                                        ;   void print_vec(const char *label, const float *p, long n)
print_vec:  push    rbp
                                        ;   prologue: save the caller's frame pointer
            mov     rbp, rsp
                                        ;   anchor the frame
            push    r12
                                        ;   r12, r13 and rbx are CALLEE-SAVED -- the only registers
                                        ;   that survive `call printf`, which is why the three loop
                                        ;   variables live there
            push    r13
            push    rbx
            and     rsp, -16
                                        ;   round rsp DOWN to a multiple of 16, for the printf calls
            mov     r12, rsi
                                        ;   park the array pointer somewhere printf cannot reach
            mov     r13, rdx
                                        ;   ...and the count
            mov     rsi, rdi
                                        ;   printf argument 2: the label. Moved FIRST, because rdi is
                                        ;   about to be overwritten.
            lea     rdi, [rel lblfmt]
                                        ;   printf argument 1: just "%s"
            xor     eax, eax
                                        ;   0 vector registers for this call
            call    printf wrt ..plt
                                        ;   `wrt ..plt` routes the call through the Procedure Linkage
                                        ;   Table -- what position-independent code needs
            xor     rbx, rbx
                                        ;   the lane index starts at 0
.l:         cmp     rbx, r13
                                        ;   `.l` is LOCAL to print_vec
            jge     .done
            movss   xmm0, [r12 + rbx*4]
                                        ;   load ONE float from lane index rbx. base + 4*index, with
                                        ;   4 because the elements are 32-bit.
            cvtss2sd xmm0, xmm0
                                        ;   widen to double: %f reads a DOUBLE, always. A C compiler
                                        ;   inserts this conversion invisibly.
            lea     rdi, [rel fmt_f]
                                        ;   printf argument 1: " %7.1f"
            mov     eax, 1
                                        ;   ONE vector register carries an argument
            call    printf wrt ..plt
            inc     rbx
                                        ;   next lane
            jmp     .l
                                        ;   round again. NOTE: the printing is SCALAR -- one printf
                                        ;   per element -- even though the arithmetic was vectorised.
                                        ;   That asymmetry is typical of real vector code.
.done:      lea     rdi, [rel nl]
                                        ;   end the line
            xor     eax, eax
            call    printf wrt ..plt
            lea     rsp, [rbp-24]
                                        ;   THE EPILOGUE'S CLEVER LINE. It cannot use `mov rsp, rbp`,
                                        ;   because that would skip past the three pushed registers.
                                        ;   rbp-24 lands exactly on the last thing pushed -- 24 being
                                        ;   three registers of eight bytes. Count the pushes and the
                                        ;   number follows.
            pop     rbx
                                        ;   restore the three IN REVERSE ORDER to the pushes -- the
                                        ;   stack is last-in first-out
            pop     r13
            pop     r12
            pop     rbp
                                        ;   ...and finally the caller's frame pointer
            ret
                                        ;   pop the return address into rip

main:       push    rbp
                                        ;   int main(void). Prologue and alignment as usual.
            mov     rbp, rsp
            and     rsp, -16

            lea     rdi, [rel h_sse]
                                        ;   the SSE header
            xor     eax, eax
                                        ;   0 vector registers
            call    printf wrt ..plt

            lea     rdi, [rel l_a]
                                        ;   print a: label, pointer, count
            lea     rsi, [rel a8]
            mov     rdx, 4
            call    print_vec
            lea     rdi, [rel l_b]
                                        ;   ...and b
            lea     rsi, [rel b8]
            mov     rdx, 4
            call    print_vec

            lea     rdi, [rel res]
                                        ;   add4_ps(res, a8, b8)
            lea     rsi, [rel a8]
            lea     rdx, [rel b8]
            call    add4_ps
            lea     rdi, [rel l_add]
                                        ;   ...then display the result
            lea     rsi, [rel res]
            mov     rdx, 4
            call    print_vec

            lea     rdi, [rel res]
                                        ;   the same for subtraction...
            lea     rsi, [rel a8]
            lea     rdx, [rel b8]
            call    sub4_ps
            lea     rdi, [rel l_sub]
            lea     rsi, [rel res]
            mov     rdx, 4
            call    print_vec

            lea     rdi, [rel res]
                                        ;   ...and multiplication
            lea     rsi, [rel a8]
            lea     rdx, [rel b8]
            call    mul4_ps
            lea     rdi, [rel l_mul]
            lea     rsi, [rel res]
            mov     rdx, 4
            call    print_vec

            lea     rdi, [rel h_avx]
                                        ;   the AVX header
            xor     eax, eax
            call    printf wrt ..plt

            lea     rdi, [rel res]
                                        ;   add8_ps(res, a8, b8) -- EIGHT lanes this time
            lea     rsi, [rel a8]
            lea     rdx, [rel b8]
            call    add8_ps
            lea     rdi, [rel l_vadd]
                                        ;   ...and print all eight
            lea     rsi, [rel res]
            mov     rdx, 8
            call    print_vec

            lea     rdi, [rel note]
                                        ;   the closing note
            xor     eax, eax
            call    printf wrt ..plt

            xor     eax, eax
                                        ;   main's return value: 0 = success
            mov     rsp, rbp
                                        ;   epilogue: restore rsp, then the frame pointer
            pop     rbp
            ret
                                        ;   pop the return address into rip

section .note.GNU-stack noalloc noexec nowrite progbits
                                        ;   the "no executable stack" marker

