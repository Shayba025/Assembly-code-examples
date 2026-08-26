;;; ============================================================================
;;; code-0007.asm -- scanf can read into a STACK slot, not just a global
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prompts "int> ", reads one integer, echoes it back. Trivially small; the
;;;   whole point is that NOTHING lives in .bss. Compare code-0001, which
;;;   reserved global slots `a` and `b` for scanf to write into. Here the slot is
;;;   made on the fly:
;;;
;;;       sub rsp, 8*1      <-- carve 8 bytes out of the stack
;;;       mov rsi, rsp      <-- their address is scanf's output pointer
;;;
;;;   That is exactly what a C compiler does for a LOCAL VARIABLE. `long x;`
;;;   inside a function is not magic -- it is `sub rsp, 8` and a name for the
;;;   offset. This file is where you see that mapping directly.
;;;
;;;   THREE TECHNIQUES ARE COMBINED HERE:
;;;
;;;   1. Strings as immediates pushed on the stack (from code-0006).
;;;   2. Output parameters: scanf needs the ADDRESS of the destination, which is
;;;      why we pass rsp and not the value at rsp.
;;;   3. Addressing locals from rbp rather than rsp. After the call, the number
;;;      is read back as `qword [rbp - 8*2]`, NOT as `[rsp]` -- because rsp has
;;;      moved since (the `and rsp, -16` before the call). rbp has not moved, so
;;;      offsets from rbp stay valid for the whole function. THIS IS THE REASON
;;;      FRAME POINTERS EXIST.
;;;
;;;   WHERE IS -8*2? Walk the stack down from the anchor:
;;;       [rbp - 8*0] .. the saved rbp is AT [rbp]
;;;       [rbp - 8*1] .. the pushed "%lld\0" format string
;;;       [rbp - 8*2] .. the 8 bytes carved out by `sub rsp, 8*1`  <-- the number
;;;   Count the pushes and you can name every local without guessing.
;;;
;;;   Note also the discipline this file adds over code-0006: `and rsp, -16` is
;;;   repeated immediately before EVERY call, because each intervening push or
;;;   sub may have broken the alignment. And after the printf, `mov rsp, rbp`
;;;   resets the world before the next stanza begins.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0007.asm"          # then type a number + Enter
;;;   echo 12345 | ./asm "lectures code /code-0007.asm"
;;;   echo -42  | ./asm "lectures code /code-0007.asm"
;;;
;;; DEBUG IT
;;;   echo 12345 | ./debug "lectures code /code-0007.asm"
;;;
;;;   Useful session:
;;;     p $rbp                 the anchor; write it down
;;;     break scanf
;;;     c
;;;     info registers rdi rsi the format string, and the ADDRESS to write into
;;;     x/s $rdi               "%lld"
;;;     p $rsi - $rbp          -16, i.e. rsi == rbp - 8*2. The output slot.
;;;     finish                 let scanf run; rax = number of items converted (1)
;;;     x/1gd $rbp-16          the integer scanf just deposited on YOUR stack
;;;     p $rsp                 note it is NOT equal to $rbp-16 any more --
;;;                            this is why the code reads via rbp
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Dump the frame and read it like a map. Stop just before the final printf
;;;   and do:
;;;       x/6gx $rbp-40        six quadwords around your frame
;;;       x/1gx $rbp           the SAVED rbp of the caller
;;;       x/1gx $rbp+8         the RETURN ADDRESS into the C library
;;;   Everything at a NEGATIVE offset from rbp is yours (locals); everything at
;;;   a positive offset belongs to the machinery of the call itself. That layout
;;;   is identical for every function you will ever disassemble, in any language.
;;;
;;;   The experiment that makes the lesson stick: single-step with `si` and watch
;;;   `p $rsp` after each of `push rdi`, `sub rsp, 8`, `and rsp, -16`, and again
;;;   after `call scanf` returns. rsp will have taken four different values while
;;;   your integer sat still at rbp-16 the whole time. A pointer into a moving
;;;   region is only usable if you measure it from something that does not move.
;;;
;;;   Finally note the danger. Your integer lives BELOW rsp only until the next
;;;   `and rsp, -16` -- after that it is fair game for anything that pushes.
;;;   Returning a pointer to a stack local from a function is the classic
;;;   dangling-pointer bug, and this file shows you precisely why: `mov rsp, rbp`
;;;   in the epilogue un-allocates it with a single instruction, without erasing
;;;   anything. Do `x/1gd $rbp-16` after the epilogue in gdb -- the value is
;;;   still visibly there, and is now completely unowned.
;;; ============================================================================

