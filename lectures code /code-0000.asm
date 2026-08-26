;;; ============================================================================
;;; code-0000.asm -- The do-nothing program:  int main() { return 0; }
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Nothing at all. It is the smallest possible complete program: it starts,
;;;   returns the value 0, and exits. Its whole purpose is to show you the
;;;   minimum scaffolding every assembly file in this course needs:
;;;     * a `global` directive, so the linker can see your symbol,
;;;     * a `.text` section, where executable instructions live,
;;;     * a `ret`, which hands control back to whoever called you.
;;;
;;;   Note that we write `main`, not `_start`. That means the C library starts
;;;   up first (it sets up the stack, the heap, stdio, the environment) and then
;;;   *calls* our `main` like an ordinary function. This is why `ret` is enough
;;;   to end the program: we return into C library code, which then calls exit().
;;;
;;; RUN IT   (copy-paste this, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0000.asm"
;;;
;;;   It prints nothing. To see that it really returned 0, ask the shell:
;;;   ./asm "lectures code /code-0000.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0000.asm"
;;;
;;;   gdb opens already stopped on the first instruction of `main`. Then:
;;;     si            step ONE instruction  (watch rax change from junk to 0)
;;;     p $rax        print rax
;;;     si            step again -- this executes the `ret`
;;;     bt            backtrace: you are now back inside the C library
;;;     c             continue to the end
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Type `bt` the moment you land in `main`. You will see something like:
;;;       #0  main () at code-0000.asm:NN
;;;       #1  0x00007ffff7... in __libc_start_call_main ()
;;;       #2  0x00007ffff7... in __libc_start_main_impl ()
;;;       #3  0x00000000004... in _start ()
;;;   Read that from the BOTTOM up: it is the history of who called whom.
;;;   `_start` is the true entry point of the executable; it called into the C
;;;   library's startup, which called your `main`. Frame #0 is always "where the
;;;   CPU is right now", and each higher number is one step further back in time.
;;;
;;;   Now do `x/1gx $rsp` before the `ret`. The single quadword sitting at the
;;;   top of the stack IS the return address -- the address inside the C library
;;;   that `call main` pushed there. `ret` does exactly one thing: pop that
;;;   quadword into rip. That is the entire mechanism of returning from a
;;;   function, and every later example in this course builds on it.
;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; main -- the program entry point as far as the C library is concerned.
;;;   C signature : int main(void)
;;;   Receives    : nothing it cares about
;;;   Returns     : rax = 0, the process exit status ("everything is fine")
;;;   How it works: sets the return register and returns immediately.
;;; ----------------------------------------------------------------------------

global main                             ; `global` EXPORTS a symbol from this file so the
                                        ;   linker can find it from other object files.
                                        ;   Without it, `main` would be file-local and the
                                        ;   C library would have nothing to call.
section .text                           ; `section` selects which part of the output file
                                        ;   the following lines go into. `.text` is the
                                        ;   read-only, executable section: machine code.
main:                                   ; a LABEL: a name for "the address of the next
                                        ;   thing emitted". Costs zero bytes; it is just a
                                        ;   name the assembler remembers.
        mov rax, 0                      ; `mov dst, src` copies src into dst (it does NOT
                                        ;   move -- the source is unchanged). Here we put
                                        ;   the 64-bit constant 0 into rax. By the System V
                                        ;   calling convention rax holds a function's return
                                        ;   value, so this is literally `return 0;`.
        ret                             ; `ret` pops the 8-byte return address off the top
                                        ;   of the stack into rip, so execution resumes in
                                        ;   the caller. Equivalent to `pop rip`.

section .note.GNU-stack noalloc noexec  ; A marker section carrying no code and no
                                        ;   data. It tells the Linux loader "this program
                                        ;   does NOT need an executable stack", which is a
                                        ;   security requirement on modern systems. `noalloc`
                                        ;   = takes up no memory at run time, `noexec` = not
                                        ;   executable. Every file in this course ends with
                                        ;   this line; without it the linker warns.
