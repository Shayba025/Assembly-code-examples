;;; ============================================================================
;;; code-0025.asm -- Dot product of two 64-element double vectors, using AVX+FMA
;;; (the original header calls this file dot-product-f64.asm)
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   The same dot product as code-0024, but on 64-bit DOUBLES instead of 32-bit
;;;   integers. Read the two files side by side -- the shape is identical and
;;;   every difference is instructive:
;;;
;;;       code-0024 (int32)              code-0025 (double)
;;;       ---------------------------    ---------------------------
;;;       8 lanes per ymm, 8 iterations  4 lanes per ymm, 16 iterations
;;;       vpxor      (integer zero)      vxorpd     (double zero)
;;;       vmovdqu    (integer load)      vmovupd    (double load)
;;;       vpmulld + vpaddd  (2 insns)    vfmadd231pd       (ONE insn)
;;;       vpaddd     (integer add)       vaddpd     (double add)
;;;       result in eax, rax = 0         result in xmm0, rax = 1
;;;
;;;   FOUR THINGS TO TAKE AWAY:
;;;
;;;   1. LANE COUNT IS SET BY ELEMENT SIZE. 256 bits / 64 bits = four doubles per
;;;      ymm register, so 64 elements need 16 iterations, not 8. Halving the
;;;      precision doubles the throughput -- which is the entire reason people
;;;      train neural networks in 16-bit floats.
;;;
;;;   2. INTEGER AND FLOATING-POINT INSTRUCTIONS ARE SEPARATE, even when they
;;;      would do the same bits. `vxorpd` and `vpxor` both zero a register, and
;;;      you should still use the one that matches your data type: mixing
;;;      "domains" costs a stall on real hardware. The suffix tells you which:
;;;      `pd` = Packed Double, `ps` = Packed Single, `sd`/`ss` = Scalar.
;;;
;;;   3. FMA -- FUSED MULTIPLY-ADD -- IS THE STAR OF THIS FILE.
;;;          vfmadd231pd ymm0, ymm1, ymm2      ; ymm0 := ymm1*ymm2 + ymm0
;;;      One instruction replaces the multiply and the add, and -- more
;;;      importantly -- it rounds ONCE instead of twice, so it is strictly more
;;;      accurate than doing the two operations separately. Decode the "231":
;;;      the digits name which operands are multiplied and which is added, in
;;;      order -- operands 2 and 3 are multiplied, operand 1 is the addend and
;;;      the destination. (There are also 132 and 213 variants for when the
;;;      value you want to keep is somewhere else.) This is the instruction that
;;;      makes matrix multiplication fast on every modern CPU.
;;;
;;;   4. RETURNING A DOUBLE TO printf. Doubles travel in XMM REGISTERS, and the
;;;      first one goes in xmm0 -- which is where the answer already is. So there
;;;      is no move at all; the only thing that changes is `mov rax, 1`, telling
;;;      the variadic convention that ONE vector register carries an argument.
;;;      Get that count wrong and printf reads garbage.
;;;
;;;   THE HORIZONTAL REDUCTION at the end is the same fold-in-half idea as
;;;   code-0024, but with only four lanes it takes two steps instead of three:
;;;       4 lanes:  [ a b | c d ]
;;;         vextractf128 xmm1, ymm0, 1   -> xmm1 = [ c d ]
;;;         vaddpd  xmm0, xmm0, xmm1     -> [ a+c  b+d ]         (2 lanes)
;;;         unpckhpd xmm1, xmm1          -> broadcast the HIGH lane
;;;         addsd   xmm0, xmm1           -> scalar add: the total, in lane 0
;;;   The professor left both spellings of the third step in the source: a single
;;;   `movhlps` (move the high half to the low half) or the `movapd` +
;;;   `unpckhpd` pair. They do the same job here; `movhlps` is an SSE1
;;;   instruction operating on floats and is one instruction shorter.
;;;
;;;   A DEAD INSTRUCTION TO NOTICE: `mov rsi, rax` just before the call is left
;;;   over from the integer version. rsi is not used by a `%f` conversion at all
;;;   -- the value is in xmm0. Harmless, and a good example of the kind of line
;;;   that survives a copy-paste and confuses the next reader.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0025.asm"    # The dot product is 198188.457200
;;;
;;;   Confirm the FMA really is more accurate -- change `vfmadd231pd` to the
;;;   two-instruction form and compare the last digits:
;;;       vmulpd ymm3, ymm1, ymm2
;;;       vaddpd ymm0, ymm0, ymm3
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0025.asm"
;;;
;;;   Useful session -- print vectors as doubles, not integers:
;;;     break code-0025.asm:NN     put NN on the `vfmadd231pd` line
;;;     c
;;;     p $ymm1.v4_double          four elements of A
;;;     p $ymm2.v4_double          the matching four of B
;;;     p $ymm0.v4_double          the four running partial sums
;;;     si
;;;     p $ymm0.v4_double          each lane grew by its own product
;;;     c                          next block of four
;;;
;;;   Watch the reduction:
;;;     break code-0025.asm:NN     NN on `vextractf128`
;;;     c
;;;     p $ymm0.v4_double          four partial sums
;;;     si si                      extract + add
;;;     p $xmm0.v2_double          two
;;;     si si si                   movapd, unpckhpd, addsd
;;;     p $xmm0.v2_double          lane 0 is the answer
;;;
;;;   And check the calling convention right before printf:
;;;     break printf
;;;     c
;;;     p $xmm0.v2_double[0]       198188.4572 -- argument 1, in a vector register
;;;     p $rax                     1 -- "one vector register carries an argument"
;;;     x/s $rdi                   the format string
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   As in code-0024, the stack is nearly idle: two frames in `bt`, no locals,
;;;   no pushes, rsp constant after the prologue. The vector registers are the
;;;   working storage.
;;;
;;;   BUT THIS FILE HAS THE BETTER LESSON ABOUT THE CALLING CONVENTION, because
;;;   the answer is passed in a CALLER-SAVED VECTOR REGISTER and must survive
;;;   until printf reads it. Look at what that implies:
;;;       break printf
;;;       c
;;;       p $xmm0.v2_double[0]     the answer, still intact -- printf has not run
;;;       finish
;;;       p $xmm0.v2_double[0]     now it is whatever printf left behind
;;;   xmm0 is simultaneously "where my result lives" and "a register the callee
;;;   may destroy". It works only because nothing happens between computing it
;;;   and calling. Insert any other `call` in between and the value is gone --
;;;   and there is no push/pop idiom for it either, because `push` does not take
;;;   an xmm register. You would have to `sub rsp, 16` and `movapd [rsp], xmm0`
;;;   by hand. Try adding a stray `call printf` before the real one and watch
;;;   the number turn to rubbish.
;;;
;;;   THAT is the general rule this pair of files is teaching: caller-saved means
;;;   "valid only until the next call", and the wider the register, the more
;;;   awkward saving it becomes. The System V ABI makes every one of xmm0-xmm15
;;;   caller-saved, which is why vectorised inner loops are almost always written
;;;   with NO function calls inside them at all -- exactly as here.
;;;
;;;   One alignment note that matters more in vector code: `and rsp, -16` before
;;;   the call is not optional politeness. The C library's own SIMD routines use
;;;   ALIGNED accesses on stack memory, and a misaligned stack makes them fault
;;;   rather than merely run slowly. Check `p $rsp % 16` at the breakpoint on
;;;   printf: it must be 8, because `call` pushed 8 bytes onto a 16-aligned stack.
;;; ============================================================================

