;;; ============================================================================
;;; andrax.asm -- AND as a MASK: keeping some bits and clearing the rest
;;; Practice session 2                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Computes 0x1122334455667788 AND 0x0000FFFFFFFFFFFF and leaves the answer,
;;;   0x0000334455667788, in rax. Nothing is printed -- like everything in this
;;;   folder it exists to be SINGLE-STEPPED IN gdb.
;;;   (Verified: rax = 0x334455667788 after the `and`.)
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` has no
;;;   `ret`, so after the `nop` the CPU decodes whatever bytes happen to follow.
;;;   Adding `ret` after the `nop` is the fix, and a good first exercise.
;;;
;;;   THE IDEA -- AND IS THE "KEEP THESE BITS" OPERATION. Look at it one bit at
;;;   a time:  x AND 1 = x  and  x AND 0 = 0. So the second operand is a MASK:
;;;   wherever it has a 1 the original bit survives, wherever it has a 0 the
;;;   original bit is forced to zero. Here the mask 0x0000FFFFFFFFFFFF is
;;;   sixteen 0-bits followed by forty-eight 1-bits, so the instruction means
;;;   "keep the low 48 bits, clear the top 16".
;;;
;;;       rax   0001 0001 0010 0010  0011 0011 0100 0100 ...   (0x11223344...)
;;;       rbx   0000 0000 0000 0000  1111 1111 1111 1111 ...   (0x0000FFFF...)
;;;       AND   0000 0000 0000 0000  0011 0011 0100 0100 ...   (0x00003344...)
;;;
;;;   WHERE YOU MEET THIS FOR REAL:
;;;     * `and rsp, -16` -- the stack-alignment line in every lecture file. -16
;;;       is 0xFFFF...FFF0, a mask with the low four bits clear, so it rounds rsp
;;;       DOWN to a multiple of 16.
;;;     * `and rax, 1` -- isolate the lowest bit, i.e. test for oddness. (See
;;;       `test rax, 1` in code-0015.asm, which does the same without storing.)
;;;     * `and rax, 0xFF` -- keep one byte. Extracting a field from a packed word
;;;       is a shift followed by an AND, and nothing else.
;;;
;;;   AND ITS THREE SIBLINGS, worth learning as a set:
;;;       AND  keep bits          x & 1 = x,  x & 0 = 0
;;;       OR   set bits           x | 1 = 1,  x | 0 = x     (see orax.asm)
;;;       XOR  flip bits          x ^ 1 = ~x, x ^ 0 = x     (see xorxchg.asm)
;;;       NOT  flip all bits                                (see invert.asm)
;;;
;;;   AND SETS THE FLAGS, which is easy to forget: ZF is set if the result is
;;;   zero, SF copies the top bit, and CF and OF are always cleared. That is why
;;;   `test`, which is an AND that discards its result, is the standard way to
;;;   ask "are any of these bits set?".
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   Don't rely on it -- see above. To watch what happens:
;;;   ./asm "ps_code/2/andrax.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/2/andrax.asm"
;;;
;;;   Useful session:
;;;     si  si                    load the two constants
;;;     p/x $rax                  0x1122334455667788
;;;     p/x $rbx                  0xffffffffffff -- note gdb drops leading zeros
;;;     p/t $rbx                  the same value in BINARY: 48 ones
;;;     si                        execute the `and`
;;;     p/x $rax                  0x334455667788 -- the top 16 bits are gone
;;;     info registers eflags     ZF clear, CF and OF always cleared by AND
;;;
;;;   Try other masks without editing the file:
;;;     set $rax = 0x1122334455667788
;;;     set $rbx = 0xFF
;;;     # re-run the `and` by setting rip back one instruction, or simply:
;;;     p/x $rax & 0xFF           0x88 -- the lowest byte
;;;     p/x $rax & 1              0 -- so the value is even
;;;     p/x $rax & -16            the value rounded down to a multiple of 16
;;;
;;;   Seeing `p/x $rax & -16` produce the alignment you have been writing since
;;;   code-0001 is the moment `and rsp, -16` stops being magic.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing moves -- `p $rsp` is the same at the first instruction and at the
;;;   `nop`. But this file is where the stack's most-repeated instruction finally
;;;   makes sense, so do this once:
;;;
;;;       p/x $rsp                   whatever it happens to be
;;;       p/x $rsp & -16             the aligned value `and rsp, -16` produces
;;;       p ($rsp & -16) <= $rsp     1 -- rounding DOWN, always
;;;
;;;   Rounding down is what makes the idiom safe: it can only move rsp further
;;;   away from data you have already placed on the stack, never over it. That is
;;;   exactly the argument code-0007.asm relies on when it captures a pointer
;;;   into rdi and only THEN aligns.
;;;
;;;   The other thing to notice is rbx. It is CALLEE-SAVED -- a function that
;;;   uses it must push it in the prologue and pop it in the epilogue -- and this
;;;   file clobbers it without a thought. Harmless here because nothing runs
;;;   afterwards. In a real function it is the kind of bug that crashes somewhere
;;;   else entirely. Callee-saved on x86-64: rbx, rbp, r12, r13, r14, r15, rsp.
;;;   Everything else is scratch.
;;; ============================================================================

global main                             ; export `main` so the C library start-up can
                                        ;   call it. No `section .text` -- NASM
                                        ;   defaults to it.

;;; ----------------------------------------------------------------------------
;;; main -- mask off the top 16 bits of a 64-bit constant.
;;;   Receives : nothing
;;;   Returns  : rax = 0x0000334455667788 -- but there is no `ret`, so nobody
;;;              collects it
;;;   Clobbers : rax, and rbx (which is CALLEE-SAVED and is not preserved)
;;; ----------------------------------------------------------------------------
main:
    mov rax, 0x1122334455667788         ; the value to be masked. A 64-bit immediate
                                        ;   with a distinct byte in each position, so
                                        ;   you can see exactly which bytes survive.
    mov rbx, 0x0000ffffffffffff         ; THE MASK: sixteen 0-bits then forty-eight
                                        ;   1-bits. `p/t $rbx` in gdb shows it.
    and rax, rbx                        ; `and dst, src` = bitwise AND, dst := dst & src.
                                        ;   Where the mask has 1 the original bit is
                                        ;   KEPT, where it has 0 the bit is CLEARED.
                                        ;   Result: 0x0000334455667788.
                                        ;   Also sets the flags: ZF from the result,
                                        ;   and CF and OF are always cleared.
    nop                                 ; the end -- AND NO `ret`. `nop` does nothing,
                                        ;   in one byte, and exists purely as a place
                                        ;   to put a breakpoint.
