;;; ============================================================================
;;; collatz.asm -- storing a Collatz chain into an array
;;; Practice session 3                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Computes the Collatz chain of 7 and writes every term into the array `seq`,
;;;   leaving the number of terms in `count`. Nothing is printed.
;;;   (Verified: 17 terms -- 7, 22, 11, 34, 17, 52, 26, 13, 40, 20, 10, 5, 16,
;;;   8, 4, 2, 1 -- and count = 17.)
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` ends in
;;;   `nop`, with no `ret`, so the CPU walks off the end. Adding `ret` after the
;;;   `nop` is the fix. (array1.asm and array2.asm in this folder do have one.)
;;;
;;;   THE RULE: start from n. If n is 1, stop. If n is even, halve it. If n is
;;;   odd, replace it with 3n+1. Whether this always terminates is famously
;;;   unproven -- and famously true for every number anyone has tested.
;;;
;;;   COMPARE code-0015.asm IN "lectures code ", which computes the identical
;;;   chain and PRINTS it. The two files differ in exactly one respect, and it is
;;;   an important one:
;;;
;;;       code-0015.asm  prints each term, so it must call printf inside the
;;;                      loop -- which destroys rax -- so n has to be parked in a
;;;                      stack local ([rbp - 8*1]) before every call and reloaded
;;;                      after it.
;;;       collatz.asm    calls nothing, so n can simply live in rax for the whole
;;;                      run, and no stack local is needed at all.
;;;
;;;   That is the whole reason code-0015.asm has a frame and this file does not.
;;;   Read them side by side.
;;;
;;;   THE THREE INSTRUCTIONS WORTH KNOWING:
;;;       test rax, 1      AND with 1, keeping ONLY the flags. This isolates the
;;;                        lowest bit, so ZF is set exactly when n is EVEN. Much
;;;                        cheaper than dividing to find a remainder.
;;;       shr rax, 1       SHift Right logical by one: divides by 2, discarding
;;;                        the remainder. One cycle, versus roughly twenty for a
;;;                        `div`. Exact here because n is known even.
;;;       shl rax, 1       SHift Left by one: doubles. Combined with `add rax,
;;;                        rbx` (where rbx is the original n) and an `inc`, this
;;;                        computes 3n+1 without a multiply.
;;;
;;;   code-0015.asm does the odd case in ONE instruction instead of four:
;;;       lea rax, [rax + 2*rax + 1]     ; rax + 2*rax + 1 = 3n+1
;;;   `lea` computes an address expression and keeps the NUMBER rather than
;;;   dereferencing it, so the address unit does the arithmetic for free. Worth
;;;   rewriting this file that way as an exercise.
;;;
;;;   A REAL LIMIT WORTH NOTICING: `seq resq 100` holds 100 terms, and nothing
;;;   here checks the counter against that. Starting from 7 the chain is 17 long,
;;;   so it fits -- but 27 has a chain of 112 terms and would write 12 quadwords
;;;   PAST THE END of the array, straight over `count`. Try it: change
;;;   `start_value` to 27 and see what `count` ends up holding. That is the same
;;;   class of bug as the off-by-one in code-0020.asm, and this is a cheap place
;;;   to meet it.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   `main` has no `ret`, so running it is unreliable. To watch what happens:
;;;   ./asm "ps_code/3/collatz.asm" ; echo "exit status = $?"
;;;
;;;   The results live in memory, so use gdb.
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/3/collatz.asm"
;;;
;;;   Useful session:
;;;     break done
;;;     c
;;;     p (long)count             17
;;;     x/17gd &seq               the whole chain: 7 22 11 34 17 52 26 13 40
;;;                               20 10 5 16 8 4 2 1
;;;
;;;   Watch the parity test decide, one term at a time:
;;;     break collatz.asm:22      the `test rax, 1` line
;;;     c
;;;     p $rax                    the current term
;;;     si                        the test
;;;     info registers eflags     ZF set means EVEN
;;;     si                        the jnz -- taken only for odd numbers
;;;     c                         next term
;;;
;;;   And watch the array fill up as it goes:
;;;     break collatz.asm:16      the `mov qword [rdi], rax` line
;;;     c
;;;     p $rcx                    how many terms so far
;;;     p ($rdi - (long*)&seq)    the index -- same number, derived from the pointer
;;;     x/20gd &seq               the array, mostly still zero
;;;     c                         again, and watch it grow
;;;
;;;   Then break it deliberately:
;;;     # edit start_value to 27, rebuild, and:
;;;     break done
;;;     c
;;;     p (long)count             112 -- but the array only holds 100
;;;     x/2gd &count              you have overwritten memory past the array
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   The stack is completely idle: `p $rsp` at `main` and at `done` gives the
;;;   same value, and there is no prologue at all. THE INTERESTING QUESTION IS
;;;   WHY THIS FILE GETS AWAY WITH IT WHEN code-0015.asm DOES NOT.
;;;
;;;   Run both under gdb and compare what happens to rax around the middle of the
;;;   loop:
;;;       here            rax holds n from the first instruction to the last.
;;;                       Nothing can take it away, because nothing is called.
;;;       code-0015.asm   break on its `call printf`, `p $rax`, `finish`,
;;;                       `p $rax` -- destroyed. Hence
;;;                       `mov qword [rbp - 8*1], rax` before every call and
;;;                       `mov rax, qword [rbp - 8*1]` after it.
;;;
;;;   THE RULE THIS ILLUSTRATES, and it governs every program in the course: A
;;;   VALUE THAT MUST OUTLIVE A CALL CANNOT LIVE IN A CALLER-SAVED REGISTER. You
;;;   have now seen four different answers to that problem --
;;;       push/pop around the call         code-0002.asm
;;;       keep it in .data                 code-0003.asm  (and `count` here)
;;;       keep it in a stack local         code-0015.asm, code-0018.asm
;;;       make no calls at all             this file, code-0024.asm
;;;   -- and the last one is by far the cheapest when you can arrange it.
;;;
;;;   Note also where the OUTPUT lives. `seq` and `count` are in .bss, not on the
;;;   stack, precisely so they survive after `main` finishes and you can inspect
;;;   them. A stack local would be gone the moment the frame was released.
;;; ============================================================================

global main                             ; export `main` for the C library start-up

section .data                           ; initialised, writable data
start_value dq 7                        ; the series begins at 7
                                        ;   `dq` = define quadword, 8 bytes. Change
                                        ;   this to 27 to overflow the array -- see
                                        ;   the header.

section .bss                            ; zero-filled at load time, costs no file space
seq resq 100                            ; uninitialized array for series values
                                        ;   `resq 100` reserves 100 quadwords = 800
                                        ;   bytes. NOTHING CHECKS AGAINST THIS LIMIT.
count resq 1                            ; how many values are stored
                                        ;   ...and it sits immediately after `seq`, so
                                        ;   an overrun lands right here.

section .text                           ; the executable-code section

;;; ----------------------------------------------------------------------------
;;; main -- write the Collatz chain of start_value into seq, and its length into
;;;         count.
;;;   C equivalent : long n = start_value, i = 0;
;;;                  for (;;) { seq[i++] = n;
;;;                             if (n == 1) break;
;;;                             n = (n & 1) ? 3*n + 1 : n / 2; }
;;;                  count = i;
;;;   Receives : nothing
;;;   Returns  : nothing -- there is no `ret`. The answers are in memory.
;;;   Registers: rax = the current term n, alive for the whole run
;;;              rdi = a walking pointer into seq, stepping by 8
;;;              rcx = how many terms have been stored
;;;              rbx = scratch, used only to hold n while computing 3n+1
;;;   No prologue, no frame, no stack use at all -- possible only because nothing
;;;   is called. See the call-stack notes above.
;;; ----------------------------------------------------------------------------
 main:
    mov rax, [start_value]              ; current value
                                        ;   BRACKETS: load the CONTENTS of
                                        ;   start_value (7), not its address
    lea rdi, [seq]                      ;pointer to array
                                        ;   Load Effective Address: rdi := &seq. No
                                        ;   brackets-dereference here -- `lea` computes
                                        ;   the address and keeps it.
    xor rcx, rcx                        ; counter = 0
                                        ;   `xor r, r` is the idiomatic zeroing
        xor rbx, rbx                    ; clear the scratch register too. (rbx is
                                        ;   CALLEE-SAVED and is being clobbered without
                                        ;   a push -- harmless here, a real bug inside
                                        ;   a function that returns.)
Collatz_loop:
     mov qword [rdi], rax               ; store the current value in array
                                        ;   `qword` is REQUIRED: `[rdi]` alone does not
                                        ;   tell NASM how wide the store should be.
     inc rcx                            ; one more term recorded
     add rdi, 8                         ; advance the pointer by EIGHT, the size of one
                                        ;   quadword element. THE STEP IS THE ELEMENT
                                        ;   SIZE -- compare array1.asm (1) and
                                        ;   array2.asm (2).
     cmp rax, 1                         ; have we reached the end of the chain?
     je done                            ; 1 is the terminating value
     test rax, 1                        ; check if the number is odd
                                        ;   `test x, y` = AND keeping only the flags.
                                        ;   ANDing with 1 isolates the lowest bit, so
                                        ;   ZF is set exactly when n is EVEN.
     jnz odd_case                       ; ZF clear => the low bit was 1 => n is odd
even_case:
     shr rax, 1                         ; n := n / 2. SHift Right logical by one: every
                                        ;   bit moves down, the low bit falls off.
                                        ;   Exact, because n is known even here.
     jmp Collatz_loop
odd_case:
     mov rbx, rax                       ; keep a copy of n -- the next two instructions
                                        ;   are about to destroy it
     shl rax, 1                         ; rax := 2n. SHift Left by one doubles.
     add rax , rbx                      ; rax := 2n + n = 3n
     inc rax                            ; rax := 3n + 1
                                        ;   FOUR instructions. code-0015.asm does the
                                        ;   same in one: `lea rax, [rax + 2*rax + 1]`.
     jmp Collatz_loop
done:
    mov qword [count], rcx              ; publish the length. Stored in .bss so it
                                        ;   survives for you to inspect afterwards.
    nop                                 ; the end -- AND NO `ret`. Running this file
                                        ;   therefore crashes; see the header.
