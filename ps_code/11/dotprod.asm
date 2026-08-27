;;; ============================================================================
;;; dotprod.asm -- vertical FMA, then a cross-lane fold
;;; Practice session 11                      (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Computes the dot product of two 4096-element float vectors twice: once
;;;   with AVX and FMA eight lanes at a time, once scalar, and prints both so you
;;;   can see they agree.
;;;   (Verified: both give 32762.0.)
;;;
;;;   THE AUTHOR'S HEADER SPLITS IT INTO TWO PHASES, AND THAT IS THE RIGHT WAY
;;;   TO THINK ABOUT EVERY REDUCTION YOU WILL EVER VECTORISE:
;;;
;;;     PHASE 1 -- VERTICAL, and easy. Lane i of the accumulator only ever talks
;;;       to lane i of the inputs. One `vfmadd231ps` does eight multiply-adds.
;;;       This phase is where all the time goes, and it is embarrassingly
;;;       parallel.
;;;
;;;     PHASE 2 -- HORIZONTAL, and awkward. You need ONE number, but the answer
;;;       is spread across eight lanes, and SIMD hardware is deliberately bad at
;;;       moving data between lanes. So you do it ONCE, at the very end, with a
;;;       fold: 8 -> 4 -> 2 -> 1.
;;;
;;;   Getting that division right is the whole skill. A beginner writes the
;;;   horizontal add inside the loop and wonders why the vector version is slower
;;;   than the scalar one.
;;;
;;;   `vfmadd231ps ymm0, ymm1, ymm2` IS FUSED MULTIPLY-ADD:
;;;       ymm0 := ymm1 * ymm2 + ymm0,  eight lanes at once
;;;   Decode the "231": operands 2 and 3 are multiplied, operand 1 is the addend
;;;   AND the destination. There are also 132 and 213 variants for when the value
;;;   you want to keep is somewhere else. FUSED means it rounds ONCE rather than
;;;   twice, so it is strictly more accurate than a separate `vmulps` and
;;;   `vaddps` -- and it is one instruction instead of two. This is the
;;;   instruction that makes matrix multiplication fast on every modern CPU.
;;;   code-0025.asm in "lectures code " uses the double-precision form.
;;;
;;;   `vhaddps` (Horizontal ADD Packed Single) is the fold's workhorse. Unlike
;;;   every other packed instruction, it adds ADJACENT PAIRS WITHIN a register
;;;   rather than corresponding lanes of two registers. It exists solely for this
;;;   final collapse. Compare code-0024.asm, which achieves the same thing for
;;;   integers using `vpshufd` to swap lanes and then an ordinary `vpaddd` --
;;;   three different spellings of one idea, all in this course.
;;;
;;;   THE SCALAR REFERENCE IS THE POINT OF THE SECOND FUNCTION. Never trust a
;;;   vectorised routine without one: it is the only way to know your fold is
;;;   right. Note that the two answers agree EXACTLY here, which will not always
;;;   be true -- floating-point addition is not associative, so summing in a
;;;   different order can change the last bits.
;;;
;;;   `mov dword [rsi + r10*4], 0x40000000` IS 2.0f, WRITTEN AS ITS BIT PATTERN,
;;;   for the same reason loads.asm writes 0x3f800000 for 1.0f: there is no
;;;   instruction to load a floating-point immediate into a register.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/11/dotprod.asm"
;;;
;;;   Check the arithmetic: a[i] = (i mod 7) + 1 and b[i] = 2, so the answer is
;;;   2 * sum of (i mod 7 + 1) over 4096 elements:
;;;   python3 -c "print(sum(((i%7)+1)*2 for i in range(4096)))"
;;;
;;; DEBUG IT   -- the author's own session, adapted to this course's scripts
;;;   ./debug "ps_code/11/dotprod.asm"
;;;
;;;   Watch eight partial sums accumulate:
;;;     break dbg_dot_acc
;;;     c
;;;     display $ymm0.v8_float    the eight running partials
;;;     p $ymm1.v8_float          eight elements of a
;;;     p $ymm2.v8_float          eight elements of b
;;;     si                        ONE fma folds in eight products
;;;     c                         next eight elements
;;;
;;;   Then watch them collapse to one:
;;;     break dbg_dot_fold
;;;     c
;;;     p $ymm0.v8_float          eight partials, all different
;;;     si                        vextractf128
;;;     p $xmm1.v4_float          the upper four
;;;     si                        vaddps      -> 4
;;;     p $xmm0.v4_float
;;;     si                        vhaddps     -> 2
;;;     p $xmm0.v4_float
;;;     si                        vhaddps     -> 1
;;;     p $xmm0.v4_float[0]       32762 -- the answer, in lane 0
;;;
;;;   And compare the two implementations directly:
;;;     break dot_scalar
;;;     c
;;;     finish
;;;     p $xmm0.v4_float[0]       the reference answer
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   NEITHER `dot_avx` NOR `dot_scalar` HAS A PROLOGUE. No `push rbp`, no frame,
;;;   no saved registers -- they are LEAF FUNCTIONS that call nothing, have no
;;;   locals, and use only caller-saved registers. The only stack either touches
;;;   is the 8-byte return address. Measure it:
;;;       break dot_avx
;;;       c
;;;       p $rsp
;;;       finish
;;;       p $rsp                  8 higher, and nothing else changed
;;;
;;;   *** AND THE INNER LOOP CONTAINS NO CALL AT ALL, WHICH IS NOT NEGOTIABLE. ***
;;;   All sixteen of xmm0-xmm15 are CALLER-SAVED: there is no such thing as a
;;;   callee-saved vector register on this platform. Put a `call` inside
;;;   `dot_loop` and ymm0 -- the accumulator holding all eight partial sums -- is
;;;   destroyed on the first iteration. Worse, there is no cheap way to protect
;;;   it: `push` does not accept a vector operand, so you would need
;;;   `sub rsp, 32` and `vmovups [rsp], ymm0` around every call, at which point
;;;   the vectorisation has bought you nothing.
;;;
;;;   THAT CONSTRAINT SHAPES EVERY FAST VECTOR ROUTINE YOU WILL EVER WRITE:
;;;       keep the hot loop free of calls, so the accumulators stay in registers
;;;       fold the lanes down once, at the end
;;;       and only then talk to the outside world
;;;   Look back through the course and you will see it everywhere: code-0024.asm
;;;   and code-0025.asm both compute entirely in registers and call printf once,
;;;   afterwards; packed.asm's `print_vec` reloads from memory on every iteration
;;;   precisely because it cannot do otherwise.
;;;
;;;   The contrast with the INTEGER world is worth holding onto. There you have
;;;   rbx and r12-r15 to park values in across a call -- which is exactly what
;;;   multboard.asm in ps_code/6 and newton_raphson.asm in ps_code/9 do. In the
;;;   floating-point world that option simply does not exist.
;;; ============================================================================

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
                                                     ;   export `main` for the C library start-up
            global dbg_dot_acc                       ; breakpoint: the accumulating FMA
                                                     ;   exported ONLY so gdb has names to break on
            global dbg_dot_fold                      ; breakpoint: start of the fold
            extern printf
                                                     ;   the only external function needed

            section .bss
                                                     ;   zero-filled at load time, no file space
            align 32
                                                     ;   pad to a 32-byte boundary, so a 256-bit load never
                                                     ;   straddles two cache lines
N           equ 4096
                                                     ;   `equ` = an assemble-time constant. A multiple of 8, so the
                                                     ;   vector loop never runs past the end -- real code needs a
                                                     ;   scalar tail loop when it is not.
a:          resd N
                                                     ;   `resd N` reserves N 32-bit float slots
b:          resd N

            section .rodata
                                                     ;   READ-ONLY data: strings that are never written
hdr:        db "Dot product of two length-4096 vectors:", 10, 0
fmt:        db "  %-26s = %.1f", 10, 0
                                                     ;   %-26s left-aligns a label; %.1f prints a DOUBLE
l_simd:     db "AVX+FMA (8 lanes + fold)", 0
l_ref:      db "scalar reference", 0
note:       db 10, "Inner loop: one vfmadd231ps per 8 elements; lanes folded once.", 10, 0

            section .text
                                                     ;   the executable-code section
; float dot_avx(rdi=a, rsi=b, rdx=n)  -- n multiple of 8
                                                     ;   float dot_avx(const float *a, const float *b, long n)
; (unique non-local labels: the exported dbg_ labels must not split a local scope)
dot_avx:    vxorps  ymm0, ymm0, ymm0                 ; acc = 0 (8 lanes)
                                                     ;   acc = 0 in all eight lanes. NOTE: no prologue -- a LEAF
                                                     ;   function with no locals and no calls.
            xor     rax, rax
                                                     ;   the element index
dot_loop:   cmp     rax, rdx
                                                     ;   non-local labels, deliberately: an exported `dbg_` label
                                                     ;   in the middle would split the local-label scope
            jge     dot_reduce
            vmovups ymm1, [rdi + rax*4]
                                                     ;   eight floats of a. base + 4*index, with 4 because the
                                                     ;   elements are 32-bit.
            vmovups ymm2, [rsi + rax*4]
                                                     ;   ...and eight of b
dbg_dot_acc:                                         ; <-- break: acc, a, b before the FMA
                                                     ;   a label at the SAME address, exported for gdb
            vfmadd231ps ymm0, ymm1, ymm2             ; acc += a*b (8 lanes)
                                                     ;   PHASE 1, VERTICAL: acc[i] += a[i]*b[i], for all eight
                                                     ;   lanes, in ONE instruction. "231" names the operand roles:
                                                     ;   2 and 3 are multiplied, 1 is the addend and destination.
                                                     ;   FUSED means one rounding instead of two -- strictly more
                                                     ;   accurate than a separate multiply and add.
            add     rax, 8
                                                     ;   eight elements consumed per iteration
            jmp     dot_loop
dot_reduce:
                                                     ;   PHASE 2 begins: eight partial sums, and we need one number
dbg_dot_fold:                                        ; <-- break: 8 partials, about to fold
                                                     ;   a label at the SAME address, exported for gdb
            vextractf128 xmm1, ymm0, 1               ; lanes 4..7
                                                     ;   the upper 128 bits (lanes 4-7) into an xmm register.
                                                     ;   xmm0 already IS the lower half of ymm0.
            vaddps  xmm0, xmm0, xmm1                 ; -> 4 partials
                                                     ;   eight lanes folded into four
            vhaddps xmm0, xmm0, xmm0                 ; -> 2
                                                     ;   Horizontal ADD: adds ADJACENT PAIRS *within* the register.
                                                     ;   The one instruction that deliberately crosses the lane
                                                     ;   barrier -- which is why it belongs here and nowhere else.
                                                     ;   Four -> two.
            vhaddps xmm0, xmm0, xmm0                 ; -> 1 (lane 0)
                                                     ;   ...and again. Two -> one, in lane 0.
            vzeroupper
                                                     ;   ZERO THE UPPER HALVES before returning to code that may
                                                     ;   use 128-bit SSE
            ret
                                                     ;   pop the return address into rip. The answer is in xmm0.

; float dot_scalar(rdi=a, rsi=b, rdx=n)
                                                     ;   float dot_scalar(...) -- the REFERENCE implementation.
                                                     ;   Never trust a vectorised routine without one: it is the
                                                     ;   only way to know the fold is right.
dot_scalar: vxorps  xmm0, xmm0, xmm0
                                                     ;   acc = 0, lane 0 only
            xor     rax, rax
.l:         cmp     rax, rdx
            jge     .d
            movss   xmm1, [rdi + rax*4]
                                                     ;   one element of a...
            mulss   xmm1, [rsi + rax*4]
                                                     ;   ...times one element of b...
            addss   xmm0, xmm1
                                                     ;   ...added to the running total. Three instructions per
                                                     ;   element, against one per eight in the vector version.
            inc     rax
                                                     ;   one element per iteration
            jmp     .l
.d:         ret
                                                     ;   no fold needed: the answer was never spread across lanes

main:       push    rbp
                                                     ;   int main(void). Prologue and alignment as usual.
            mov     rbp, rsp
            and     rsp, -16

                                                     ; fill a[i] = (i % 7) + 1,  b[i] = 2.0
                                                     ;   fill a[i] = (i mod 7) + 1 and b[i] = 2.0
            lea     rdi, [rel a]
            lea     rsi, [rel b]
            xor     r10, r10
            mov     ecx, 7
                                                     ;   the divisor for the modulo
.fill:      cmp     r10, N
            jge     .filled
            mov     rax, r10
            xor     rdx, rdx
                                                     ;   `div` always divides RDX:RAX...
            div     rcx
                                                     ;   ...and rdx MUST be cleared first, or you get a wrong
                                                     ;   answer or a divide-error exception
            lea     eax, [rdx + 1]
                                                     ;   rax := i/7, rdx := i mod 7
            cvtsi2ss xmm0, eax
                                                     ;   `lea` as arithmetic: eax := (i mod 7) + 1, with no memory
                                                     ;   access at all
            movss   [rdi + r10*4], xmm0
                                                     ;   ConVerT Signed Integer to Scalar Single -- integers and
                                                     ;   floats have completely different bit layouts, so this is
                                                     ;   real work, not a move
            mov     dword [rsi + r10*4], 0x40000000  ; 2.0f
                                                     ;   store one element of a
            inc     r10
                                                     ;   2.0f, WRITTEN AS ITS BIT PATTERN, because there is no
                                                     ;   instruction to load a float immediate into a register
            jmp     .fill
.filled:
            lea     rdi, [rel hdr]
                                                     ;   the header line
            xor     eax, eax
            call    printf wrt ..plt

            lea     rdi, [rel a]
                                                     ;   the vectorised dot product...
            lea     rsi, [rel b]
            mov     rdx, N
            call    dot_avx
            cvtss2sd xmm0, xmm0
                                                     ;   ...widened to double, because %f reads a DOUBLE
            lea     rdi, [rel fmt]
            lea     rsi, [rel l_simd]
            mov     eax, 1
                                                     ;   ONE vector register carries an argument
            call    printf wrt ..plt

            lea     rdi, [rel a]
                                                     ;   ...and the scalar reference, for comparison
            lea     rsi, [rel b]
            mov     rdx, N
            call    dot_scalar
            cvtss2sd xmm0, xmm0
            lea     rdi, [rel fmt]
            lea     rsi, [rel l_ref]
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