section .data                           ; the ONE piece of static data in the program
fmt_output:
        db `You entered: %lld\n\0`      ; too long for a 64-bit immediate (18 bytes), so
                                        ;   unlike the other two strings here it has to go
                                        ;   in .data. code-0007a shows how to push even
                                        ;   this one onto the stack, in three pieces.

extern printf, scanf                    ; supplied by the C library
global main                             ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- prompt, read an integer into a stack local, print it back.
;;;   C equivalent:
;;;       int main(void) { long long x; printf("int> "); scanf("%lld", &x);
;;;                        printf("You entered: %lld\n", x); }
;;;   Receives    : nothing it uses
;;;   Returns     : rax = printf's character count (never explicitly zeroed)
;;;   Frame layout: [rbp]      saved caller rbp
;;;                 [rbp-8*1]  the pushed format string of the moment
;;;                 [rbp-8*2]  the integer read by scanf
;;;   How it works: three stanzas, each of which builds its arguments, aligns
;;;                 the stack, calls, and (for the first) resets rsp from rbp.
;;; ----------------------------------------------------------------------------
main:
        push rbp                        ; save the old frame-pointer (callee-saved register)
        mov rbp, rsp                    ; point to the base of the new frame. NOTE: unlike
                                        ;   the earlier files there is no `and rsp,-16`
                                        ;   here -- alignment is done per-call below.

        mov rdi, `int> \0`              ; a [format] string is just a number!
                                        ;   6 bytes -- 'i','n','t','>',' ','\0' -- packed
                                        ;   into one 64-bit immediate. Little-endian layout
                                        ;   puts 'i' at the lowest address, so it reads
                                        ;   correctly out of memory.
        push rdi                        ; ...even on the stack. Now at [rsp]. This lands at
                                        ;   [rbp - 8*1].
        mov rdi, rsp                    ; so the rsp is its address! rdi = printf's 1st
                                        ;   argument, a char* into our own stack.
        mov rax, 0                      ; 0 floating-point registers in use (variadic rule)
        and rsp, -16                    ; align the stack downwards, on 16 bytes -- the
                                        ;   `push` above left it at 8 mod 16, so this fixes
                                        ;   it. Done AFTER rdi was captured, deliberately:
                                        ;   the string's address was already saved.
        call printf                     ; prints the prompt "int> "
        mov rsp, rbp                    ; restore the rsp -- wipes the pushed string and
                                        ;   the alignment slack in one go, back to a clean
                                        ;   empty frame

        mov rdi, `%lld\0`               ; the scanf format-string as a number: 5 bytes
                                        ;   '%','l','l','d','\0' in one immediate
        push rdi                        ; ...on the stack. Lands at [rbp - 8*1] again --
                                        ;   the previous string is gone, this reuses the slot.
        mov rdi, rsp                    ; So the rsp is its address! scanf argument 1.
        sub rsp, 8*1                    ; Making room for the integer. `sub` moves rsp DOWN
                                        ;   8 bytes, and the stack grows downward, so this
                                        ;   ALLOCATES 8 bytes. This is exactly how a C
                                        ;   compiler creates a local variable.
        mov rsi, rsp                    ; So the rsp is its address! scanf argument 2 --
                                        ;   the POINTER to write the result into, i.e. `&x`.
                                        ;   This slot is [rbp - 8*2].
        and rsp, -16                    ; align the stack downwards, on 16 bytes. Safe to do
                                        ;   now: rsi already holds the slot's address, and
                                        ;   rounding rsp down can only move it away from
                                        ;   our data, never over it.
        call scanf                      ; reads a decimal from stdin and stores it at [rsi]

        mov rdi, fmt_output             ; the printf format-string in the data section
        mov rsi, qword [rbp - 8*2]      ; this is the number we read with scanf.
                                        ;   Addressed from rbp, NOT rsp -- rsp has moved
                                        ;   twice since scanf's slot was carved out, but
                                        ;   rbp has not moved at all. This is the payoff of
                                        ;   keeping a frame pointer.
        mov rax, 0                      ; 0 floating-point registers in use
        and rsp, -16                    ; align the stack downwards, on 16 bytes (rsp may
                                        ;   already be aligned; the instruction is harmless
                                        ;   and cheap, so it is done unconditionally)
        call printf                     ; prints "You entered: <n>"

        mov rsp, rbp                    ; restore the rsp: discard the local, the string
                                        ;   and the padding, all at once
        pop rbp                         ; point to the base of the previous frame
        ret                             ; pop the return address into rip

section .note.GNU-stack noalloc noexec  ; required Linux marker: stack is not exec
