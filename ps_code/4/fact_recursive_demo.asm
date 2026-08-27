;;; ============================================================================
;;; fact_recursive_demo.asm -- recursion built from hand-made CALL and RETURN
;;; Practice session 4                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Computes 5! = 120 recursively and prints "fact (5)=120". Every `call` and
;;;   every `ret` in the program is a MACRO -- there is not one of either
;;;   instruction in the object file.
;;;   (Verified: prints `fact (5)=120`. The exit status is 13, which is printf's
;;;   character count: `main` never resets rax before its final `ret`.)
;;;
;;;   THIS IS THE CULMINATION OF ps_code/4. Read the folder in order:
;;;       push_pop_demo.asm      push and pop are sub/store and load/add
;;;       call_return_demo.asm   call and ret are push+jmp and pop+jmp
;;;       this file              ...and recursion is just that, repeated
;;;
;;;   THE POINT: recursion needs NOTHING from the hardware beyond a pointer and
;;;   some memory. There is no "call stack" feature in the CPU -- only rsp, some
;;;   RAM, and the discipline of pushing before you leave and popping when you
;;;   come back. This program proves it by discarding the two instructions
;;;   usually credited with making recursion possible, and recursing anyway.
;;;
;;;   HOW ONE ACTIVATION OF `fact` USES THE STACK. Follow the addresses:
;;;       CALL fact        pushes the return address        rsp -= 8
;;;       enter 0,0        pushes rbp, sets rbp = rsp       rsp -= 8
;;;       PUSH rdi         saves n across the recursion     rsp -= 8
;;;       CALL fact        pushes the next return address   rsp -= 8
;;;         ... the callee does the same, one level deeper ...
;;;       POP rdi          recovers n                       rsp += 8
;;;       leave            rsp = rbp, then pops rbp         rsp += 8
;;;       RETURN           pops the return address, jumps   rsp += 8
;;;   So each level costs 24 bytes, and `bt` will show one frame per level.
;;;   Exactly the same arithmetic as `fact` in code-0010.asm -- which is the
;;;   whole point, since that file used the real instructions.
;;;
;;;   WHY n MUST BE PUSHED. `imul rax, rdi` at the end needs n, but the recursive
;;;   call is entitled to destroy rdi (it is caller-saved, and the callee uses it
;;;   as its own parameter). So n is parked on the stack across the call and
;;;   recovered afterwards. This is the SPILL you met in code-0013.asm -- a value
;;;   that must outlive a call cannot live in a caller-saved register.
;;;
;;;   THE MACROS USE r11, NOT r12. Compare call_return_demo.asm, which uses r12.
;;;   Both work, for different reasons:
;;;       r11 is CALLER-saved -- free to clobber, and the return address that
;;;           matters is the copy on the STACK, not the one in the register.
;;;       r12 is CALLEE-saved -- so the callee is obliged to hand it back intact.
;;;   r11 is the better choice here precisely because recursion overwrites it at
;;;   every level and nobody cares.
;;;
;;;   `lea r11, [rel %%L]` is RIP-RELATIVE addressing: "the address of %%L,
;;;   computed as an offset from the current instruction". It produces
;;;   position-independent code, which is what modern linkers prefer.
;;;   call_return_demo.asm's `mov r12, %%L` uses an absolute address instead --
;;;   simpler, but it needs `-no-pie` at link time, which the ./asm script
;;;   happens to pass.
;;;
;;;   `%%L` is a MACRO-LOCAL label: NASM invents a fresh unique name at each
;;;   expansion, which is essential here because CALL is expanded three times.
;;;
;;;   `enter 0,0` = `push rbp` + `mov rbp, rsp`; `leave` = `mov rsp, rbp` +
;;;   `pop rbp`. The familiar prologue and epilogue, in one instruction each.
;;;
;;;   `imul rax, rdi` is the SIGNED multiply in its friendly two-operand form:
;;;   rax := rax * rdi, with no hidden registers. Compare the one-operand
;;;   `mul rcx` in code-0009.asm, which commandeers both rdx and rax.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/4/fact_recursive_demo.asm" ; echo "exit status = $?"
;;;
;;;   To try a different n, edit `mov rdi, 5` near the bottom. Careful: 21! and
;;;   beyond overflow a 64-bit register, and %d prints only the low 32 bits, so
;;;   the printed answer goes wrong well before that -- try 13 and check.
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/4/fact_recursive_demo.asm"
;;;
;;;   THE session for this file -- watch a stack build itself out of macros:
;;;     break fact
;;;     c  c  c                   descend three levels
;;;     bt                        one frame per level, exactly as if `call` had
;;;                               been used -- gdb cannot tell the difference
;;;     p $rdi                    this level's n
;;;     x/1gx $rbp+8              this level's return address
;;;     info symbol *(long*)($rbp+8)
;;;                               ...named. It is the macro's %%L.
;;;     up                        move out one level
;;;     x/1gx $rbp+8              a DIFFERENT return address
;;;     down
;;;
;;;   Measure the cost per level:
;;;     break fact
;;;     c
;;;     p $rsp                    note it
;;;     c
;;;     p $rsp                    24 bytes lower. Multiply by n for the total.
;;;
;;;   Watch the spill that makes the multiplication possible:
;;;     break fact_recursive_demo.asm:NN    NN on the `PUSH rdi` line
;;;     c
;;;     p $rdi                    n
;;;     si si                     the two instructions of the PUSH macro
;;;     x/1gd $rsp                n, safe on the stack
;;;     break fact
;;;     c                         descend into the recursive call
;;;     p $rdi                    n-1 -- the register has been reused
;;;     # ...and the parked copy is still untouched, one frame up
;;;
;;;   And confirm the macros vanished:
;;;     disassemble fact          no `call`, no `ret` -- lea/sub/mov/jmp only
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Put this file next to code-0010.asm ("lectures code ") and run both under
;;;   gdb with n = 5. Break on `fact` in each and type `bt`. YOU WILL SEE THE
;;;   SAME PICTURE: six frames, 24 bytes apiece, results multiplying together on
;;;   the way back out. One program uses `call` and `ret`; the other uses four
;;;   macros made of `sub`, `mov`, `add`, `lea` and `jmp`. The stack does not
;;;   know or care which.
;;;
;;;   THAT IS THE LESSON WORTH KEEPING. A call stack is not a hardware
;;;   structure -- it is a CONVENTION about how to use a pointer and some memory:
;;;       * put the return address somewhere the callee can find it
;;;       * agree who restores rsp (see code-0010 vs code-0011: caller or callee)
;;;       * agree which registers survive a call and which do not
;;;   Get all three right and recursion works. `call` and `ret` are a one-byte
;;;   encoding of the first point, nothing more. code-0005.asm makes the same
;;;   argument from the opposite end, keeping continuations in registers and
;;;   never touching the stack at all.
;;;
;;;   ONE THING TO TRY, because it fails instructively. Comment out the `PUSH rdi`
;;;   and `POP rdi` pair, rebuild, and run. The answer becomes wrong -- and it
;;;   will not crash, which is worse. The recursion still returns correctly,
;;;   because the RETURN ADDRESSES are still being managed properly; only the
;;;   DATA was lost. Return addresses and saved data live on the same stack and
;;;   are protected by different halves of the same discipline.
;;; ============================================================================

