;;; ============================================================================
;;; change.asm -- swapping two registers (identical to xchg.asm)
;;; Practice session 2                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Exactly what xchg.asm in this same folder does: loads 1234 and 5678, then
;;;   swaps them with one instruction.
;;;   (Verified: rax = 5678, rbx = 1234 at the `nop`.)
;;;
;;;   THE TWO FILES ARE THE SAME PROGRAM. Diff them and the only differences are
;;;   whitespace:
;;;       diff originals/ps_code/2/xchg.asm originals/ps_code/2/change.asm
;;;   Presumably one is a saved copy of the other from the practice session. Read
;;;   xchg.asm's header for the full discussion of `xchg` -- its atomicity with a
;;;   memory operand, its role in spinlocks, and why compilers avoid it.
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` has no `ret`.
;;;
;;;   WHAT IS WORTH DOING WITH A DUPLICATE FILE: turn it into the comparison the
;;;   folder is missing. Rewrite THIS copy to perform the same swap three other
;;;   ways, and time or count the instructions:
;;;
;;;       1. with a temporary register
;;;              mov rcx, rax
;;;              mov rax, rbx
;;;              mov rbx, rcx          ; 3 instructions, needs a spare register
;;;
;;;       2. with the stack
;;;              push rax
;;;              push rbx
;;;              pop rax
;;;              pop rbx               ; 4 instructions, needs no spare register
;;;                                    ;   but touches memory
;;;
;;;       3. with XOR
;;;              xor rax, rbx
;;;              xor rbx, rax
;;;              xor rax, rbx          ; 3 instructions, no spare, no memory
;;;                                    ;   (this is xorxchg.asm)
;;;
;;;       4. with xchg                 ; 1 instruction  (this file)
;;;
;;;   Four ways to swap two values, trading instruction count against register
;;;   pressure against memory traffic. That trade-off is what most of assembly
;;;   programming actually consists of, and this is the smallest possible example
;;;   of it.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   `main` has no `ret`, so running it is unreliable. To watch what happens:
;;;   ./asm "ps_code/2/change.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/2/change.asm"
;;;
;;;   Useful session:
;;;     display/d $rax
;;;     display/d $rbx
;;;     si si                     load the two values
;;;     si                        the swap -- both registers change in one step
;;;
;;;   Then try variant 2 above by hand, without editing anything, to watch the
;;;   stack version work:
;;;     p $rsp                    note it
;;;     # in gdb you can execute instructions the program does not contain by
;;;     # setting registers directly, but the honest way is to edit the file.
;;;     # Do that: replace the xchg with the four push/pop lines, rebuild, and
;;;     # then step it while watching rsp:
;;;     display $rsp
;;;     si si si si
;;;   rsp drops by 16 and comes back. THAT is the cost of the stack-based swap,
;;;   and it is exactly the cost `xchg` avoids.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   The version in the file leaves rsp completely untouched. The push/pop
;;;   variant above does not, and that contrast is the point of keeping this
;;;   duplicate around.
;;;
;;;   Note the ORDER in the push/pop version:
;;;       push rax   push rbx   pop rax   pop rbx
;;;   The pops come back in the OPPOSITE order from the pushes, and that reversal
;;;   is what performs the swap. It is also the defining property of a stack --
;;;   last in, first out -- and it is the same property that makes recursion work
;;;   in code-0013.asm and backtracking work in code-0004.asm. A stack is not
;;;   primarily "where functions keep things". It is a reversal machine, and
;;;   function calls are one application of that.
;;;
;;;   Watch it in gdb after editing:
;;;       x/2gx $rsp        after both pushes -- 5678 on top, 1234 below
;;;   The value pushed LAST is at the LOWEST address, which is exactly why
;;;   code-0007a.asm has to push the three chunks of its string in reverse order.
;;;
;;;   As everywhere in this folder, rbx is CALLEE-SAVED and is clobbered without
;;;   a push, and the return address is still sitting untouched at [rsp]:
;;;       break main
;;;       info symbol *(long*)$rsp
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

;;; ----------------------------------------------------------------------------
;;; main -- swap two registers. Identical to xchg.asm in this folder.
;;;   Receives : nothing
;;;   Returns  : rax = 5678, rbx = 1234 -- but there is no `ret`
;;;   Clobbers : rax, and rbx (which is CALLEE-SAVED and is not preserved)
;;; ----------------------------------------------------------------------------
main:
     mov rax, 1234                      ; the first value
     mov rbx, 5678                      ; the second
    xchg rax, rbx                       ; EXCHANGE: the two registers trade contents
                                        ;   in one instruction -- no temporary, no
                                        ;   memory, no flags changed. See xchg.asm's
                                        ;   header for why this instruction is
                                        ;   atomic when one operand is memory.
    nop                                 ; the end -- AND NO `ret`.
