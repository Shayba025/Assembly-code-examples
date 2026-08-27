;;; ============================================================================
;;; fib.asm -- ten steps of the Fibonacci recurrence, in registers
;;; Practice session 1                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Runs the Fibonacci step ten times and leaves 144 in rax. Nothing is printed
;;;   -- like everything in this folder it is meant to be SINGLE-STEPPED IN gdb.
;;;   (Verified: rax = 0x90 = 144 when it reaches `end`.)
;;;
;;;   *** RUNNING IT SEGFAULTS, AND THAT IS EXPECTED. *** `main` has no `ret`.
;;;
;;;   THE IDEA: Fibonacci needs two values at once, and each step turns the pair
;;;   (a, b) into (b, a+b). The body here does it in four moves:
;;;       mov r8, r9        r8 := b
;;;       mov r9, rax       r9 := the previous result
;;;       add r8, r9        r8 := b + previous
;;;       mov rax, r8       keep it in rax as well
;;;   Compare code-0012.asm in "lectures code ", which does the whole step with
;;;   ONE instruction:
;;;       xadd rbx, rax     ; (rbx, rax) <- (rbx + rax, rbx)
;;;   `xadd` (eXchange and ADD) supplies the temporary in hardware. Four
;;;   instructions become one. Reading the two files together is the exercise.
;;;
;;;   WHERE THE SEQUENCE ACTUALLY STARTS. The setup looks like it seeds 0 and 1,
;;;   but the first thing the body does is overwrite both r8 and r9, so the 0 is
;;;   never used. The values that come out of rax are
;;;       2, 3, 5, 8, 13, 21, 34, 55, 89, 144
;;;   -- ten steps, starting from 2, not the 0, 1, 1, 2, ... you might expect.
;;;   Trace it once by hand and confirm; then decide how you would fix the
;;;   initialisation to make ten steps produce fib(0) .. fib(9). That question is
;;;   the real content of this exercise.
;;;
;;;   WHY r8 AND r9 AND NOT rbx AND rdx: r8 through r15 are the "new" registers
;;;   added by x86-64, and r8-r11 are CALLER-SAVED -- free to clobber. rbx and
;;;   r12-r15 are callee-saved and would have to be pushed and popped. Choosing
;;;   scratch registers from the caller-saved set is exactly the right instinct.
;;;
;;;   `loop` again: decrement rcx, jump if rcx is then non-zero. The counter must
;;;   be rcx, it tests after decrementing (rcx = 0 on entry gives 2^64
;;;   iterations), and it leaves the flags alone.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   Don't -- see above. To watch it fail:
;;;   ./asm "ps_code/1/fib.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/1/fib.asm"
;;;
;;;   Useful session:
;;;     display/d $r8             one of the pair
;;;     display/d $r9             the other
;;;     display/d $rax            the current answer
;;;     display/d $rcx            the countdown
;;;     si si si si               past the setup
;;;   Then hold `si` and read rax after each `mov rax, r8`:
;;;       2, 3, 5, 8, 13, 21, 34, 55, 89, 144
;;;
;;;   Watch a single step of the recurrence in slow motion:
;;;     break fib.asm:NN          NN on the `mov r8, r9` line
;;;     c
;;;     info registers r8 r9 rax  the state going in
;;;     si si si si               the four instructions of the body
;;;     info registers r8 r9 rax  the state coming out -- compare with (b, a+b)
;;;
;;;   And convince yourself the initial 0 is dead:
;;;     break main
;;;     si                        mov r8, 0
;;;     p $r8                     0
;;;     break fib.asm:NN          NN on the `mov r9, rax` line
;;;     c
;;;     p $r8                     1 -- the 0 was overwritten before it was ever read
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing happens on it. `p $rsp` is identical at the first instruction and
;;;   at `end:` -- the entire computation lives in four registers, because no
;;;   function is called from inside the loop.
;;;
;;;   THAT IS THE CONTRAST THIS FOLDER IS BUILDING TOWARDS. Look at code-0013.asm
;;;   in "lectures code ", which computes Fibonacci RECURSIVELY. Break on `fib`
;;;   there, run with n = 20, and type `bt`: a stack of frames, one per level of
;;;   the current path, with results being spilled to memory between the two
;;;   recursive calls because there is only one rax. Then come back here, where
;;;   the same answer costs zero bytes of stack and ten iterations.
;;;
;;;   Two ways to compute Fibonacci, differing by a factor of millions in time
;;;   and by all of the stack in space, and the difference is entirely in which
;;;   values you choose to keep alive at once. That question -- how many things
;;;   must be live simultaneously -- is what decides whether an algorithm fits in
;;;   registers or needs a stack, and it is worth asking about every loop you
;;;   ever write.
;;;
;;;   The return address is still on the stack, unused, at `end:`:
;;;       break main
;;;       info symbol *(long*)$rsp
;;;   Add `ret` after the final `nop` to actually go home.
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

;;; ----------------------------------------------------------------------------
;;; main -- ten steps of the Fibonacci recurrence.
;;;   Receives : nothing
;;;   Returns  : rax = 144 -- but there is no `ret`, so nobody collects it
;;;   Registers: r8, r9 = the running pair
;;;              rax    = a copy of the newest value
;;;              rcx    = the countdown, because `loop` insists on rcx
;;;   Invariant: after each pass, rax holds the newest term and r9 the one before.
;;;              Note the initial r8 = 0 is dead -- see the header.
;;; ----------------------------------------------------------------------------
main:
   mov r8, 0                            ;  0 is the first number of fibonaci series
                                        ;   ...but it is overwritten by the first
                                        ;   instruction of the body before it is ever
                                        ;   read. Dead code; see the header.
   mov  r9, 1                           ; 1 is the second number
                                        ;   (r8-r11 are CALLER-saved, so they are free
                                        ;   scratch -- no push/pop needed)
   mov rax, 1                           ; the "previous result" the first pass will
                                        ;   fold in, which is what actually seeds the
                                        ;   sequence
   mov rcx, 10                          ; rcx use as a counter for 10  numbers. at each stage it decremented
                                        ;   the register is not a choice: `loop` uses
                                        ;   rcx and nothing else
   cont:
      mov r8, r9                        ; slide the pair along: r8 := the newer of the
                                        ;   two old values
      mov r9, rax                       ; r9 := the previous result
      add r8, r9                        ; r8 := their sum -- the new Fibonacci number.
                                        ;   `add dst, src` means dst := dst + src.
      mov  rax, r8                      ; keep the answer in rax as well, ready for
                                        ;   the next pass. FOUR INSTRUCTIONS where
                                        ;   `xadd` would do (see the header).
      loop cont                         ; decrement rcx, jump back while non-zero.
                                        ;   Ten passes, so rax ends at 144.
  end:
       nop                              ; the end -- AND NO `ret`. Running this file
                                        ;   therefore crashes; see the header.