%macro PUSH 1                           ; `push %1`, written out. See push_pop_demo.asm.
   sub rsp, 8                           ; claim 8 bytes -- the stack grows downward
   mov qword [rsp], %1                  ; store the value into the slot just claimed
%endmacro

%macro POP 1                            ; `pop %1`, written out
   mov %1, qword [rsp]                  ; read the top of the stack...
   add rsp, 8                           ; ...and release the slot
%endmacro

%macro CALL 1                           ; `call %1`, written out
   lea  r11, [rel %%L]                  ; THE RETURN ADDRESS, computed RIP-RELATIVELY:
                                        ;   "the address of %%L as an offset from here".
                                        ;   Position-independent, unlike
                                        ;   call_return_demo.asm's absolute `mov`.
                                        ;   r11 is CALLER-saved, which is fine: the copy
                                        ;   that matters is the one on the stack.
   PUSH r11                             ; push it, exactly as a real `call` would
   jmp %1                               ; ...and go. The jmp itself remembers nothing.
   %%L:                                 ; macro-local label -- unique per expansion, and
                                        ;   this macro is expanded three times
%endmacro

%macro RETURN 0                         ; `ret`, written out
   POP r11                              ; take the return address off the stack...
   jmp  r11                             ; ...and jump to it. An INDIRECT JUMP, which is
                                        ;   all `ret` has ever been. Using r11 rather
                                        ;   than rax leaves the return VALUE intact --
                                        ;   compare call_return_demo.asm, whose RETURN
                                        ;   clobbers rax.
%endmacro