section .data                           ; initialised, writable data
fmt_dot_product:
        db `The dot product is %f\n\0`  ; %f prints a double. The VALUE will arrive
                                        ;   in xmm0, not in an integer register.
align 64                                ; pad to a 64-byte (cache-line) boundary, so
                                        ;   a 32-byte vector load never straddles two
                                        ;   cache lines
A:
        dq 58.31, 58.27, 84.72, 44.64, 50.70, 62.36, 46.86, 78.24
        dq 91.10, 95.37, 89.10, 96.47, 39.68, 22.91, 60.69, 77.88
        dq 23.58, 40.96, 58.31, 11.26, 18.24, 91.79, 63.92, 73.12
        dq 28.26, 29.76, 62.17, 98.93, 38.16, 33.87, 80.68, 23.68
        dq 22.37, 54.64, 81.46, 11.13, 78.57, 41.89, 83.30, 97.28
        dq 77.21, 85.38, 80.78, 46.94, 45.31, 51.45, 39.19, 12.60
        dq 56.80, 75.85, 17.56, 21.66, 23.57, 61.59, 21.29, 89.68
        dq 97.39, 64.10, 13.10, 77.91, 74.66, 77.85, 42.66, 69.84
B:
        dq 74.80, 66.13, 96.63, 14.69, 54.21, 45.71, 66.39, 37.81
        dq 50.73, 37.78, 84.43, 33.61, 45.97, 49.80, 14.49, 43.76
        dq 18.96, 37.93, 93.11, 29.90, 19.81, 53.22, 75.32, 32.18
        dq 69.17, 74.99, 71.34, 39.87, 42.30, 15.72, 63.75, 66.40
        dq 52.22, 80.36, 79.35, 63.58, 40.21, 57.12, 34.19, 90.87
        dq 43.69, 63.77, 87.68, 52.57, 56.92, 43.21, 70.41, 67.25
        dq 40.64, 51.19, 68.23, 26.75, 37.41, 66.67, 86.45, 28.10
        dq 45.36, 66.58, 12.30, 94.94, 36.39, 32.33, 94.39, 29.26
                                        ; `dq` = define QUADWORD: 8 bytes each, here
                                        ;   holding IEEE-754 doubles. Four of these
                                        ;   fit in one 256-bit ymm register, which is
                                        ;   why the loop below runs 16 times and not
                                        ;   8 as in code-0024.
