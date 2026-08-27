;;; ============================================================================
;;; notal.asm -- a 16-bit write preserves the rest of the register
;;; Practice session 2                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Copies the low 16 bits of rax into bx, inverts them, and stops. rax is
;;;   never modified at all.
;;;   (Verified: rax = 0x123456789ABCDEF0 unchanged, and bx = 0x210F.)
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` has no `ret`.
;;;
;;;   READ THIS FILE TOGETHER WITH invert.asm, which is its other half. Between
;;;   them they establish the partial-register rule for x86-64:
;;;
;;;       write to al / ah  (8 bits)   -> the other 56 bits are PRESERVED
;;;       write to bx / ax  (16 bits)  -> the other 48 bits are PRESERVED
;;;       write to ebx / eax (32 bits) -> the upper 32 bits are ZEROED
;;;
;;;   THIS file shows the preserving case, invert.asm shows the zeroing one. The
;;;   32-bit exception is deliberate: always zeroing removes a dependency on the
;;;   register's old value and lets the CPU reorder more freely. It is also why
;;;   compilers write `xor eax, eax` instead of `xor rax, rax` -- one byte
;;;   shorter, identical effect.
;;;
;;;   TRACE IT:
;;;       mov rax, 0x123456789ABCDEF0   rax = 0x123456789ABCDEF0
;;;       mov bx, ax                    bx = 0xDEF0. rbx's upper 48 bits keep
;;;                                     whatever junk they already held.
;;;       not bx                        bx = ~0xDEF0 = 0x210F. Again the upper
;;;                                     48 bits of rbx are untouched.
;;;   So after this program rbx is a MIXTURE: 0x210F in the low 16 bits and
;;;   leftover start-up garbage above. Print `p/x $rbx` in gdb and you will see
;;;   something like 0x2aaaab2a210f -- the 0x210F is yours, the rest is not.
;;;   That is exactly the hazard the rule creates.
;;;
;;;   A NOTE ON THE FILENAME: it says "notal", suggesting `not al`, but the code
;;;   uses bx. Try changing it to `mov al, ...` / `not al` and watch the same
;;;   preservation happen 8 bits at a time.
;;;
;;;   `not` flips every bit of its operand in place and is the only one of
;;;   AND/OR/XOR/NOT that CHANGES NO FLAGS.
;;;
;;;   WHY THE SUB-REGISTERS EXIST AT ALL: they are how you work with bytes and
;;;   16-bit quantities without shifting and masking by hand. code-0019.asm uses
;;;   `mov byte [unget_buffer], al` for precisely that -- store one character,
;;;   using the low byte of a 64-bit register, with no extra instructions.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   `main` has no `ret`, so running it is unreliable. To watch what happens:
;;;   ./asm "ps_code/2/notal.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/2/notal.asm"
;;;
;;;   Useful session:
;;;     display/x $rax
;;;     display/x $rbx
;;;     p/x $rbx                  BEFORE anything -- note the start-up garbage
;;;     si                        mov rax, 0x123456789ABCDEF0
;;;     si                        mov bx, ax   -> low 16 bits of rbx become 0xDEF0,
;;;                               and everything above them is UNCHANGED
;;;     si                        not bx       -> 0x210F, upper bits still unchanged
;;;     p/x $rax                  0x123456789ABCDEF0 -- never touched
;;;     p/x $bx                   0x210f
;;;     p/x $rbx                  0x210f mixed into whatever was there before
;;;
;;;   Now do the contrasting experiment in the SAME session:
;;;     set $rbx = 0xFFFFFFFFFFFFFFFF
;;;     # step the `not bx` again by moving rip back one instruction:
;;;     p $rip
;;;     # ...or simply compare what the two widths would do:
;;;     p/x (0xFFFFFFFFFFFFFFFF & ~0xFFFF) | (~0xDEF0 & 0xFFFF)   the 16-bit result
;;;     p/x (~0x9ABCDEF0) & 0xFFFFFFFF                            the 32-bit result
;;;   The first keeps the top bits, the second does not. That is the whole rule.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing moves on the stack, but this file gives you the clearest possible
;;;   demonstration of why UNINITIALISED REGISTERS ARE NOT ZERO. Before the first
;;;   instruction runs, print them:
;;;       info registers rbx rcx rdx rsi rdi
;;;   None of them is zero. They hold whatever the C library's start-up code left
;;;   behind on its way to calling you. There is no rule that says a register
;;;   starts empty -- and a 16-bit write leaves 48 bits of that history visible.
;;;
;;;   The same is true of stack memory, and it matters more there. When you do
;;;   `sub rsp, 8*3` to make three locals, as code-0018.asm does, those 24 bytes
;;;   contain the remains of whatever function last used that address. Check it:
;;;       break main
;;;       x/8gx $rsp-64             memory below the stack pointer -- old frames
;;;   Every local variable must be INITIALISED before it is read. C compilers
;;;   warn you about this. In assembly, nobody does.
;;;
;;;   And, as everywhere in this folder, rbx is CALLEE-SAVED and is clobbered
;;;   here without being pushed. The return address is still untouched at [rsp]:
;;;       info symbol *(long*)$rsp
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

;;; ----------------------------------------------------------------------------
;;; main -- copy 16 bits, invert them, and leave everything else alone.
;;;   Receives : nothing
;;;   Returns  : nothing -- there is no `ret`. rax is unchanged, bx = 0x210F.
;;;   Clobbers : the low 16 bits of rbx only. rbx is CALLEE-SAVED, so even a
;;;              partial write like this would need a push/pop in a real function.
;;; ----------------------------------------------------------------------------
main:
     mov rax, 0x123456789ABCDEF0        ; a 64-bit value with a distinct nibble in
                                        ;   every position. It is never modified.
    mov  bx, ax                         ; a 16-BIT move: the low 16 bits of rax
                                        ;   (0xDEF0) into the low 16 bits of rbx.
                                        ;   The upper 48 bits of rbx are PRESERVED --
                                        ;   which here means they keep the start-up
                                        ;   garbage they already contained.
     not bx                             ; flip those 16 bits: 0xDEF0 -> 0x210F.
                                        ;   Again the upper 48 bits are untouched, and
                                        ;   `not` sets no flags at all.
     nop                                ; the end -- AND NO `ret`.
