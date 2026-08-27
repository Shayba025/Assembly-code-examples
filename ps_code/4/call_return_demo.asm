;;; ============================================================================
;;; call_return_demo.asm -- building `call` and `ret` out of push and jmp
;;; Practice session 4                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints two lines with printf. The output is beside the point -- the file
;;;   exists to show that `call` and `ret` are not primitive. They are shorthand:
;;;
;;;       call target       is exactly       push <address of the next line>
;;;                                          jmp target
;;;
;;;       ret               is exactly       pop rax
;;;                                          jmp rax
;;;
;;;   The four macros at the top spell all of that out. PUSH and POP are the
;;;   sub/store and load/add pair from push_pop_demo.asm in this folder; CALL and
;;;   RETURN are built on top of them. Read that file first.
;;;   (Verified: prints "Hello world!" then "hakol oved heytev!", exit status 0.)
;;;
;;;   THE ONE CLEVER LINE IS `mov r12, %%L`. A macro needs to name the
;;;   instruction that comes AFTER its own expansion -- the return address. It
;;;   does that by planting a label at the end of itself:
;;;       %macro CALL 1
;;;          mov r12, %%L          ; r12 := the address of the line after the jmp
;;;          PUSH r12              ; ...pushed, exactly as `call` would
;;;          jmp %1                ; ...and go
;;;          %%L:                  ; <- this is where the callee will return to
;;;       %endmacro
;;;   `%%L` is a MACRO-LOCAL label: NASM invents a fresh, unique name at each
;;;   expansion, so using CALL twice does not produce two labels called L. Without
;;;   `%%` the second use would fail to assemble.
;;;
;;;   AND THAT IS THE WHOLE OF THE CALL MECHANISM: a return address is just a
;;;   number, computed at assembly time, stored in memory, and eventually loaded
;;;   into rip. Nothing about it is magical, which is exactly the point
;;;   code-0005.asm makes from the other direction when it keeps continuations in
;;;   rcx and r8 and jumps to them.
;;;
;;;   NOTE THAT `printf` STILL WORKS. The library function was compiled with a
;;;   real `ret`, and it pops whatever address it finds on the stack. It cannot
;;;   tell that the address was pushed by a macro rather than by a `call`
;;;   instruction -- because there is nothing to tell. THAT is the proof that the
;;;   two are equivalent.
;;;
;;;   TWO INSTRUCTIONS YOU HAVE NOT MET YET:
;;;       enter 0,0     equivalent to `push rbp` + `mov rbp, rsp`. The operands
;;;                     are (bytes of locals, nesting level); with 0,0 it is just
;;;                     the standard prologue. It exists for Pascal-style nested
;;;                     procedures and is SLOWER than writing the two
;;;                     instructions out, so compilers do not use it.
;;;       leave         equivalent to `mov rsp, rbp` + `pop rbp`. The standard
;;;                     epilogue, and unlike `enter` it is genuinely fast and
;;;                     widely used.
;;;   So `enter 0,0` / `leave` here are exactly the prologue and epilogue you
;;;   have been writing by hand since code-0001.asm.
;;;
;;;   A DETAIL WORTH CHECKING: r12 is CALLEE-SAVED, so printf is obliged to give
;;;   it back unchanged -- which is lucky, because the CALL macro leaves the
;;;   return address in it. Had the macro used, say, r11 (caller-saved), the
;;;   value in the register would be destroyed. It would still work, because the
;;;   address that matters is the one on the STACK, not the one in the register.
;;;   fact_recursive_demo.asm in this folder uses r11 for exactly that reason.
;;;
;;;   THE ALIGNMENT WORKS OUT, and it is worth confirming rather than assuming.
;;;   At `main`, `call main` has left rsp at 8 mod 16. `enter 0,0` pushes rbp, so
;;;   rsp is 0 mod 16. The CALL macro's PUSH makes it 8 mod 16 -- which is
;;;   precisely what a real `call` would have left, so printf sees exactly the
;;;   alignment the ABI promises it.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/4/call_return_demo.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/4/call_return_demo.asm"
;;;
;;;   THE session for this file -- watch a return address being manufactured:
;;;     display/x $rsp
;;;     si si                     enter 0,0 and mov rdi, message
;;;     si                        xor rax, rax
;;;     si                        mov r12, <the macro's %%L>
;;;     info symbol $r12          gdb names the very next source line
;;;     x/1i $r12                 ...and disassembles it
;;;     si si                     sub rsp,8 / mov [rsp],r12   <- the "push"
;;;     x/1gx $rsp                the return address, now in memory
;;;     info symbol *(long*)$rsp  the same line, read back from the stack
;;;     si                        jmp printf
;;;     bt                        gdb shows printf called FROM main -- it cannot
;;;                               tell the difference either
;;;     finish                    let printf run its own `ret`
;;;     p $rip                    you are back at %%L, exactly as planned
;;;
;;;   Check the macros really did vanish:
;;;     disassemble main          no `call` instruction anywhere -- just
;;;                               mov/sub/mov/jmp
;;;
;;;   And confirm the alignment claim:
;;;     break printf
;;;     c
;;;     p $rsp % 16               8, exactly as a real `call` would have left it
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THIS IS THE FILE THAT DEMYSTIFIES THE STACK COMPLETELY. Everything the
;;;   lecture files do with `call`, `ret`, frames and return addresses is built
;;;   from three primitive operations: change rsp, move memory, change rip. This
;;;   program performs them by hand and the C library cannot tell.
;;;
;;;   Do this experiment, which is the point of the whole exercise. Break just
;;;   after the CALL macro's push and TAMPER WITH THE RETURN ADDRESS:
;;;       break printf
;;;       c
;;;       x/1gx $rsp                    the return address printf will use
;;;       set *(long*)$rsp = *(long*)$rsp + 3
;;;       c
;;;   The program now returns into the middle of an instruction and misbehaves.
;;;   Nothing checked it. Nothing could have -- the "return address" is just
;;;   eight bytes of memory that `ret` copies into rip. That is simultaneously
;;;   why the stack is so cheap and why STACK BUFFER OVERFLOWS ARE EXPLOITABLE:
;;;   overwrite those eight bytes with an address of your choosing and you have
;;;   redirected the program.
;;;
;;;   It is also why `section .note.GNU-stack noalloc noexec` appears at the end
;;;   of every lecture file: it tells the loader the stack does not need to be
;;;   executable, so an attacker who overwrites a return address cannot simply
;;;   point it at data they also wrote there. (This file's `.note.GNU-stack` line
;;;   has no `noalloc noexec` attributes -- compare code-0000.asm.)
;;;
;;;   Finally, note what the RETURN macro reveals: `pop rax` then `jmp rax`. A
;;;   `ret` is an INDIRECT JUMP through a value taken from memory. Once you have
;;;   seen that, `jmp rcx` in code-0005.asm's `between` stops looking exotic --
;;;   it is a `ret` whose address came from a register instead of the stack. Same
;;;   machine, same idea, different storage.
;;; ============================================================================

