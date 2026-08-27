;;; ============================================================================
;;; invert.asm -- NOT, and the trap of partial-register writes
;;; Practice session 2                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Looks like it does nothing: it inverts ax twice (which cancels out) and
;;;   then inverts eax. But the final value of rax is NOT what you would guess.
;;;   (Verified: rax = 0x000000006543210F at the `nop`.)
;;;
;;;   *** THIS FILE IS A TRAP, AND THAT IS THE WHOLE POINT. *** Predict the
;;;   answer before you read on, then check it in gdb.
;;;
;;;   THE RULE THAT CATCHES EVERYONE -- x86-64 treats writes to the 8-, 16- and
;;;   32-bit sub-registers DIFFERENTLY:
;;;
;;;       write to al  or ah  (8 bits)   -> the other 56 bits are PRESERVED
;;;       write to ax         (16 bits)  -> the other 48 bits are PRESERVED
;;;       write to eax        (32 bits)  -> the upper 32 bits are ZEROED
;;;       write to rax        (64 bits)  -> obviously, all of it
;;;
;;;   The 32-bit case is the odd one out, and it is not an accident: AMD chose it
;;;   deliberately when designing x86-64, because always zeroing removes a
;;;   dependency on the register's previous value and lets the CPU reorder more
;;;   aggressively. It is also why compilers write `xor eax, eax` rather than
;;;   `xor rax, rax` -- same effect, one byte shorter.
;;;
;;;   NOW TRACE THIS FILE:
;;;       mov rax, 0x123456789ABCDEF0    rax = 0x123456789ABCDEF0
;;;       not ax                         ax = ~0xDEF0 = 0x210F, UPPER 48 KEPT
;;;                                      rax = 0x123456789ABC210F
;;;       not ax                         back to 0xDEF0
;;;                                      rax = 0x123456789ABCDEF0   (unchanged!)
;;;       not eax                        eax = ~0x9ABCDEF0 = 0x6543210F
;;;                                      ...AND THE UPPER 32 BITS ARE ZEROED
;;;                                      rax = 0x000000006543210F
;;;
;;;   So the first two instructions really do cancel, and the third quietly
;;;   destroys the top half of the register. If you expected 0x123456789ABC...
;;;   to survive, you have just met the single most common surprise in 64-bit
;;;   x86.
;;;
;;;   `not` itself is the simplest instruction here: flip every bit of the
;;;   operand, in place. It is the only one of AND/OR/XOR/NOT that DOES NOT
;;;   TOUCH THE FLAGS at all -- worth knowing, because it means you can invert a
;;;   value between a `cmp` and its conditional jump without disturbing the
;;;   comparison.
;;;
;;;   Compare notal.asm in this folder, which does the 16-bit half of the same
;;;   experiment and confirms that the upper bits really are preserved.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   `main` has no `ret`, so running it is unreliable. To watch what happens:
;;;   ./asm "ps_code/2/invert.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/2/invert.asm"
;;;
;;;   THE session for this file -- print rax after EVERY instruction:
;;;     display/x $rax
;;;     si                        mov rax, 0x123456789ABCDEF0
;;;     si                        not ax    -> 0x123456789ABC210F
;;;     si                        not ax    -> 0x123456789ABCDEF0, restored
;;;     si                        not eax   -> 0x6543210F, TOP HALF GONE
;;;
;;;   See the sub-registers as separate views of the same bits:
;;;     p/x $rax                  the whole 64
;;;     p/x $eax                  the low 32
;;;     p/x $ax                   the low 16
;;;     p/x $al                   the low 8
;;;     p/x $ah                   bits 8-15
;;;   They are not four registers. They are four windows onto one register, and
;;;   the only thing that differs is what a WRITE does to the bits outside the
;;;   window.
;;;
;;;   Prove the zeroing rule for yourself, without editing the file:
;;;     set $rax = 0xFFFFFFFFFFFFFFFF
;;;     set $eax = 0                  gdb writes the whole register here, so
;;;                                   instead check it with a real instruction:
;;;     # put a breakpoint on the `not eax` line and step it:
;;;     set $rax = 0xAAAAAAAAAAAAAAAA
;;;     si
;;;     p/x $rax                  0x55555555 -- upper half zeroed, not preserved
;;;
;;;   And confirm `not` leaves the flags alone:
;;;     info registers eflags     before
;;;     si
;;;     info registers eflags     identical
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing moves on it. The value of this file to the rest of the course is
;;;   that partial-register writes are all over the ABI, and getting them wrong
;;;   silently corrupts data rather than crashing.
;;;
;;;   Two places you have already seen it:
;;;     * code-0019.asm -- `mov byte [unget_buffer], al` writes ONE byte from the
;;;       low end of rax. It has to be `al`, because the destination is one byte
;;;       wide, and the upper bits of rax are irrelevant.
;;;     * code-0024.asm -- `movd eax, xmm0` extracts a 32-bit result, and the
;;;       very next line does `mov rsi, rax` and relies on the upper 32 bits
;;;       being zero. That only works BECAUSE of the rule this file demonstrates.
;;;       Had the instruction written to `ax`, rsi would have inherited garbage.
;;;
;;;   And the general lesson for reading a frame dump: when you see `x/1gx $rbp-8`
;;;   come back with a plausible small number in the low half and rubbish in the
;;;   top half, a partial-register write is very often why. Look for a 16-bit or
;;;   8-bit `mov` into the register that was stored there.
;;;
;;;   As everywhere in this folder, the return address is still on the stack,
;;;   unused, because there is no `ret`:
;;;       break main
;;;       info symbol *(long*)$rsp
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

;;; ----------------------------------------------------------------------------
;;; main -- demonstrate that 16-bit writes preserve and 32-bit writes zero.
;;;   Receives : nothing
;;;   Returns  : rax = 0x000000006543210F -- but there is no `ret`
;;;   Clobbers : rax only
;;;   The first two instructions cancel each other exactly. The third does not
;;;   just invert 32 bits -- it also destroys the upper 32. That asymmetry is the
;;;   entire exercise.
;;; ----------------------------------------------------------------------------
main:
     mov rax, 0x123456789ABCDEF0        ; a 64-bit value with a different nibble in
                                        ;   every position, so you can see exactly
                                        ;   which parts change
     not ax                             ; `not` flips every bit of its operand, in
                                        ;   place, and TOUCHES NO FLAGS.
                                        ;   `ax` is the low 16 bits: 0xDEF0 becomes
                                        ;   0x210F, and the upper 48 bits are
                                        ;   PRESERVED. rax = 0x123456789ABC210F.
     not ax                             ; flip them back. rax is now exactly what it
                                        ;   was two instructions ago -- proof that a
                                        ;   16-bit write really does preserve.
     not eax                            ; `eax` is the low 32 bits: 0x9ABCDEF0 becomes
                                        ;   0x6543210F. BUT a 32-bit write ALSO ZEROES
                                        ;   THE UPPER 32 BITS -- so rax ends up as
                                        ;   0x000000006543210F, not
                                        ;   0x123456786543210F. THIS IS THE TRAP.
     nop                                ; the end -- AND NO `ret`.
