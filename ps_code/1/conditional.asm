;;; ============================================================================
;;; conditional.asm -- cmp and the conditional jumps, in isolation
;;; Practice session 1                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Nothing you can see. It compares 10 with 20, jumps to one of three labels,
;;;   executes a couple of `nop`s, and stops. IT IS NOT MEANT TO BE RUN -- it is
;;;   meant to be SINGLE-STEPPED IN gdb so you can watch the flags decide where
;;;   control goes. The `nop`s exist purely to give you somewhere to land and put
;;;   a breakpoint.
;;;
;;;   *** RUNNING IT SEGFAULTS, AND THAT IS EXPECTED. *** `main` has no `ret`, so
;;;   after the last `nop` the CPU keeps decoding whatever bytes follow -- which
;;;   are not instructions. Every file in this practice folder has the same
;;;   shape. Adding `ret` at the end of `exit:` would make it exit cleanly, and
;;;   that is a good first exercise.
;;;
;;;   THE MECHANISM, which is the whole point:
;;;       cmp rax, rbx      computes rax - rbx and THROWS THE ANSWER AWAY,
;;;                         keeping only the FLAGS in the rflags register:
;;;                           ZF (zero)     set when the two were equal
;;;                           SF (sign)     set when the result was negative
;;;                           OF (overflow) set when the subtraction overflowed
;;;                           CF (carry)    set on unsigned borrow
;;;       jl / jg / je      read those flags. They perform no comparison of their
;;;                         own -- they are simply reading what `cmp` left behind.
;;;
;;;   SIGNED VERSUS UNSIGNED IS A CHOICE YOU MAKE IN THE JUMP, NOT IN THE `cmp`:
;;;       signed:    jl  jle  jg  jge      (less / greater)
;;;       unsigned:  jb  jbe  ja  jae      (below / above)
;;;       either:    je  jne  jz  jnz
;;;   The same `cmp` feeds both families. Choosing the wrong family is one of the
;;;   most common bugs in assembly -- with rax = -1 and rbx = 1, `jl` is taken
;;;   and `jb` is not, because -1 as an unsigned number is enormous.
;;;
;;;   NOTE THE DEAD CODE: since 10 < 20, `jl less_than` is always taken and the
;;;   `jg` and `je` lines below it can never execute. That is deliberate -- edit
;;;   the two constants and re-run to reach the other branches.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   Don't -- see above. If you want to watch it fail:
;;;   ./asm "ps_code/1/conditional.asm" ; echo "exit status = $?"
;;;
;;;   The linker will also warn about a missing .note.GNU-stack section. That is
;;;   the marker every file in "lectures code " ends with; these practice files
;;;   omit it. Harmless here, and worth adding once you know what it is for.
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/1/conditional.asm"
;;;
;;;   Useful session:
;;;     si  si                    load rax and rbx
;;;     info registers rax rbx    10 and 20
;;;     si                        execute the `cmp`
;;;     info registers eflags     [ SF ] -- 10-20 is negative, so SF is set and
;;;                               ZF is clear. THAT is the whole result.
;;;     si                        the `jl` -- watch rip move to less_than
;;;     bt                        still one frame; a jump is not a call
;;;
;;;   Now change the answer without changing the code:
;;;     ./debug "ps_code/1/conditional.asm"
;;;     break conditional.asm:NN  NN on the `cmp rax, rbx` line
;;;     c
;;;     set $rbx = 5              now rax > rbx
;;;     si si                     cmp, then the jl -- NOT taken this time
;;;     si                        the jg IS taken
;;;   Being able to steer a program by writing registers in gdb is one of the
;;;   most useful debugging skills there is.
;;;
;;;   To see the flags on their own:
;;;     p $eflags                 gdb prints them as a readable list
;;;     p ($eflags >> 6) & 1      ZF, extracted by hand
;;;     p ($eflags >> 7) & 1      SF
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Chiefly, what happens when you ignore it. `main` was reached by a `call`
;;;   from the C library, which pushed a return address; this program never pops
;;;   it, because it has no `ret`. Look:
;;;       break main
;;;       x/1gx $rsp              the return address into the C library
;;;       info symbol *(long*)$rsp
;;;                               __libc_start_call_main, or similar
;;;   That quadword is a fully valid instruction to "go home", sitting untouched
;;;   at the top of the stack, and the program walks off the end of itself
;;;   instead. Add `ret` after the final `nop`, rebuild, and it exits cleanly --
;;;   with rax as its exit status, which is 10 here because nothing reset it.
;;;
;;;   The second observation is that `jmp` costs nothing on the stack. Print
;;;   `p $rsp` at `main` and again at `exit:` -- identical. Compare `call`, which
;;;   lowers rsp by 8 every time. In this file every transfer of control is a
;;;   jump, so the stack is exactly as the C library left it, from the first
;;;   instruction to the last.
;;; ============================================================================

section .text                           ; the executable-code section
global  main                            ; export `main` so the C library start-up
                                        ;   code can call it

;;; ----------------------------------------------------------------------------
;;; main -- compare two constants and branch three ways.
;;;   Receives : nothing
;;;   Returns  : it does not -- there is no `ret`. See the header.
;;;   How it works: `cmp` sets the flags; the three conditional jumps read them.
;;; ----------------------------------------------------------------------------
main:
    mov rax, 10                         ; the left-hand operand of the comparison
    mov rbx, 20                         ; the right-hand operand. (rbx is
                                        ;   callee-saved and is being clobbered
                                        ;   without a push -- see the lecture files.)
    cmp rax, rbx                        ; compute rax - rbx and DISCARD the result,
                                        ;   keeping only the flags: ZF, SF, OF, CF.
                                        ;   It is a subtraction whose only product
                                        ;   is "how do these two compare".
    jl less_than                        ; jump if LESS, signed. Reads SF and OF --
                                        ;   it performs no comparison itself.
                                        ;   10 < 20, so this is ALWAYS taken and
                                        ;   the next two lines are dead code.
    jg greater_than                     ; jump if GREATER, signed. Unreachable here.
    je  equal                           ; jump if EQUAL -- reads ZF alone, so it is
                                        ;   the one conditional that means the same
                                        ;   thing for signed and unsigned values.
                                        ;   Also unreachable here.

less_than:
             nop                        ; `nop` does nothing at all, in one byte. It
             nop                        ;   exists here purely as a landing pad you
                                        ;   can set a breakpoint on.
            jmp exit                    ; unconditional jump: nothing is pushed
greater_than:
             nop                        ; the same landing pad for the "greater" case
             nop
            jmp exit
equal:
             nop                        ; ...and for the "equal" case
             nop
            jmp exit
exit:

           nop                          ; the end of the program -- AND THERE IS NO
                                        ;   `ret`. Execution continues into whatever
                                        ;   bytes follow, which is why running this
                                        ;   crashes. Adding `ret` here is the fix.
