;;; ============================================================================
;;; is_even.asm -- MUTUAL RECURSION: two functions that call each other
;;; Practice session 5                       (study annotations added)
;;;
;;; WHAT THIS FILE IS
;;;   Two functions, `is_even(n)` and `is_odd(n)`, each defined in terms of the
;;;   other, and NO `main`. A C driver, `is_even_test.c`, sits next to it; the
;;;   ./asm and ./debug scripts link any <name>_test.c automatically.
;;;   (Verified: is_even(7) = 0, is_odd(7) = 1, matching C's `n % 2 == 0`.)
;;;
;;;   THE DEFINITION, which is the classic textbook example of mutual recursion:
;;;       is_even(0) = true                is_odd(0) = false
;;;       is_even(n) = is_odd(n-1)         is_odd(n) = is_even(n-1)
;;;   Neither function can be understood on its own -- each is only correct
;;;   because the other is. That is what "mutual" means, and it is why the two
;;;   must live in the same file (or at least be declared to each other).
;;;
;;;   *** IT IS AN ABSURDLY EXPENSIVE WAY TO TEST PARITY. *** `test rdi, 1` does
;;;   the same job in ONE instruction, with no calls at all -- see collatz.asm in
;;;   ps_code/3 and code-0015.asm in "lectures code ". This version costs n
;;;   nested calls and n stack frames. is_even(1000000) is a million frames deep
;;;   and WILL overflow the stack and crash. Keep n small, and treat the file as
;;;   a study of recursion rather than as a parity test.
;;;
;;;   HOW THE ANSWER TRAVELS BACK. This is the subtle part, and it is worth
;;;   tracing carefully. Neither function computes anything on the way out:
;;;       is_even:  ... call is_odd ; jmp .even_done ; .even_done: leave ; ret
;;;   There is no `mov rax, ...` after the call. The value in rax is simply
;;;   whatever the callee left there, and it is passed straight through, up
;;;   however many levels there are, until it reaches the original caller. Only
;;;   the two BASE CASES ever write to rax:
;;;       .even_base:  mov rax, 1        reached when is_even is called with 0
;;;       .odd_base:   mov rax, 0        reached when is_odd is called with 0
;;;   So the answer is decided entirely at the bottom of the recursion, and every
;;;   frame above it exists only to be unwound. Compare code-0010.asm's `fact`,
;;;   where every level multiplies on the way out and the frames are doing real
;;;   work.
;;;
;;;   `enter`-free prologue, `leave` epilogue: the functions use `push rbp` /
;;;   `mov rbp, rsp` on the way in and `leave` on the way out. `leave` is exactly
;;;   `mov rsp, rbp` + `pop rbp`.
;;;
;;;   A NOTE ON THE LABELS. `.even_base`, `.even_done` and `.odd_base`, `.done`
;;;   are LOCAL labels: a NASM name starting with '.' belongs to the most recent
;;;   non-local label. So `.done` inside `is_odd` is really `is_odd.done` and
;;;   cannot collide with anything in `is_even`. gdb shows them under those full
;;;   names -- try `info functions is_`.
;;;
;;;   THE FRAME IS ARGUABLY UNNECESSARY. Neither function has a local variable,
;;;   and neither reads its argument from the stack -- n arrives in rdi. The
;;;   prologue and epilogue are pure habit here, costing 16 bytes and four
;;;   instructions per level. Deleting them would work (the functions would still
;;;   need the return address, which `call` handles) and would halve the memory
;;;   cost. Try it and watch `p $rsp` between levels change from 16 to 8.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/5/is_even.asm"          # a table for n = 0..10
;;;   ./asm "ps_code/5/is_even.asm" 7
;;;   ./asm "ps_code/5/is_even.asm" 100
;;;
;;;   Now find the breaking point -- somewhere in the hundreds of thousands:
;;;   ./asm "ps_code/5/is_even.asm" 100000  ; echo "exit status = $?"
;;;   ./asm "ps_code/5/is_even.asm" 10000000 ; echo "exit status = $?"
;;;   A status of 139 means SIGSEGV: the stack ran out. That is not a bug in the
;;;   code -- it is the honest cost of one frame per unit.
;;;
;;; DEBUG IT   -- this is the file to watch a stack grow in
;;;   ./debug "ps_code/5/is_even.asm" 5
;;;
;;;   THE session for this file:
;;;     break is_even
;;;     break is_odd
;;;     c  c  c  c                the two functions alternate, level by level
;;;     bt                        is_odd, is_even, is_odd, is_even, ... down to
;;;                               main in is_even_test.c. THE ALTERNATION IS
;;;                               VISIBLE IN THE BACKTRACE.
;;;     p $rdi                    n at this level -- one smaller each time
;;;
;;;   Measure the cost per level:
;;;     break is_even
;;;     c
;;;     p $rsp                    note it
;;;     c
;;;     p $rsp                    32 bytes lower -- two levels (even, odd), each
;;;                               costing 16: 8 for the return address, 8 for the
;;;                               saved rbp
;;;
;;;   Watch the answer being decided at the very bottom, and then just travelling:
;;;     break is_even.asm:NN      NN on the `mov rax, 1` line (.even_base)
;;;     break is_even.asm:NN      and on the `mov rax, 0` line (.odd_base)
;;;     c                         run all the way down
;;;     bt                        you are n frames deep
;;;     p $rax                    the answer, just written
;;;     finish                    unwind one level
;;;     p $rax                    UNCHANGED -- nothing on the way out touches it
;;;     finish  finish  finish    the same value, all the way up
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THIS IS THE CLEAREST DEMONSTRATION IN THE COURSE THAT STACK DEPTH IS A REAL
;;;   RESOURCE. Everything else you have recursed on has been logarithmic or
;;;   small: Hanoi is n deep, factorial is n deep with n <= 20, Fibonacci is n
;;;   deep. Here n is unbounded and the depth is exactly n, so you can actually
;;;   reach the limit from the command line.
;;;
;;;   Find it experimentally:
;;;       ./asm "ps_code/5/is_even.asm" 100000    ; echo $?
;;;       ./asm "ps_code/5/is_even.asm" 1000000   ; echo $?
;;;   The default stack on Linux is 8 MB, and each level here costs 16 bytes, so
;;;   the arithmetic says roughly 500,000 levels. Check whether your measured
;;;   breaking point matches the prediction -- and if it does, you have just
;;;   measured the size of your own stack with nothing but a parity function.
;;;
;;;   THE DEEPER POINT is about TAIL CALLS. Look at what `is_even` does after its
;;;   recursive call: `jmp .even_done`, then `leave`, then `ret`. It does NOTHING
;;;   with the returned value. A call in that position is a TAIL CALL, and a
;;;   compiler is allowed to replace it with a plain `jmp`, reusing the current
;;;   frame instead of building a new one. That single transformation would turn
;;;   this program from O(n) stack into O(1) stack and it would never overflow.
;;;   You have already seen the technique, under a different name: code-0005.asm's
;;;   `between` finishes with `jmp rcx` instead of returning, and its stack usage
;;;   is exactly zero however many times it runs.
;;;
;;;   Try it: replace
;;;       dec rdi / call is_odd / jmp .even_done   ... leave / ret
;;;   with
;;;       dec rdi / leave / jmp is_odd
;;;   Rebuild, and run it with 10000000. It will now answer instantly and never
;;;   grow the stack at all -- because control transfers sideways instead of
;;;   downwards. That is tail-call optimisation, done by hand, and seeing the
;;;   segfault disappear is the best possible argument for understanding it.
;;; ============================================================================

section .text                           ; the executable-code section
global is_even                          ; export both functions so the C driver can
global is_odd                           ;   call either. NOTE: no `global main` --
                                        ;   this file has no main() of its own.

;long is_even (long n)
; rdi = n
; return rax=1 if even and rax = 0 if odd

;;; ----------------------------------------------------------------------------
;;; is_even -- is n even? Defined in terms of is_odd.
;;;   C signature : long is_even(long n)
;;;   Receives    : rdi = n   (System V: the first argument is in rdi)
;;;   Returns     : rax = 1 if n is even, 0 if odd
;;;   Clobbers    : rax, rdi
;;;   Frame       : 16 bytes per level -- 8 for the return address, 8 for the
;;;                 saved rbp. There are no locals, so the frame is not strictly
;;;                 necessary; see the header.
;;;   Recursion   : is_even(0) = 1, is_even(n) = is_odd(n-1). Only the base case
;;;                 ever writes rax; every other level just passes it through.
;;;   WARNING     : depth is exactly n. Large n overflows the stack.
;;; ----------------------------------------------------------------------------
is_even:
   push rbp                             ; prologue: save the caller's frame pointer
   mov rbp,rsp                          ; anchor this activation
   cmp rdi, 0                           ; subtract 0 from n, keeping only the flags
   je .even_base                        ; THE BASE CASE: 0 is even
                                        ;recursive case : is_odd (n-1)
   dec rdi                              ; the argument for the other function: n-1
   call is_odd                          ; ask the OTHER function. Its answer arrives in
                                        ;   rax and we do nothing to it.
   jmp .even_done                       ; skip the base-case assignment

.even_base:
   mov rax, 1                           ; is_even(0) = 1 (true). ONE OF ONLY TWO PLACES
                                        ;   in the whole file that writes rax.
.even_done:
   leave                                ; epilogue: `mov rsp, rbp` + `pop rbp` in one
                                        ;   instruction
   ret                                  ; pop the return address into rip. rax is
                                        ;   whatever the callee left -- untouched.
;long is_odd (long n)
; rdi = n
; return rax=1 if odd  and rax = 0 if even

;;; ----------------------------------------------------------------------------
;;; is_odd -- is n odd? Defined in terms of is_even.
;;;   C signature : long is_odd(long n)
;;;   Receives    : rdi = n
;;;   Returns     : rax = 1 if n is odd, 0 if even
;;;   Clobbers    : rax, rdi
;;;   Recursion   : is_odd(0) = 0, is_odd(n) = is_even(n-1).
;;;   The mirror image of is_even above -- and neither is correct without the
;;;   other. Its local labels are `.odd_base` and `.done`, which are really
;;;   `is_odd.odd_base` and `is_odd.done` and so cannot clash with is_even's.
;;; ----------------------------------------------------------------------------
is_odd:
   push rbp                             ; prologue: save the caller's frame pointer
   mov rbp,rsp                          ; anchor this activation
   cmp rdi, 0                           ; n == 0?
   je .odd_base                         ; THE BASE CASE: 0 is not odd
                                        ;recursive case : is_even(n-1)
   dec rdi                              ; n-1
   call is_even                         ; ask the other function; its rax becomes ours
   jmp .done                            ; skip the base-case assignment

.odd_base:
   mov rax, 0                           ; is_odd(0) = 0 (false). The second and last
                                        ;   place in the file that writes rax.
.done:
   leave                                ; epilogue: rsp := rbp, then pop rbp
   ret                                  ; pop the return address into rip

