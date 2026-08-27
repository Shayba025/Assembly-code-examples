;;; ============================================================================
;;; divbymul.asm -- dividing by multiplying: 64/7 without a `div` in the hot path
;;; Practice session 2                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Computes 64 / 7 = 9 using a MULTIPLICATION by a precomputed reciprocal.
;;;   (Verified: rcx = 0x2492492492492492 and rax = 9 at the `nop`.)
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` has no `ret`.
;;;
;;;   WHY ANYONE WOULD DO THIS. `div` is by far the slowest integer instruction
;;;   on x86 -- roughly 20 to 40 cycles for 64-bit operands, and it cannot be
;;;   pipelined. `mul` costs about 3. So when you must divide by the SAME
;;;   constant many times, it pays to compute 1/d once and multiply thereafter.
;;;   Every optimising compiler does exactly this: write `x / 7` in C, look at
;;;   the assembly, and you will find a magic constant and a `mul`, not a `div`.
;;;
;;;   THE MATHEMATICS, in one line:
;;;       n / d  ==  (n * (2^64 / d)) / 2^64
;;;   Multiplying two 64-bit numbers gives a 128-bit product in RDX:RAX, and
;;;   dividing by 2^64 means simply TAKING THE HIGH HALF. So the whole division
;;;   becomes one `mul` followed by `mov rax, rdx`. No shifting, no second
;;;   division -- the register split does the work for free. That is the trick.
;;;
;;;   THE AWKWARD PART is computing 2^64/7, because 2^64 does not fit in a
;;;   64-bit register. The file works around it in two steps:
;;;       mov rax, 1 ; shl rax, 63       rax = 2^63, which DOES fit
;;;       xor rdx, rdx ; div rsi         rax = 2^63/7 = 0x1249249249249249
;;;       shl rax, 1                     rax = 2*(2^63/7) ~ 2^64/7
;;;                                          = 0x2492492492492492
;;;   The doubling is approximate -- it loses the low bit of the true quotient --
;;;   which is exactly why this technique needs care in general. For d = 7 and
;;;   small n it happens to give the right answer; a production version uses a
;;;   rounded-up magic number plus a correction shift, and there are published
;;;   algorithms for choosing them.
;;;
;;;   TRY IT AND SEE IT BREAK: change rdi from 64 to 7 and the answer should be
;;;   1, but the truncation above may give 0. That failure is the point --
;;;   reciprocal division is a real optimisation with real preconditions, not a
;;;   free lunch.
;;;
;;;   THE THREE INSTRUCTIONS TO KNOW:
;;;       div src     UNSIGNED divide. Reads the 128-bit dividend in RDX:RAX,
;;;                   writes the quotient to RAX and THE REMAINDER TO RDX. You
;;;                   MUST set rdx first -- `xor rdx, rdx` for unsigned, `cqo`
;;;                   for signed `idiv` -- or you get junk, or a #DE exception.
;;;       mul src     UNSIGNED multiply. RDX:RAX := RAX * src. It WRITES rdx
;;;                   without reading it, which is why `cqo` before a `mul` (as
;;;                   in code-0009.asm and factorial.asm) achieves nothing.
;;;       shl r, k    shift left by k, i.e. multiply by 2^k.
;;;   Note how `div` and `mul` are mirror images: one splits RDX:RAX apart, the
;;;   other builds it up. This file uses both halves of that symmetry.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   `main` has no `ret`, so running it is unreliable. To watch what happens:
;;;   ./asm "ps_code/2/divbymul.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/2/divbymul.asm"
;;;
;;;   Useful session -- follow the reciprocal being built:
;;;     si si si si               through `shl rax, 63`
;;;     p/x $rax                  0x8000000000000000 = 2^63
;;;     si si                     xor rdx, rdx  then  div rsi
;;;     p/x $rax                  0x1249249249249249 = 2^63/7
;;;     p $rdx                    1 -- THE REMAINDER, free of charge
;;;     si                        shl rax, 1
;;;     p/x $rax                  0x2492492492492492, the approximate 2^64/7
;;;
;;;   Then the multiply that replaces the division:
;;;     si si                     mov rcx, rax ; mov rax, rdi
;;;     si                        mul rcx
;;;     p/x $rdx                  9 -- the HIGH half of the 128-bit product
;;;     p/x $rax                  the low half, which is discarded
;;;     si                        mov rax, rdx
;;;     p $rax                    9 = 64/7
;;;
;;;   Check the arithmetic at the prompt:
;;;     p (unsigned long)(1UL<<63)/7          0x1249249249249249
;;;     p 64/7                                9
;;;     p/x 0x2492492492492492 * 64           the low half only -- gdb wraps at 64
;;;                                           bits, which is exactly why the CPU
;;;                                           gives you rdx as well
;;;
;;;   And watch it fail, to see the precondition:
;;;     break divbymul.asm:NN     NN on the `mov rax, rdi` line
;;;     c
;;;     set $rdi = 7              7/7 should be 1
;;;     si si si
;;;     p $rax                    check whether the truncation cost you the answer
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing happens on the stack, but this file is the best illustration in the
;;;   folder of a REGISTER CONTRACT you do not get to choose.
;;;
;;;   `div` and `mul` both hard-wire rdx and rax. You cannot ask for the product
;;;   somewhere else, and you cannot skip initialising rdx before a divide. That
;;;   is a convention enforced by the silicon, and it is the same KIND of thing
;;;   as the calling conventions the lecture files spend so long on -- an
;;;   agreement about which register means what, which you must honour exactly.
;;;   The difference is only who enforces it:
;;;       the CPU        rdx:rax for mul/div, rcx for loop/shift counts
;;;       the ABI        rdi, rsi, rdx, rcx, r8, r9 for arguments; rax for the
;;;                      return value; rax = float count for variadic calls
;;;       the kernel     rax = call number, and r10 instead of rcx for argument 4
;;;   Three different sets of rules about the same sixteen registers, and getting
;;;   any of them wrong produces wrong answers rather than error messages.
;;;
;;;   The concrete stack connection: because `mul` and `div` commandeer rdx and
;;;   rax, a function that needs to keep something in either across a
;;;   multiplication has to put it somewhere else first -- a callee-saved
;;;   register, or the frame. Look at code-0010.asm's `fact`, which re-reads n
;;;   from `[rbp + 8*2]` immediately before its `mul` rather than keeping it in a
;;;   register. It has to: the recursive call destroyed the registers, and the
;;;   `mul` is about to destroy two more. THE FRAME IS THE ONLY THING THAT
;;;   SURVIVES BOTH.
;;;
;;;   As everywhere in this folder, the return address sits untouched at [rsp]:
;;;       break main
;;;       info symbol *(long*)$rsp
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

; calculating 64/7 by mul with inverse number of 7 64*1/7

;;; ----------------------------------------------------------------------------
;;; main -- divide 64 by 7 using a reciprocal multiplication.
;;;   Receives : nothing
;;;   Returns  : rax = 9 -- but there is no `ret`
;;;   Clobbers : rax, rcx, rdx, rdi, rsi
;;;   Registers: rdi = the dividend n (64)
;;;              rsi = the divisor d (7)
;;;              rcx = the precomputed reciprocal, approximately 2^64/7
;;;              rdx = receives the HIGH half of the product, which is the answer
;;;   Phase 1 builds the reciprocal with one (slow) division. Phase 2 does the
;;;   actual work with one (fast) multiplication. In real code phase 1 happens
;;;   once, at compile time, and only phase 2 appears in the loop.
;;; ----------------------------------------------------------------------------
main:
    mov rdi, 64                         ; the dividend n
    mov rsi, 7                          ; the divisor d
    mov rax, 1                          ; build 2^63 in two steps, because a 64-bit
     shl rax, 63                        ;now rax = 2^63
                                        ;   `shl r, k` shifts left k bits, i.e.
                                        ;   multiplies by 2^k. We want 2^64/7 but 2^64
                                        ;   does not fit in a register, so start with
                                        ;   2^63 and double the quotient afterwards.
   xor rdx, rdx                         ; rdx is the high  64 bits of the result or residue.
                                        ;   `div` reads a 128-BIT dividend in RDX:RAX,
                                        ;   so rdx MUST be initialised. XOR with itself
                                        ;   is the idiomatic zeroing. (For signed
                                        ;   `idiv` you would use `cqo` instead.)
    div rsi                             ; rax = 2^63/7 still not the inverse, rdx = residue
                                        ;   UNSIGNED divide: quotient to RAX, REMAINDER
                                        ;   TO RDX. rax becomes 0x1249249249249249.
                                        ;   This is the slow instruction the whole
                                        ;   technique exists to avoid repeating.
    shl rax, 1                          ; rax = 2^64 , a necessary step to get the inverse
                                        ;   doubling 2^63/7 approximates 2^64/7 =
                                        ;   0x2492492492492492. APPROXIMATES: the low
                                        ;   bit of the true quotient is lost, which is
                                        ;   why this needs care in general.
    mov rcx, rax                        ; park the reciprocal. In real code this
                                        ;   constant is baked in by the compiler and
                                        ;   everything above disappears.
    mov rax, rdi                        ; rax := n, because `mul` always multiplies rax
   mul rcx                              ; rdx:rax = a*1/b
                                        ;   UNSIGNED multiply: the 128-bit product
                                        ;   spans RDX:RAX. Dividing that by 2^64 means
                                        ;   simply taking the high half -- the register
                                        ;   split does it for free.
   mov rax, rdx                         ; the highest 64 bits are the result
                                        ;   rax := 9, which is 64/7. One multiply has
                                        ;   replaced one divide.
   nop                                  ; the end -- AND NO `ret`.
