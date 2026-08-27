;;; ============================================================================
;;; orax.asm -- OR as the "turn these bits ON" operation
;;; Practice session 2                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Computes 0x1122334455667788 OR 0x0000000000008877 and leaves the answer,
;;;   0x112233445566FFFF, in rax. Nothing is printed -- it exists to be
;;;   SINGLE-STEPPED IN gdb.
;;;   (Verified: rax = 0x112233445566ffff after the `or`.)
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` has no `ret`.
;;;
;;;   THE IDEA -- OR IS THE "SET THESE BITS" OPERATION, the exact complement of
;;;   AND. One bit at a time:  x OR 1 = 1  and  x OR 0 = x. So wherever the
;;;   second operand has a 1 the result is forced to 1, and wherever it has a 0
;;;   the original bit survives untouched.
;;;
;;;   READ THE LOW 16 BITS, WHICH IS WHERE THE INTERESTING PART HAPPENS:
;;;       0x7788   0111 0111 1000 1000
;;;       0x8877   1000 1000 0111 0111
;;;       OR       1111 1111 1111 1111   = 0xFFFF
;;;   The two constants are bitwise complements of each other in those 16 bits,
;;;   so ORing them fills every one. Everything above bit 15 is unchanged,
;;;   because the mask is zero there.
;;;
;;;   AND versus OR, side by side (compare andrax.asm in this folder):
;;;       AND  clears the bits where the mask is 0 -- "keep only these"
;;;       OR   sets   the bits where the mask is 1 -- "add these in"
;;;   Together they are how you edit a bit-field without disturbing its
;;;   neighbours: `and` to clear the field, then `or` to write the new value.
;;;   That two-step is the standard idiom for a hardware register, a packed
;;;   struct or a set of flags:
;;;       and rax, ~FIELD_MASK      ; punch a hole
;;;       or  rax, new_value        ; fill it in
;;;
;;;   WHERE YOU MEET THIS FOR REAL: look at code-0022.asm in "lectures code ",
;;;       mov rsi, 0x241            ; O_WRONLY | O_CREAT | O_TRUNC
;;;   Those three constants are 0x001, 0x040 and 0x200 -- each a single bit --
;;;   and 0x241 is their OR. Every "flags" argument you will ever pass to a
;;;   system call is built exactly this way.
;;;
;;;   OR SETS THE FLAGS: ZF from the result, SF from its top bit, and CF and OF
;;;   are always cleared. A useful consequence is that `or rax, rax` is a
;;;   one-instruction "is rax zero?" test that leaves rax alone -- though `test
;;;   rax, rax` is the more idiomatic spelling.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   Don't rely on it -- see above. To watch what happens:
;;;   ./asm "ps_code/2/orax.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/2/orax.asm"
;;;
;;;   Useful session:
;;;     si  si                    load the two constants
;;;     p/x $rax                  0x1122334455667788
;;;     p/x $rbx                  0x8877
;;;     p/t $rax & 0xFFFF         the low 16 bits, in binary
;;;     p/t $rbx & 0xFFFF         ...and the mask's. Note they are complements.
;;;     si                        execute the `or`
;;;     p/x $rax                  0x112233445566ffff
;;;     info registers eflags     CF and OF cleared, as OR always does
;;;
;;;   Build a flags word by hand, the way a system call would:
;;;     p/x 0x001 | 0x040 | 0x200     0x241 -- exactly code-0022's open() flags
;;;     p/x 0x241 & 0x040             non-zero, so O_CREAT is present
;;;     p/x 0x241 & 0x004             0, so that flag is absent
;;;   Setting bits with OR and testing them with AND is the whole vocabulary.
;;;
;;;   And the clear-then-set idiom, on the second byte:
;;;     p/x ($rax & ~0xFF00) | 0xAB00   the byte replaced, neighbours intact
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing happens on it -- `p $rsp` never changes. What this file is really
;;;   worth to you is the reminder that a 64-bit immediate is a legal `mov`
;;;   operand but NOT a legal operand for most arithmetic:
;;;       mov rbx, 0x0000000000008877   ; fine -- mov has a 64-bit immediate form
;;;       or  rax, 0x0000000000008877   ; NOT encodable -- or takes at most a
;;;                                     ;   sign-extended 32-bit immediate
;;;   That is why the constant is loaded into rbx first. Try changing the `or` to
;;;   use the immediate directly and read NASM's complaint -- it is a real
;;;   encoding limit, not a style rule, and it explains a lot of otherwise
;;;   puzzling two-instruction sequences in compiler output.
;;;
;;;   As in the rest of this folder, rbx is CALLEE-SAVED and is being clobbered
;;;   without a push. Fine here because nothing follows; a genuine bug inside a
;;;   real function. And the return address the C library pushed is still sitting
;;;   untouched at [rsp]:
;;;       break main
;;;       info symbol *(long*)$rsp
;;;   Add `ret` after the `nop` to use it.
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

;;; ----------------------------------------------------------------------------
;;; main -- OR a 16-bit pattern into a 64-bit constant.
;;;   Receives : nothing
;;;   Returns  : rax = 0x112233445566FFFF -- but there is no `ret`
;;;   Clobbers : rax, and rbx (which is CALLEE-SAVED and is not preserved)
;;; ----------------------------------------------------------------------------
main:
    mov rax, 0x1122334455667788         ; the value to be modified
    mov rbx, 0x0000000000008877         ; the bits to turn ON. Loaded into a register
                                        ;   because `or` cannot take a full 64-bit
                                        ;   immediate -- only `mov` can.
    or rax, rbx                         ; `or dst, src` = bitwise OR, dst := dst | src.
                                        ;   Where the mask has 1 the result is FORCED
                                        ;   to 1, where it has 0 the original bit is
                                        ;   kept. The low 16 bits become 0xFFFF because
                                        ;   0x7788 and 0x8877 are complements there.
                                        ;   Also sets ZF/SF, and always clears CF/OF.
    nop                                 ; the end -- AND NO `ret`. A one-byte
                                        ;   do-nothing, useful as a breakpoint target.