section .data                           ; initialised, writable data
fmt:    db "fact (%d)=%d" , 10, 0       ; printf format. Double quotes do not expand
                                        ;   escapes in NASM, so the newline (10) and the
                                        ;   terminator (0) are written as numbers.
                                        ;   %d prints a 32-BIT int -- see the overflow
                                        ;   note in the header.

section .text
global main                             ; export `main` for the C library start-up
extern printf                           ; supplied by the C library

;;; ----------------------------------------------------------------------------
;;; fact -- n! by recursion, using the hand-made CALL/RETURN macros.
;;;   Pseudo-C : long fact(long n) { return n <= 1 ? 1 : n * fact(n-1); }
;;;   Receives : rdi = n            (System V style: the argument is in a REGISTER,
;;;                                  unlike code-0010.asm, which pushes it)
;;;   Returns  : rax = n!
;;;   Clobbers : rax, rdi, r11
;;;   Frame    : [rbp + 8*1] return address, [rbp] saved rbp, [rbp - 8*1] the
;;;              parked copy of n. 24 bytes per level.
;;;
;;;   THE ESSENTIAL LINE IS `PUSH rdi`. n is needed AFTER the recursive call, for
;;;   the multiply, but rdi is caller-saved and the callee uses it as its own
;;;   parameter. So n is spilled to the stack and recovered afterwards -- the same
;;;   problem, and the same solution, as code-0013.asm's `push rax`.
;;; ----------------------------------------------------------------------------
fact:
   enter 0,0                            ; prologue: `push rbp` + `mov rbp, rsp` in one
                                        ;   instruction. Establishes this activation's
                                        ;   anchor.
   cmp rdi, 1                           ; is n greater than 1?
   jg .recursive                        ; `jg` = signed greater: keep recursing
   mov rax, 1                           ; THE BASE CASE: fact(0) = fact(1) = 1
   leave                                ; epilogue: `mov rsp, rbp` + `pop rbp`
   RETURN                               ; the macro: pop the return address, jmp to it
.recursive:
   PUSH rdi                             ; SPILL n to the stack. The recursive call is
                                        ;   about to overwrite rdi, and the multiply
                                        ;   below still needs the original value.
   dec rdi                              ; the argument for the next level: n-1
   CALL fact                            ; recurse. rax comes back holding (n-1)!
   POP rdi                              ; recover our own n from the stack
   imul rax, rdi                        ; rax := (n-1)! * n. The two-operand SIGNED
                                        ;   multiply -- no hidden rdx, unlike the
                                        ;   one-operand `mul` in code-0009.asm.
   leave                                ; epilogue
   RETURN                               ; and back to whichever CALL got us here

;;; ----------------------------------------------------------------------------
;;; main -- compute 5! and print it.
;;;   Receives : nothing
;;;   Returns  : rax = printf's character count (13), never reset to 0
;;;   Clobbers : rax, rdi, rsi, rdx, r11, r12
;;;   r12 holds a copy of n across the call to `fact`, and that is safe because
;;;   r12 is CALLEE-SAVED: `fact` is obliged to give it back unchanged. Contrast
;;;   the `PUSH rdi` inside `fact`, which had to use the stack because rdi is not.
;;; ----------------------------------------------------------------------------
main:
    enter 0,0                           ; prologue: push rbp, rbp := rsp
    mov rdi, 5                          ; the argument to fact. Edit this to try other
                                        ;   values -- but see the overflow note above.
    mov  r12, rdi                       ; keep a copy for printing afterwards. r12 is
                                        ;   CALLEE-SAVED, so `fact` must preserve it --
                                        ;   no stack slot needed.
    CALL fact                           ; rax := 5! = 120
    mov rsi, r12                        ; printf argument 2: the original n
    mov rdx, rax                        ; printf argument 3: the factorial
    mov rdi, fmt                        ; printf argument 1: the format string
    xor rax, rax                        ; 0 vector registers carry arguments -- the
                                        ;   variadic rule
    CALL printf                         ; the hand-made call again. printf's own real
                                        ;   `ret` pops the address our macro pushed.
    leave                               ; epilogue: rsp := rbp, pop rbp
    ret                                 ; a REAL `ret` -- back to the C library.
                                        ;   NOTE rax is not reset first, so the exit
                                        ;   status is printf's character count, 13.

section .note.GNU-stack                 ; the "no executable stack" marker. Note it
                                        ;   lacks the `noalloc noexec` attributes the
                                        ;   lecture files use -- compare code-0000.asm.
