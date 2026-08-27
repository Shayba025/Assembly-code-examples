;;; ============================================================================
;;; loads.asm -- aligned versus unaligned vector loads, and why it matters
;;; Practice session 11                      (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Sums the same 4096-element array twice -- once with aligned loads, once
;;;   with unaligned ones -- gets the same answer, and then does one unaligned
;;;   load from a deliberately misaligned address to show that it works.
;;;   (Verified: both sums are 4096.0, and the misaligned load returns 1.0.)
;;;
;;;   THE RULE, from the author's header: `vmovaps` FAULTS unless the address is
;;;   32-byte aligned; `vmovups` works anywhere. On any CPU since about 2011 they
;;;   cost the same when the data IS aligned, so THE UNALIGNED FORM IS THE RIGHT
;;;   DEFAULT. The aligned form buys you nothing except a crash when you are
;;;   wrong about your data.
;;;
;;;   *** THE EXPERIMENT WORTH DOING IS THE ONE THE FILE DOES NOT DO. *** Change
;;;   the `vmovups ymm0, [rdi + 4]` near the end into `vmovaps` and rebuild:
;;;       ./asm "ps_code/11/loads.asm" ; echo "exit status = $?"
;;;   arr is 32-byte aligned, so arr+4 is not, and the program dies with SIGSEGV
;;;   (status 139). One letter, and the difference is a crash. Then change it
;;;   back. There is no better demonstration of what "alignment" means.
;;;
;;;   `align 32` IN .bss IS WHAT MAKES THE ALIGNED VERSION LEGAL. It pads until
;;;   the next address is a multiple of 32. Without it the `vmovaps` in
;;;   `sum_aligned` would fault on the very first iteration -- and note that
;;;   nothing in the instruction tells you whether the address is aligned. The
;;;   guarantee comes entirely from the data declaration.
;;;
;;;   THE HORIZONTAL FOLD at the end of each function is the standard reduction:
;;;       vextractf128 xmm1, ymm0, 1     8 lanes -> two halves
;;;       vaddps  xmm0, xmm0, xmm1       -> 4 partials
;;;       vhaddps xmm0, xmm0, xmm0       -> 2 partials
;;;       vhaddps xmm0, xmm0, xmm0       -> 1 answer, in lane 0
;;;   `vhaddps` (Horizontal ADD) is the one instruction in SIMD that deliberately
;;;   breaks the lane barrier: it adds ADJACENT PAIRS within a register rather
;;;   than corresponding lanes of two registers. It exists precisely for this
;;;   final collapse. dotprod.asm in this folder uses the identical sequence, and
;;;   code-0024.asm in "lectures code " does the same thing for integers with
;;;   `vpshufd` and `vpaddd` -- worth comparing all three.
;;;
;;;   `mov dword [rel onef], 0x3f800000` IS 1.0f, WRITTEN AS ITS BIT PATTERN.
;;;   There is no instruction to load a floating-point immediate into an xmm
;;;   register, so the value is assembled as an integer, stored to memory, and
;;;   loaded back with `movss`. Decode it if you like: sign 0, exponent 0x7F
;;;   (which is bias 127, so 2^0), mantissa 0 -- exactly 1.0. You will meet
;;;   0x40000000 (= 2.0f) in dotprod.asm for the same reason.
;;;
;;;   `vzeroupper` before returning: mixing 256-bit AVX with the 128-bit SSE the
;;;   C library uses inside printf costs a stall of tens of cycles per transition
;;;   unless the upper halves have been zeroed. Not optional in real code.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/11/loads.asm"
;;;
;;;   Then do the crash experiment described above -- it is the point of the file.
;;;
;;; DEBUG IT   -- the author's own session, adapted to this course's scripts
;;;   ./debug "ps_code/11/loads.asm"
;;;
;;;   Watch a vector load populate a register:
;;;     break dbg_aligned
;;;     c
;;;     p $ymm1.v8_float          stale contents, before the load
;;;     si                        the vmovaps
;;;     p $ymm1.v8_float          {1,1,1,1,1,1,1,1} -- eight floats at once
;;;     display $ymm0.v8_float    the running sum, sticky
;;;     c   c   c                 eight more elements per stop
;;;
;;;   Check the alignment claim with your own eyes:
;;;     p/x $rdi                  the array address
;;;     p $rdi % 32               0 -- which is why vmovaps is legal here
;;;     break dbg_misaligned
;;;     c
;;;     p ($rdi + 4) % 32         4 -- NOT aligned. vmovaps here would fault.
;;;     si
;;;     p $ymm0.v8_float          the unaligned load succeeded anyway
;;;
;;;   And watch the fold collapse 8 lanes into 1:
;;;     break loads.asm:NN        NN on the `vextractf128` line in al_done
;;;     c
;;;     p $ymm0.v8_float          eight partial sums
;;;     si si                     extract + add
;;;     p $xmm0.v4_float          four
;;;     si                        vhaddps
;;;     p $xmm0.v4_float          two distinct values
;;;     si                        vhaddps again
;;;     p $xmm0.v4_float[0]       4096 -- the answer
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE TWO SUMMING FUNCTIONS HAVE NO PROLOGUE AT ALL -- no `push rbp`, no
;;;   frame, no saved registers. They are LEAF FUNCTIONS: they call nothing, they
;;;   have no locals, and they use only caller-saved registers (rax and the ymm
;;;   registers). The only stack they touch is the 8-byte return address `call`
;;;   pushed. Confirm it:
;;;       break sum_aligned
;;;       c
;;;       p $rsp                  note it
;;;       finish
;;;       p $rsp                  8 higher. That is the entire cost of the call.
;;;
;;;   THAT IS NOT AN ACCIDENT, AND IT IS THE POINT WORTH TAKING AWAY. A
;;;   vectorised inner loop must not contain a `call`, because ALL SIXTEEN of
;;;   xmm0-xmm15 are CALLER-SAVED -- there is no such thing as a callee-saved
;;;   vector register on this platform. Put a `call printf` inside `al_loop` and
;;;   your accumulator ymm0 is destroyed on the first iteration, with no register
;;;   to move it to and no `push` that would take it (`push` does not accept a
;;;   vector operand; you would need `sub rsp, 32` and `vmovups [rsp], ymm0`).
;;;
;;;   So the shape of every fast vector routine in this course is the same:
;;;       compute everything in registers, with no calls at all
;;;       fold the lanes down to one value
;;;       and only THEN call printf
;;;   Compare packed.asm in this folder, whose `print_vec` must reload each lane
;;;   from memory on every iteration for exactly this reason, and code-0024.asm
;;;   in "lectures code ", which moves its answer into rsi before the call.
;;;
;;;   One last thing: `and rsp, -16` appears in `main` but in neither summing
;;;   function. That is correct -- alignment is a rule about `call`, and those
;;;   two functions make none.
;;; ============================================================================

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
                                        ;   export `main` for the C library start-up
            global dbg_aligned          ; breakpoint: the vmovaps load
                                        ;   exported ONLY so gdb has names to break on
            global dbg_misaligned       ; breakpoint: the misaligned vmovups
            extern printf
                                        ;   the only external function needed

            section .bss
                                        ;   zero-filled at load time, no file space
            align 32
                                        ;   THE LINE THAT MAKES `vmovaps` LEGAL: pad until the next
                                        ;   address is a multiple of 32. Nothing in the instruction
                                        ;   checks -- the guarantee comes from here.
N           equ 4096
                                        ;   `equ` = an assemble-time constant. A multiple of 8, so the
                                        ;   loops never run past the end.
arr:        resd N
                                        ;   `resd N` reserves N 32-bit slots
onef:       resd 1
                                        ;   one scratch slot, used to materialise the float 1.0

            section .rodata
                                        ;   READ-ONLY data: strings that are never written
hdr:        db "Summing 4096 aligned floats, two ways:", 10, 0
fmt:        db "  %-22s = %.1f", 10, 0
                                        ;   %-22s left-aligns a label; %.1f prints a DOUBLE
l_a:        db "vmovaps (aligned)", 0
l_u:        db "vmovups (unaligned)", 0
fmt2:       db 10, "  vmovups from misaligned arr+1 -> lane0 = %.1f", 10, 0
note:       db "  (a vmovaps at arr+1 would have faulted -- hence prefer unaligned)", 10, 0

            section .text
                                        ;   the executable-code section
; float sum_aligned(rdi=a, rsi=n)
                                        ;   float sum_aligned(const float *a, long n)
; (unique non-local labels so dbg_aligned does not split a local-label scope)
sum_aligned:    vxorps  ymm0, ymm0, ymm0
                                        ;   zero the accumulator, all eight lanes. XOR with itself is
                                        ;   the idiomatic clear. NOTE: no prologue -- this is a LEAF
                                        ;   function with no locals and no calls.
            xor     rax, rax
                                        ;   the element index
al_loop:    cmp     rax, rsi
                                        ;   non-local labels, deliberately: an exported `dbg_` label
                                        ;   in the middle would otherwise split the local-label scope
            jge     al_done
dbg_aligned:                            ; <-- break: about to ALIGNED-load 8 floats
                                        ;   a label at the SAME address, exported for gdb
            vmovaps ymm1, [rdi + rax*4]
                                        ;   ALIGNED load of eight floats. base + 4*index, with 4
                                        ;   because the elements are 32-bit. FAULTS if the address is
                                        ;   not a multiple of 32 -- see the header experiment.
            vaddps  ymm0, ymm0, ymm1
                                        ;   eight independent adds, one instruction
            add     rax, 8
                                        ;   eight elements consumed per iteration
            jmp     al_loop
al_done:    vextractf128 xmm1, ymm0, 1
                                        ;   THE HORIZONTAL FOLD: the upper 128 bits (lanes 4-7) into
                                        ;   an xmm register. xmm0 already IS the lower half.
            vaddps  xmm0, xmm0, xmm1
                                        ;   eight lanes folded into four
            vhaddps xmm0, xmm0, xmm0
                                        ;   Horizontal ADD: adds ADJACENT PAIRS *within* the register,
                                        ;   deliberately crossing the lane barrier. Four -> two.
            vhaddps xmm0, xmm0, xmm0
                                        ;   ...and again. Two -> one, in lane 0.
            vzeroupper
                                        ;   ZERO THE UPPER HALVES before returning to code that may
                                        ;   use 128-bit SSE. Skipping this costs tens of cycles per
                                        ;   transition on many CPUs.
            ret
                                        ;   pop the return address into rip. The answer is in xmm0,
                                        ;   where the ABI wants it.

; float sum_unaligned(rdi=a, rsi=n)
                                        ;   float sum_unaligned(const float *a, long n) -- IDENTICAL
                                        ;   except for one letter on the load
sum_unaligned:  vxorps  ymm0, ymm0, ymm0
            xor     rax, rax
.l:         cmp     rax, rsi
            jge     .r
            vmovups ymm1, [rdi + rax*4]
                                        ;   UNALIGNED load: works at ANY address, and on modern CPUs
                                        ;   costs the same as the aligned form when the data happens
                                        ;   to be aligned. Prefer this.
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
                                        ;   int main(void). Prologue and alignment as usual.
            mov     rbp, rsp
            and     rsp, -16

                                        ; fill arr[i] = 1.0f
            lea     rdi, [rel arr]
                                        ;   fill the array with 1.0f
            xor     rax, rax
            mov     dword [rel onef], 0x3f800000
                                        ;   1.0f, WRITTEN AS ITS BIT PATTERN. There is no instruction
                                        ;   to load a float immediate into an xmm register, so the
                                        ;   value goes through memory. Sign 0, exponent 0x7F (bias
                                        ;   127, i.e. 2^0), mantissa 0 = exactly 1.0.
            movss   xmm1, [rel onef]
                                        ;   ...and load it back as a float
.fill:      cmp     rax, N
            jge     .done
            movss   [rdi + rax*4], xmm1
                                        ;   store one element
            inc     rax
            jmp     .fill
.done:
            lea     rdi, [rel hdr]
            xor     eax, eax
            call    printf wrt ..plt

            lea     rdi, [rel arr]
                                        ;   sum with ALIGNED loads...
            mov     rsi, N
            call    sum_aligned
            cvtss2sd xmm0, xmm0
                                        ;   ...widen to double, because %f reads a DOUBLE
            lea     rdi, [rel fmt]
            lea     rsi, [rel l_a]
            mov     eax, 1
                                        ;   ONE vector register carries an argument
            call    printf wrt ..plt

            lea     rdi, [rel arr]
                                        ;   ...and again with UNALIGNED loads. Same answer.
            mov     rsi, N
            call    sum_unaligned
            cvtss2sd xmm0, xmm0
            lea     rdi, [rel fmt]
            lea     rsi, [rel l_u]
            mov     eax, 1
            call    printf wrt ..plt

            lea     rdi, [rel arr]
                                        ;   a label at the SAME address, exported for gdb
dbg_misaligned:                         ; <-- break: unaligned load from arr+1
            vmovups ymm0, [rdi + 4]     ; arr + 1 float : NOT 32-byte aligned
                                        ;   arr + 1 float : NOT 32-byte aligned. THIS SUCCEEDS.
                                        ;   Change `vmovups` to `vmovaps` here, rebuild, and the
                                        ;   program dies with SIGSEGV. One letter.
            vzeroupper
                                        ;   zero the upper halves before calling into the C library
            cvtss2sd xmm0, xmm0
                                        ;   widen lane 0 to double for printf
            lea     rdi, [rel fmt2]
            mov     eax, 1
            call    printf wrt ..plt

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

