;;; ============================================================================
;;; xorxchg.asm -- the XOR swap: exchanging two values with no temporary
;;; Practice session 2                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Swaps rax and rbx using three XORs and nothing else -- no third register,
;;;   no memory, no `xchg`.
;;;   (Verified: rax = 0x5678, rbx = 0x1234 at the `nop`.)
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` has no `ret`.
;;;
;;;   WHY IT WORKS. XOR has two properties that make it special:
;;;       x ^ x = 0            a value cancels itself
;;;       x ^ 0 = x            zero is the identity
;;;   and it is both commutative and associative, so you can regroup freely. Now
;;;   write a for the original rax and b for the original rbx and follow along:
;;;
;;;       start                 rax = a              rbx = b
;;;       xor rax, rbx          rax = a^b            rbx = b
;;;       xor rbx, rax          rax = a^b            rbx = b^(a^b) = a
;;;       xor rax, rbx          rax = (a^b)^a = b    rbx = a
;;;
;;;   Each step throws away one value and recovers another from the combination.
;;;   The pair (a^b, b) contains exactly as much information as (a, b) -- nothing
;;;   is lost, so nothing needs storing.
;;;
;;;   THE FAMOUS BUG: if the two operands are the SAME register, the XOR swap
;;;   destroys the value. `xor rax, rax` sets rax to 0, and the remaining two
;;;   XORs cannot bring it back. A `mov`-based or `xchg`-based swap is immune.
;;;   That is one reason nobody uses this trick in production -- along with the
;;;   fact that the three instructions are serially dependent, so the CPU cannot
;;;   overlap them, while three `mov`s often cost nothing at all because the
;;;   register renamer eliminates them.
;;;
;;;   SO WHY LEARN IT? Because XOR-as-cancellation shows up everywhere:
;;;     * `xor eax, eax` is the standard way to zero a register -- shorter to
;;;       encode than `mov eax, 0`, and it breaks the dependency on the old value.
;;;     * XOR linked lists store prev^next in one pointer field.
;;;     * A one-time pad is XOR, and so is the simplest checksum: XOR everything,
;;;       and duplicated items cancel out.
;;;     * "Find the one unpaired number in a list" is solved by XORing the whole
;;;       list -- every pair cancels and the answer remains.
;;;
;;;   THE FOUR WAYS TO SWAP, all present in this folder:
;;;       xchg rax, rbx                 1 instruction  (xchg.asm, change.asm)
;;;       three XORs                    3 instructions, no spare register (here)
;;;       three MOVs via a temporary    3 instructions, needs a spare register
;;;       push/push/pop/pop             4 instructions, touches memory
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   `main` has no `ret`, so running it is unreliable. To watch what happens:
;;;   ./asm "ps_code/2/xorxchg.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/2/xorxchg.asm"
;;;
;;;   THE session for this file -- watch the intermediate state, which is the
;;;   whole point:
;;;     display/x $rax
;;;     display/x $rbx
;;;     si si                     load 0x1234 and 0x5678
;;;     si                        rax = 0x1234 ^ 0x5678 = 0x444C  <- neither value!
;;;     si                        rbx = 0x5678 ^ 0x444C = 0x1234  <- recovered
;;;     si                        rax = 0x444C ^ 0x1234 = 0x5678  <- recovered
;;;
;;;   Check the algebra yourself at the prompt:
;;;     p/x 0x1234 ^ 0x5678       0x444c
;;;     p/x 0x444c ^ 0x5678       0x1234 -- b recovered from the combination
;;;     p/x 0x444c ^ 0x1234       0x5678 -- and a
;;;     p/x 0x1234 ^ 0x1234       0 -- the cancellation property
;;;
;;;   And reproduce the aliasing bug without editing anything:
;;;     break xorxchg.asm:NN      NN on the first `xor rax, rbx` line
;;;     c
;;;     # pretend both operands named the same register:
;;;     p/x $rax ^ $rax           0 -- the value is gone, and no later XOR
;;;                               can recover it
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing happens on it -- and that is exactly what this file is for. The
;;;   whole reason to know the XOR swap is that it needs NO STORAGE: not a spare
;;;   register, not a stack slot, nothing.
;;;
;;;   Put that next to the swap in bubble_sort, in code-0021.asm:
;;;       mov r8, qword [rdx + 8*rax]        ; load both...
;;;       mov r9, qword [rdx + 8*rax + 8]
;;;       mov qword [rdx + 8*rax], r9        ; ...store them back crossed over
;;;       mov qword [rdx + 8*rax + 8], r8
;;;   That version uses two registers as temporaries, which is fine because they
;;;   were free. If they had not been, you would have had to spill something to
;;;   the frame -- and the frame-layout diagrams in code-0018.asm and
;;;   code-0021.asm are what that costs.
;;;
;;;   The general question behind all of this is REGISTER PRESSURE: how many
;;;   values must be alive at the same moment? Below the limit, everything stays
;;;   in registers and the stack is idle, as here and in code-0024.asm. Above it,
;;;   you spill, and the stack becomes the extension of the register file --
;;;   which is precisely what code-0013.asm's `push rax` between its two
;;;   recursive calls is doing.
;;;
;;;   As everywhere in this folder, rbx is CALLEE-SAVED and is clobbered without
;;;   a push, and the return address is sitting untouched at [rsp]:
;;;       break main
;;;       info symbol *(long*)$rsp
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

;;; ----------------------------------------------------------------------------
;;; main -- swap rax and rbx with three XORs and no temporary.
;;;   Receives : nothing
;;;   Returns  : rax = 0x5678, rbx = 0x1234 -- but there is no `ret`
;;;   Clobbers : rax, and rbx (which is CALLEE-SAVED and is not preserved)
;;;   Writing a for the original rax and b for the original rbx:
;;;       after step 1:  rax = a^b,  rbx = b
;;;       after step 2:  rax = a^b,  rbx = a
;;;       after step 3:  rax = b,    rbx = a
;;;   FAILS if both operands name the same register -- see the header.
;;; ----------------------------------------------------------------------------
main:
   mov rax, 0x1234                      ; call this value a
   mov rbx, 0x5678                      ; call this value b
   xor rax, rbx                         ; `xor dst, src` = bitwise exclusive-or.
                                        ;   rax := a ^ b -- a COMBINATION that holds
                                        ;   both values and neither. 0x444C here.
   xor rbx, rax                         ; rbx := b ^ (a^b) = a, because b cancels
                                        ;   itself. The first value is now recovered
                                        ;   in the second register.
   xor rax, rbx                         ; rax := (a^b) ^ a = b, for the same reason.
                                        ;   The swap is complete, and no temporary was
                                        ;   ever needed.
   nop                                  ; the end -- AND NO `ret`.