;;; The dot product should be 198188.457200

section .bss                            ; declared but empty: no uninitialised storage

extern printf                           ; supplied by the C library
global main                             ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- vectorised dot product of two arrays of doubles.
;;;   C equivalent : double s = 0; for (i = 0; i < 64; i++) s += A[i]*B[i];
;;;   Receives     : nothing
;;;   Returns      : rax = 0
;;;   Registers    : ymm0 = four running partial sums, one per lane
;;;                  ymm1, ymm2 = the current block of A and of B
;;;                  rcx = the loop counter (`loopnz` insists on rcx)
;;;                  rdx = the byte offset into both arrays
;;;   How it works : sixteen iterations, each folding four products into the
;;;                  accumulator with a single fused multiply-add. Then a
;;;                  two-step horizontal reduction leaves the total in xmm0 --
;;;                  which is exactly where printf expects its first %f argument.
;;; ----------------------------------------------------------------------------
main:
        push rbp                        ; save the old frame-pointer (callee-saved)
        mov rbp, rsp                    ; anchor this frame
        and rsp, -16                    ; align the stack for the printf at the end

        mov rcx, 16                     ; 64 elements / 4 lanes = 16 iterations.
                                        ;   rcx is not a choice: `loopnz` uses it.
        mov rdx, 0                      ; the byte offset into A and B
        vxorpd ymm0, ymm0, ymm0         ; zero the accumulator, all four lanes.
                                        ;   The `pd` form, not `vpxor`, because the
                                        ;   data is floating-point: mixing integer
                                        ;   and FP domains costs a stall.
.L:
        vmovupd ymm1, [A + rdx]         ; four doubles from A. `u` = Unaligned;
                                        ;   `vmovapd` would fault on an address that
                                        ;   is not 32-byte aligned.
        vmovupd ymm2, [B + rdx]         ; the matching four from B
        vfmadd231pd ymm0, ymm1, ymm2    ; ymm0 := ymm1*ymm2 + ymm0, four lanes at a
                                        ;   time. FUSED multiply-add: one rounding
                                        ;   instead of two, so it is more accurate
                                        ;   than a separate mul and add -- and it is
                                        ;   one instruction instead of two. The
                                        ;   "231" names the operand roles: 2 and 3
                                        ;   are multiplied, 1 is the addend and the
                                        ;   destination.
        add rdx, 8*4                    ; 8 bytes per double * 4 lanes = 32 bytes
        loopnz .L                       ; decrement rcx and repeat while non-zero
.Lout:
;;; --- the HORIZONTAL REDUCTION: four partial sums -> one number ---
        vextractf128 xmm1, ymm0, 1      ; the UPPER 128 bits of ymm0 (lanes 2 and 3).
                                        ;   xmm0 already IS the lower half.
        vaddpd xmm0, xmm0, xmm1         ; four lanes folded into two

                                        ; Either this:
                                        ; movhlps xmm1, xmm0
                                        ;   (one SSE1 instruction: move the high half
                                        ;   into the low half)

                                        ; Or these two lines
        movapd xmm1, xmm0               ; copy the pair...
        unpckhpd xmm1, xmm1             ; ...and broadcast its HIGH lane into both.
                                        ;   Either spelling puts lane 1's value where
                                        ;   a scalar add can reach it.

        addsd xmm0, xmm1                ; SCALAR add (the `sd` suffix): lane 0 only.
                                        ;   xmm0 lane 0 is now the complete sum.

        mov rsi, rax                    ; DEAD INSTRUCTION: left over from the integer
                                        ;   version in code-0024. A `%f` conversion
                                        ;   takes its value from xmm0, never from rsi.
        mov rdi, fmt_dot_product        ; printf argument 1: the format string
        mov rax, 1                      ; |{xmm0}| = 1: exactly ONE vector register
                                        ;   carries an argument. THE VARIADIC RULE --
                                        ;   get this number wrong and printf reads
                                        ;   the wrong place.
        call printf                     ; the double is already sitting in xmm0

        mov rax, 0                      ; status OK for the OS
        mov rsp, rbp                    ; restore the stack pointer from the anchor
        pop rbp                         ; restore the caller's frame-pointer
        ret                             ; pop the return address into rip

section .note.GNU-stack noalloc noexec  ; required Linux marker: stack is not exec
