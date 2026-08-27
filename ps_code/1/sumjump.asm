;;; ============================================================================
;;; sumjump.asm -- the same sum as sumloop.asm, written with cmp/jz/dec/jmp
;;; Practice session 1                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Adds multiples of 5 into rax, using an explicit test-and-jump loop instead
;;;   of the `loop` instruction. READ IT SIDE BY SIDE WITH sumloop.asm -- that
;;;   comparison is the entire exercise:
;;;
;;;       sumloop.asm                     sumjump.asm
;;;       --------------------------      --------------------------
;;;       add rax, rbx                    add rax, rbx
;;;       add rbx, 5                      cmp rcx, 0
;;;       loop cont                       jz end
;;;                                       dec rcx
;;;                                       add rbx, 5
;;;                                       jmp cont
;;;
;;;   One instruction versus four. And they do NOT give the same answer: `loop`
;;;   tests at the BOTTOM after decrementing, while this version tests in the
;;;   MIDDLE, after the add but before the decrement. Work out which one adds an
;;;   extra term before you look it up -- then check with gdb.
;;;
;;;   *** RUNNING IT SEGFAULTS, AND THAT IS EXPECTED. *** `main` has no `ret`.
;;;
;;;   WHY WRITE IT THE LONG WAY? Because `loop` is genuinely limiting: the
;;;   counter must be rcx, it can only count down, it can only step by one, and
;;;   its jump range is a single signed byte (-128..+127), so it cannot reach a
;;;   distant label. Modern compilers essentially never emit it -- `dec`/`jnz` is
;;;   faster on current hardware. The explicit form has none of those limits: you
;;;   can test any register, in any direction, with any condition, anywhere in
;;;   the body. Learn to read both; write the explicit one.
;;;
;;;   THE FLAG SUBTLETY WORTH NOTICING: `dec rcx` sets ZF all by itself, so the
;;;   `cmp rcx, 0` above it is not strictly necessary if you are willing to
;;;   restructure -- `dec rcx ; jnz cont` is the idiomatic two-instruction loop
;;;   tail, and it is what a compiler would produce. Try rewriting this file that
;;;   way and see whether the answer changes.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   Don't -- see above. To watch it fail:
;;;   ./asm "ps_code/1/sumjump.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/1/sumjump.asm"
;;;
;;;   Useful session:
;;;     display/d $rax            the accumulator
;;;     display/d $rbx            the term being added
;;;     display/d $rcx            the counter
;;;     si si si                  past the setup
;;;   Then hold down `si` and watch. Do the same for sumloop.asm in another
;;;   window and compare the final rax -- the difference is the whole lesson
;;;   about where you put the test.
;;;
;;;   Count the iterations mechanically rather than by eye:
;;;     break sumjump.asm:NN      NN on the `add rax, rbx` line
;;;     ignore 1 1000             never stop, just tally
;;;     c
;;;     info breakpoints          the hit count is the iteration count
;;;   Do the same in sumloop.asm and compare the two numbers.
;;;
;;;   And watch the flags being produced and consumed:
;;;     break sumjump.asm:NN      NN on the `cmp rcx, 0` line
;;;     c
;;;     info registers eflags     before
;;;     si
;;;     info registers eflags     after -- ZF is what `jz` will read
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Again, nothing moves: `p $rsp` is identical at the first instruction and at
;;;   `end:`. Both `jmp` and the conditional jumps are pure changes of rip, with
;;;   no push and no pop. That is the distinction to have firmly in mind:
;;;       jmp / jz / jl ...   set rip. Cost on the stack: zero.
;;;       call                push rip, then set it. Cost: 8 bytes.
;;;       ret                 pop rip. Recovers those 8 bytes.
;;;   Every loop you will ever write is built from the first kind; every function
;;;   from the second and third.
;;;
;;;   And, as in the rest of this folder, the return address the C library pushed
;;;   is still sitting untouched at [rsp] when the program walks off its own end:
;;;       break main
;;;       info symbol *(long*)$rsp
;;;   Add `ret` after the final `nop` to use it.
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

;;; ----------------------------------------------------------------------------
;;; main -- sum multiples of 5 with an explicit test-and-jump loop.
;;;   Receives : nothing
;;;   Returns  : rax holds the sum -- but there is no `ret`, so nobody collects it
;;;   Registers: rax = the accumulator
;;;              rbx = the term added on this pass (grows by 5)
;;;              rcx = the countdown, tested explicitly rather than by `loop`
;;;   Loop shape: add, then TEST, then decrement -- note the test is in the
;;;              middle of the body, not at the end. That placement is what makes
;;;              this file's answer differ from sumloop.asm's.
;;; ----------------------------------------------------------------------------
main:
   mov rax, 0                           ;  rax use as accumulator
   mov rbx, 5                           ; rbx contains the number we have to sum up every stepjm
                                        ;   (rbx is callee-saved and is clobbered
                                        ;   without a push)
   mov rcx, 5                           ; rcx use as a counter for five numbers. at each stage it decremented
                                        ;   here rcx is an ordinary register -- no
                                        ;   instruction requires it
   cont:
      add rax, rbx                      ; accumulate this term
      cmp rcx, 0                        ; subtract 0 from rcx and keep only the flags:
                                        ;   ZF is set exactly when rcx is zero
      jz end                            ; jump if zero -- reads ZF, does no comparison
                                        ;   of its own. THE TEST IS HERE, in the
                                        ;   middle of the body: everything above it
                                        ;   has already run this pass.
      dec rcx                           ; one fewer to do. (`dec` sets ZF itself, so
                                        ;   `dec rcx ; jnz cont` would be the
                                        ;   idiomatic two-instruction tail.)
      add rbx, 5                        ; the next multiple of 5
      jmp cont                          ; unconditional jump back to the top: pure
                                        ;   rip change, nothing pushed
  end:
       nop                              ; the end -- AND NO `ret`. Running this file
                                        ;   therefore crashes; see the header.
