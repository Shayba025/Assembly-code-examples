;;; ============================================================================
;;; onbit.asm -- BT: testing one bit by index, and branching on the carry flag
;;; Practice session 2                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Asks whether bit 3 of 0x1234 is set, and adds 5 to rax if it is not.
;;;   (Verified: bit 3 is CLEAR, so the addition happens and rax = 0x1239, with
;;;   rbx = 5 at the `nop`.)
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` has no `ret`.
;;;
;;;   THE INSTRUCTION:
;;;       bt src, index     Bit Test -- copy bit number `index` of src into CF.
;;;   That is all it does. It changes nothing else, and it does not store a
;;;   result anywhere -- the answer arrives in the CARRY FLAG, which is why the
;;;   next instruction is `jc` (jump if carry) rather than `jz` or `je`.
;;;
;;;   CHECK IT BY HAND. 0x1234 in binary:
;;;
;;;       bit:  15 14 13 12 11 10  9  8   7  6  5  4  3  2  1  0
;;;             ---------------------------------------------------
;;;              0  0  0  1  0  0  1  0   0  0  1  1  0  1  0  0
;;;                                                    ^
;;;                                                  bit 3 = 0
;;;
;;;   The low nibble is 4 = 0b0100, so bit 2 is set and bit 3 is clear. CF comes
;;;   back 0, `jc` is NOT taken, and the program falls through into the addition.
;;;   Change the constant to 0x1238 and the branch is taken instead.
;;;
;;;   THE BT FAMILY, all of which put the old bit in CF and differ in what they
;;;   then write back:
;;;       bt   test only                     CF := bit
;;;       bts  test and SET      (bit := 1)  CF := old bit
;;;       btr  test and RESET    (bit := 0)  CF := old bit
;;;       btc  test and COMPLEMENT (flip)    CF := old bit
;;;   The last three are read-modify-write in one instruction, which is exactly
;;;   what you want for a flag word.
;;;
;;;   WHY BOTHER, WHEN AND WOULD DO? You could write
;;;       test rax, 1 << 3
;;;       jnz  bit_is_on
;;;   and for a constant index that is usually what a compiler emits. `bt` earns
;;;   its keep when the index is a VARIABLE -- `bt rax, rcx` works with no
;;;   shifting -- and when the bit lives in a BIT ARRAY in memory, because
;;;   `bt [mem], rcx` will happily index past the first 64 bits, doing the
;;;   divide-by-64 and the remainder for you. That makes it the natural
;;;   instruction for large bitmaps: page tables, allocator free-lists, sieves.
;;;
;;;   THE FLAG TO WATCH IS CF, and this is the first file in the course where a
;;;   branch reads it. Recall which conditionals read what:
;;;       je / jz         ZF        equality
;;;       jl / jg         SF, OF    SIGNED comparison
;;;       jb / ja         CF        UNSIGNED comparison, and carry/borrow
;;;       jc / jnc        CF        the carry flag, directly
;;;   `jc` and `jb` are literally the same instruction with two names.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   `main` has no `ret`, so running it is unreliable. To watch what happens:
;;;   ./asm "ps_code/2/onbit.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/2/onbit.asm"
;;;
;;;   Useful session:
;;;     si                        mov rax, 0x1234
;;;     p/t $rax                  in binary -- find bit 3 and confirm it is 0
;;;     si                        bt rax, 3
;;;     info registers eflags     CF is CLEAR, because bit 3 was 0
;;;     si                        jc bit_is_on -- NOT taken
;;;     si si                     the two instructions of the fall-through path
;;;     p/x $rax                  0x1239
;;;
;;;   Now take the other branch, without editing the file:
;;;     ./debug "ps_code/2/onbit.asm"
;;;     break onbit.asm:NN        NN on the `bt rax, 3` line
;;;     c
;;;     set $rax = 0x1238         bit 3 is now SET
;;;     si                        bt
;;;     info registers eflags     CF is SET this time
;;;     si                        the jc IS taken -- watch rip jump to bit_is_on
;;;
;;;   And explore the whole family at the prompt:
;;;     p ($rax >> 3) & 1         what `bt rax, 3` computes, in C notation
;;;     p/x $rax | (1 << 3)       what `bts rax, 3` would leave behind
;;;     p/x $rax & ~(1 << 3)      what `btr rax, 3` would leave behind
;;;     p/x $rax ^ (1 << 3)       what `btc rax, 3` would leave behind
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing moves on it -- `jc` and the fall-through are both plain changes of
;;;   rip. But this file is a good place to remember the distinction that the
;;;   whole course turns on:
;;;       jmp / jc / jz ...   set rip.          Stack cost: ZERO.
;;;       call                push rip, set it. Stack cost: 8 bytes.
;;;       ret                 pop rip.          Recovers those 8 bytes.
;;;   Confirm it: `p $rsp` before the `bt` and again at `bit_is_on` -- identical,
;;;   whichever branch was taken.
;;;
;;;   THE OTHER THING WORTH NOTICING is the shape of the control flow. The
;;;   "true" branch jumps forward to a label; the "false" branch simply FALLS
;;;   THROUGH into the code below and then reaches the same label. That is an
;;;   if-with-no-else, and it is why `bit_is_on` is reached either way. It is
;;;   the same many-in/one-out pattern as the answer labels in code-0005.asm and
;;;   the five error paths in code-0022.asm: arrange the common continuation to
;;;   be the next thing in memory, and you save a jump.
;;;
;;;   As everywhere in this folder, rbx is CALLEE-SAVED and is clobbered without
;;;   a push, and the return address sits untouched at [rsp]:
;;;       break main
;;;       info symbol *(long*)$rsp
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

;;; ----------------------------------------------------------------------------
;;; main -- test one bit and branch on the result.
;;;   Receives : nothing
;;;   Returns  : rax = 0x1239, rbx = 5 -- but there is no `ret`
;;;   Clobbers : rax, and rbx (which is CALLEE-SAVED and is not preserved)
;;;   Bit 3 of 0x1234 is clear, so the `jc` is not taken and the addition runs.
;;; ----------------------------------------------------------------------------
main:
   mov rax, 0x1234                      ; the value whose bits we are inspecting.
                                        ;   Low nibble = 4 = 0b0100, so bit 2 is set
                                        ;   and BIT 3 IS CLEAR.
   bt rax, 3                            ; Bit Test: copy bit 3 of rax into the CARRY
                                        ;   FLAG. Nothing is stored and rax is not
                                        ;   modified -- the answer lives in CF alone.
                                        ;   (`bts`/`btr`/`btc` are the same test plus
                                        ;   a write-back; see the header.)
   jc bit_is_on                         ; jump if carry -- i.e. if the bit was 1.
                                        ;   Here CF = 0, so this is NOT taken and
                                        ;   control falls through to the two lines
                                        ;   below. (`jc` and `jb` are the same
                                        ;   instruction under two names.)
   mov rbx, 5                           ; the "bit was off" path: load an addend
   add rax, rbx                         ; rax := 0x1234 + 5 = 0x1239
bit_is_on:
        nop                             ; both paths converge here -- the "true"
                                        ;   branch by jumping, the "false" branch by
                                        ;   falling through. The end -- AND NO `ret`.
