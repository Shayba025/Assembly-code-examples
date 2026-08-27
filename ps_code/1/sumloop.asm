;;; ============================================================================
;;; sumloop.asm -- summing 5 + 10 + 15 + 20 + 25 with the `loop` instruction
;;; Practice session 1                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Adds the first five multiples of 5 (5+10+15+20+25 = 75) and leaves the
;;;   answer in rax. Nothing is printed -- like every file in this folder it is
;;;   meant to be SINGLE-STEPPED IN gdb, not run.
;;;
;;;   *** RUNNING IT SEGFAULTS, AND THAT IS EXPECTED. *** `main` has no `ret`, so
;;;   after the final `nop` the CPU decodes whatever bytes follow. Adding `ret`
;;;   at `end:` fixes it, and is a good exercise.
;;;
;;;   THE INSTRUCTION THIS FILE IS ABOUT:
;;;       loop <label>    decrement rcx; if rcx is now non-zero, jump to <label>
;;;   Three things follow from that one sentence, and all three catch people out:
;;;
;;;   1. THE COUNTER IS ALWAYS rcx. Not a register you choose -- rcx, wired into
;;;      the instruction. The `c` in rcx does stand for "counter".
;;;   2. IT DECREMENTS BEFORE IT TESTS. So entering the loop with rcx = 0 does
;;;      NOT skip it: rcx wraps to 0xFFFFFFFFFFFFFFFF and you get 2^64 - 1
;;;      iterations. `loop` is a do-while, never a while. (This is the trap the
;;;      lecture files code-0009 and code-0012 guard against with an explicit
;;;      `cmp rcx, 0` before the loop.)
;;;   3. IT DOES NOT TOUCH THE FLAGS. The decrement of rcx sets nothing, so any
;;;      flags set inside the body survive to the next instruction.
;;;
;;;   COMPARE sumjump.asm IN THIS SAME FOLDER. It computes the same sum with an
;;;   explicit `cmp` / `jz` / `dec` / `jmp` -- four instructions where `loop` is
;;;   one -- and it gets a different answer, because its test sits in a different
;;;   place. Read the two side by side; that comparison is the exercise.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   Don't -- see above. If you want to watch it fail:
;;;   ./asm "ps_code/1/sumloop.asm" ; echo "exit status = $?"
;;;
;;;   The linker also warns about a missing .note.GNU-stack section; these
;;;   practice files omit the marker that every "lectures code " file ends with.
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/1/sumloop.asm"
;;;
;;;   Useful session:
;;;     display/d $rax            the accumulator
;;;     display/d $rbx            the value being added
;;;     display/d $rcx            the counter
;;;     si  si  si                past the three setup instructions
;;;     si si si                  one pass of the loop body
;;;   Now just hold down `si` and read the three numbers after each step:
;;;       rax:  0   5   15  30  50  75
;;;       rbx:  5  10   15  20  25  30
;;;       rcx:  5   4    3   2   1   0
;;;   Note that rbx is incremented one extra time, on the last pass, after it is
;;;   no longer needed -- harmless, and typical of hand-written loops.
;;;
;;;   Prove that `loop` decrements before testing:
;;;     break sumloop.asm:NN      NN on the `loop cont` line
;;;     c
;;;     set $rcx = 1
;;;     si                        rcx becomes 0, so the jump is NOT taken
;;;     # run it again, and this time:
;;;     set $rcx = 0
;;;     si                        rcx becomes 0xFFFFFFFFFFFFFFFF and the jump IS
;;;                               taken. There is your 2^64-iteration loop.
;;;     p/x $rcx
;;;
;;;   And prove `loop` leaves the flags alone:
;;;     info registers eflags     before the `loop`
;;;     si
;;;     info registers eflags     unchanged, even though rcx changed
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing happens on it, and that is the observation. `p $rsp` at the first
;;;   instruction and at `end:` gives the same value: a loop does not grow the
;;;   stack, however many times it goes round. All the state -- accumulator,
;;;   addend, counter -- lives in registers, which is possible only because
;;;   nothing is called from inside the body. The moment you add a `call printf`
;;;   in there, rax, rcx and every other caller-saved register stop being safe,
;;;   and you need the push/pop or memory-variable idioms from code-0002,
;;;   code-0003 and code-0018.
;;;
;;;   The other thing worth looking at is the return address you are ignoring:
;;;       break main
;;;       x/1gx $rsp
;;;       info symbol *(long*)$rsp
;;;   That is where `ret` would have taken you. This program never uses it, walks
;;;   off the end of itself instead, and crashes. Add `ret` after the `nop` and
;;;   watch the same address take you home -- with 75 as the exit status, since
;;;   rax is what the shell receives.
;;; ============================================================================

global main                             ; export `main` for the C library start-up.
                                        ;   No `section .text` here -- NASM defaults
                                        ;   to it, so the code lands in the right
                                        ;   place anyway.

;;; ----------------------------------------------------------------------------
;;; main -- sum 5 + 10 + 15 + 20 + 25 with a counted loop.
;;;   Receives : nothing
;;;   Returns  : rax = 75 -- but there is no `ret`, so nobody collects it
;;;   Registers: rax = the accumulator
;;;              rbx = the value added on this pass (grows by 5 each time)
;;;              rcx = the countdown, because `loop` insists on rcx
;;; ----------------------------------------------------------------------------
main:
   mov rax, 0                           ;  rax use as accumulator
                                        ;   the empty sum is zero
   mov rbx, 5                           ; rbx contains the number we have to sum up every stepjm
                                        ;   the first term. (rbx is callee-saved and
                                        ;   is clobbered without a push.)
   mov rcx, 5                           ; rcx use as a counter for five numbers. at each stage it decremented
                                        ;   NOT a free choice: `loop` uses rcx and
                                        ;   nothing else.
   cont:
      add rax, rbx                      ; accumulate this term. `add dst, src` means
                                        ;   dst := dst + src.
      add rbx, 5                        ; the next multiple of 5, ready for the next
                                        ;   pass (also done once too often, on the
                                        ;   final pass -- harmless)
      loop cont                         ; decrement rcx, and jump back if it is still
                                        ;   non-zero. ONE instruction doing the work
                                        ;   of `dec rcx` + `jnz cont` -- and it does
                                        ;   NOT disturb the flags.
  end:
     nop                                ; the end -- AND NO `ret`. Running this file
                                        ;   therefore crashes; see the header. rax
                                        ;   holds 75 at this point.