%macro PUSH 1                           ; `push %1`, written out. See push_pop_demo.asm.
   sub rsp, 8                           ; claim 8 bytes -- the stack grows downward
   mov qword [rsp], %1                  ; store the value into the slot just claimed
%endmacro

%macro POP 1                            ; `pop %1`, written out
   mov %1, qword [rsp]                  ; read the top of the stack...
   add rsp, 8                           ; ...and release the slot (nothing is erased)
%endmacro

%macro CALL 1                           ; `call %1`, written out
   mov r12, %%L                         ; THE RETURN ADDRESS. `%%L` is a MACRO-LOCAL
                                        ;   label: NASM invents a unique name at each
                                        ;   expansion, so using CALL twice is fine.
                                        ;   Loading a label into a register loads its
                                        ;   ADDRESS -- code addresses are just numbers.
   PUSH r12                             ; push it, exactly as a real `call` would
   jmp %1                               ; ...and transfer control. Note: JMP, which by
                                        ;   itself remembers nothing. The remembering
                                        ;   was the push.
   %%L:                                 ; the callee's `ret` will land here
%endmacro

%macro RETURN 0                         ; `ret`, written out
   POP rax                              ; take the return address off the stack...
   jmp rax                              ; ...and jump to it. AN INDIRECT JUMP -- which
                                        ;   is all `ret` has ever been.
                                        ;   (Note this clobbers rax, so this macro
                                        ;   cannot be used by a function that returns a
                                        ;   value. fact_recursive_demo.asm uses r11.)
%endmacro

section .data                           ; initialised, writable data
message: db "Hello world!",10,0         ; a C string. Double quotes do NOT expand
                                        ;   escapes in NASM, so the newline (10) and
                                        ;   terminator (0) are written as numbers.
                                        ;   Compare the backquoted `\n\0` form used in
                                        ;   the lecture files.
hebrew: db  "hakol oved heytev!",10,0   ; "everything works fine", transliterated
extern printf                           ; supplied by the C library
global main                             ; export `main` for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- print two strings, using hand-built CALL instead of `call`.
;;;   Receives : nothing
;;;   Returns  : rax = 0
;;;   Clobbers : rax, rdi, r12 (which holds the manufactured return address)
;;;   The two printf invocations go through the CALL macro, so the object file
;;;   contains no `call` instruction at all -- check with `disassemble main`.
;;; ----------------------------------------------------------------------------
main:
     enter 0,0                          ; the standard prologue in one instruction:
                                        ;   `push rbp` + `mov rbp, rsp`. The operands
                                        ;   are (local bytes, nesting level). Slower
                                        ;   than writing the two out, so compilers
                                        ;   avoid it -- but it is exactly equivalent.
     mov rdi, message                   ; printf argument 1: the address of the string
     xor rax, rax                       ; 0 vector registers carry arguments -- the
                                        ;   variadic rule. `xor r, r` is the idiomatic
                                        ;   zeroing.
     CALL printf                        ; the macro: manufacture a return address, push
                                        ;   it, and jmp. printf's own `ret` pops it and
                                        ;   comes back -- it cannot tell the difference.
     mov rdi, hebrew                    ; printf argument 1: the second string
     xor rax, rax                       ; again, 0 vector registers
     CALL printf                        ; a SECOND expansion -- which is why `%%L` had
                                        ;   to be macro-local, or the two labels would
                                        ;   collide
     xor rax, rax                       ; main's return value: 0 = success
     leave                              ; the standard epilogue in one instruction:
                                        ;   `mov rsp, rbp` + `pop rbp`
     ret                                ; a REAL `ret` this time -- back to the C library

section .note.GNU-stack                 ; the "no executable stack" marker. Note it
                                        ;   lacks the `noalloc noexec` attributes the
                                        ;   lecture files use -- compare code-0000.asm.
