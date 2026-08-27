;;; ============================================================================
;;; countones.asm -- counting set bits with SHR and ADC ... and an off-by-one
;;; Practice session 2                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   It is meant to count the 1-bits in 0x0F0F0F0F0F0F0F0F, which is 32 of them.
;;;   IT DOES NOT. It leaves 92 in rax.
;;;   (Verified: rax = 0x5C = 92 at `done`.)
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` has no `ret`.
;;;
;;;   FIND THE BUG BEFORE YOU READ ON. The loop is only five instructions.
;;;
;;;   THE INTENDED MECHANISM is genuinely elegant, and worth understanding even
;;;   though this version is broken:
;;;       shr rdi, 1     shift right by one. The bit that falls off the bottom is
;;;                      not lost -- it lands in the CARRY FLAG.
;;;       adc eax, 0     ADD WITH CARRY: eax := eax + 0 + CF. So the bit that just
;;;                      fell off is added to the running total.
;;;   Repeat until the value is zero and you have counted every 1-bit, with no
;;;   comparison and no branch inside the body. `adc` is the instruction that
;;;   makes it work: it is normally used to chain additions across multiple
;;;   words (add the low halves, then `adc` the high halves so the carry
;;;   propagates), and here it is being used to harvest a single bit.
;;;
;;;   THE BUG: the file writes `adc eax, 1`, not `adc eax, 0`. So each pass adds
;;;   ONE PLUS the carry, and the result is
;;;       (number of iterations) + (number of 1-bits)
;;;   The loop runs until rdi becomes zero. The highest set bit of
;;;   0x0F0F0F0F0F0F0F0F is bit 59, so it takes 60 shifts, and there are 32 ones:
;;;       60 + 32 = 92.
;;;   Change the 1 to a 0, rebuild, and rax becomes 32. That one character is the
;;;   entire exercise.
;;;
;;;   A SECOND, SUBTLER POINT: the accumulator is `eax`, not `rax`. A 32-bit
;;;   write ZEROES the upper 32 bits of the register (see invert.asm in this
;;;   folder), so the first `adc eax, ...` silently clears the top half of rax.
;;;   Harmless here -- rax was set to 0 anyway -- but exactly the kind of thing
;;;   that bites when the accumulator started out holding something.
;;;
;;;   AND THE REAL ANSWER: modern x86 has a single instruction for this,
;;;       popcnt rax, rdi
;;;   which does the whole job in one cycle. The loop above is what you write
;;;   when you do not have it -- or what you write to understand what it does.
;;;
;;;   `test rdi, rdi` is the standard "is this register zero?" idiom: `test` is
;;;   an AND that discards its result and keeps only the flags, and x AND x is x,
;;;   so ZF ends up set exactly when rdi is zero. It is preferred over
;;;   `cmp rdi, 0` because it is one byte shorter.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   `main` has no `ret`, so running it is unreliable. To watch what happens:
;;;   ./asm "ps_code/2/countones.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/2/countones.asm"
;;;
;;;   Useful session -- watch the value drain away one bit at a time:
;;;     display/x $rdi
;;;     display/d $rax
;;;     break countones.asm:NN    NN on the `adc eax, 1` line
;;;     c
;;;     info registers eflags     CF holds the bit that just fell off rdi
;;;     si
;;;     p $rax                    it went up by 1, or by 2 if CF was set
;;;     c                         again
;;;
;;;   Prove the diagnosis without editing the file -- count the iterations and
;;;   the ones separately:
;;;     break countones.asm:NN    NN on the `shr rdi, 1` line
;;;     ignore 1 1000             never stop, just tally
;;;     c                         run to completion
;;;     info breakpoints          hit count = 60, the number of shifts
;;;     # and 92 - 60 = 32, which is the popcount. There is your bug.
;;;
;;;   Or ask gdb directly:
;;;     p __builtin_popcountll(0x0F0F0F0F0F0F0F0FULL)     32
;;;
;;;   Then fix it: change `adc eax, 1` to `adc eax, 0`, rebuild, and rerun. rax
;;;   should now be 32.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing happens on the stack -- but this file teaches something better:
;;;   HOW TO LOCATE A BUG WITH gdb RATHER THAN BY STARING.
;;;
;;;   The method above is worth generalising. You had one wrong number (92) and
;;;   no idea where it came from. Instead of re-reading the code, you asked the
;;;   debugger to count something you could reason about -- how many times the
;;;   loop ran -- and the difference between the two numbers named the bug
;;;   exactly. `break` + `ignore N` + `info breakpoints` is a counter you can
;;;   attach to any line of any program, and it costs nothing to try.
;;;
;;;   The same trick answers questions all over this course:
;;;     * how many times is `fib` really called in code-0013.asm? (break fib,
;;;       ignore, run, info breakpoints -- and watch it explode with n)
;;;     * how many candidates does code-0020.asm test before finding 1000 primes?
;;;     * how many passes does bubble sort make in code-0021.asm on sorted input
;;;       versus reversed input?
;;;   Each of those is a one-line experiment that turns an argument about
;;;   complexity into a measurement.
;;;
;;;   As everywhere in this folder, the return address sits untouched at [rsp]
;;;   because there is no `ret`:
;;;       break main
;;;       info symbol *(long*)$rsp
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

;;; ----------------------------------------------------------------------------
;;; main -- count the 1-bits of a constant. CONTAINS A DELIBERATE-LOOKING BUG.
;;;   Receives : nothing
;;;   Returns  : rax = 92, where the correct popcount is 32 -- see the header
;;;   Clobbers : rax, rdi
;;;   Registers: rdi = the value being drained, one bit at a time
;;;              eax = the running count (note: the 32-bit name -- see the header)
;;; ----------------------------------------------------------------------------
main:
  mov rdi, 0x0f0f0f0f0f0f0f0f           ; the value to examine: alternating nibbles of
                                        ;   0000 and 1111, so exactly 32 bits are set.
                                        ;   Its highest set bit is bit 59.
   mov rax, 0                           ; the running count starts at zero
  cont:
       test rdi, rdi                    ; `test x, y` = AND, keeping ONLY the flags.
                                        ;   x AND x is x, so ZF ends up set exactly
                                        ;   when rdi is zero. The idiomatic "is this
                                        ;   register zero?" -- shorter than `cmp rdi, 0`.
      jz done                           ; every bit has been shifted out: stop
      shr rdi, 1                        ; SHift Right by one. Every bit moves down one
                                        ;   position, and THE BIT THAT FALLS OFF THE
                                        ;   BOTTOM LANDS IN THE CARRY FLAG. That is
                                        ;   how the next instruction can see it.
      adc eax, 1                        ; ADd with Carry: eax := eax + 1 + CF.
                                        ;   *** THE BUG. *** It should be
                                        ;   `adc eax, 0`, which would add just the
                                        ;   captured bit. As written it also adds 1
                                        ;   per iteration, so the answer is
                                        ;   60 iterations + 32 ones = 92.
                                        ;   (Also note `eax`: a 32-bit write zeroes
                                        ;   the upper half of rax -- see invert.asm.)
      jmp cont                          ; round again
  done:
     nop                                ; the end -- AND NO `ret`.
