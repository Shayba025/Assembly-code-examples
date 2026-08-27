;;; ============================================================================
;;; factorial.asm -- 10! with the one-operand MUL instruction
;;; Practice session 1                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Computes 10! = 3628800 and leaves it in rax. Nothing is printed -- like
;;;   everything in this folder it is meant to be SINGLE-STEPPED IN gdb.
;;;   (Verified: rax = 0x375F00 = 3628800 when it reaches `done`.)
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` has no
;;;   `ret`, so after the final `nop` the CPU decodes whatever bytes follow.
;;;   Adding `ret` at `done:` is the fix, and a good first exercise.
;;;
;;;   THE INSTRUCTION THIS FILE IS ABOUT -- `mul rcx`:
;;;       RDX:RAX  :=  RAX * rcx
;;;   It takes ONE operand and has TWO hidden registers. It always multiplies
;;;   rax; it always writes the 128-bit product across rdx (high half) and rax
;;;   (low half). You do not get to choose either. It is UNSIGNED -- the signed
;;;   twin is `imul`, which also has friendlier two- and three-operand forms
;;;   (`imul rax, rcx` / `imul rax, rcx, 7`) that most code uses instead.
;;;
;;;   WHY THE 128-BIT RESULT: multiplying two 64-bit numbers can produce up to
;;;   128 bits, so the hardware gives you all of them rather than silently
;;;   truncating. Here rdx stays zero throughout, because 10! is small -- but
;;;   `p $rdx` after each `mul` is exactly how you would detect overflow in a
;;;   program that mattered. (Compare code-0009 in "lectures code ", which
;;;   refuses inputs above 20 for precisely this reason: 21! does not fit.)
;;;
;;;   TWO THINGS IN THIS FILE ARE UNNECESSARY, AND BOTH ARE INSTRUCTIVE:
;;;
;;;   * `cqo` before the loop. It sign-extends rax into rdx, preparing a 128-bit
;;;     DIVIDEND. But `mul` never READS rdx -- it only writes it. `cqo` belongs
;;;     with `idiv`, not with `mul`. Prove it in gdb: poison rdx with
;;;     `set $rdx = 0xdeadbeef`, step the `mul`, and print rdx -- your poison is
;;;     gone, unread. Keep `cqo` firmly associated with DIVISION.
;;;
;;;   * The loop has TWO exit tests. `cmp rcx, 1 / jz done` at the top, and
;;;     `loop cont` at the bottom, which also stops when rcx reaches 0. The
;;;     top test always fires first (at rcx = 1), so the `loop`'s own test never
;;;     triggers -- it acts as a plain `dec rcx ; jmp cont`. Belt and braces.
;;;     Try deleting the `cmp`/`jz` pair and see what 10! becomes and why.
;;;
;;;   `loop` itself: decrement rcx, jump if rcx is then non-zero. The counter
;;;   must be rcx, it tests AFTER decrementing (so entering with rcx = 0 gives
;;;   you 2^64 iterations), and it does not disturb the flags.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   Don't rely on it -- see above. To watch what happens:
;;;   ./asm "ps_code/1/factorial.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/1/factorial.asm"
;;;
;;;   Useful session:
;;;     display/d $rax            the accumulating product
;;;     display/d $rcx            the counter
;;;     display/d $rdx            the high half of every product -- watch it stay 0
;;;     break factorial.asm:NN    NN on the `mul rcx` line
;;;     c
;;;     si                        one multiply
;;;     c                         the next
;;;   The sequence in rax is 1, 10, 90, 720, 5040, 30240, 151200, 604800,
;;;   1814400, 3628800.
;;;
;;;   Prove `mul` ignores rdx on input:
;;;     break factorial.asm:NN    NN on `mul rcx`
;;;     c
;;;     set $rdx = 0xdeadbeef     poison it
;;;     si                        execute the mul
;;;     p/x $rdx                  0 -- the poison was never read
;;;
;;;   And force an overflow, to see what rdx is for:
;;;     break factorial.asm:NN    NN on `mul rcx`
;;;     c
;;;     set $rax = 0xFFFFFFFFFFFFFFFF
;;;     si
;;;     p/x $rdx                  non-zero: the product did not fit in 64 bits.
;;;                               Checking rdx (or CF/OF) is how real code detects
;;;                               multiplication overflow.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing moves. `p $rsp` is the same at the first instruction and at `done:`
;;;   -- an iterative computation with no calls does not touch the stack at all.
;;;
;;;   THE COMPARISON WORTH MAKING is with code-0010.asm in "lectures code ",
;;;   which computes the same factorial RECURSIVELY. Open both in gdb, run each
;;;   with n = 10, and put a breakpoint at the innermost multiply in each:
;;;       here:       bt  ->  one frame,  p $rsp unchanged
;;;       code-0010:  bt  ->  eleven frames, p $rsp about 240 bytes lower
;;;   Identical answers, identical arithmetic, and one of them pays 24 bytes of
;;;   stack per level while the other pays nothing. That is the trade recursion
;;;   makes, and this pair of files is the cheapest way to see it.
;;;
;;;   Finally, the return address you are ignoring:
;;;       break main
;;;       info symbol *(long*)$rsp
;;;   Still there at `done:`, untouched, because this program has no `ret`. Add
;;;   one and the exit status becomes 3628800 modulo 256 -- which is 0, since
;;;   3628800 is divisible by 256. Worth checking with `echo $?`.
;;; ============================================================================

; factorial using MUL for calculating 10!

global main                             ; export `main` for the C library start-up.
                                        ;   No `section .text` -- NASM defaults to it.

;;; ----------------------------------------------------------------------------
;;; main -- compute 10! into rax.
;;;   Receives : nothing
;;;   Returns  : rax = 3628800 -- but there is no `ret`, so nobody collects it
;;;   Registers: rax = the running product (and mul's implicit operand)
;;;              rcx = the countdown 10, 9, ..., 1 (loop's implicit counter)
;;;              rdx = written by every `mul` with the high half of the product;
;;;                    stays zero because 10! is small
;;; ----------------------------------------------------------------------------
main:
    mov rcx, 10                         ; rcx contains 10 in order to get 10!
                                        ;   also the counter `loop` will decrement --
                                        ;   the register is not a free choice
    mov rax, 1                          ; rax is the accuulator
                                        ;   the empty product is 1
    cqo                                 ; "clean" rdx before multiplying
                                        ;   ...except `mul` never reads rdx, only
                                        ;   writes it, so this achieves nothing.
                                        ;   `cqo` prepares the 128-bit DIVIDEND for
                                        ;   `idiv`. See the header for the gdb
                                        ;   experiment that proves it.
cont:
     cmp rcx, 1                         ; subtract 1 from rcx, keep only the flags
     jz done                            ; jump if zero: multiplying by 1 is pointless,
                                        ;   so stop here. THIS is the exit that
                                        ;   actually fires.
     mul rcx                            ; RDX:RAX := RAX * rcx. One operand, two
                                        ;   hidden registers, UNSIGNED. The low 64
                                        ;   bits of the product land in rax -- our
                                        ;   accumulator -- and the high 64 in rdx,
                                        ;   which stays zero for inputs this small.
     loop cont                          ; decrement rcx and jump back while non-zero.
                                        ;   A SECOND exit test that never fires,
                                        ;   because the `jz` above always wins at
                                        ;   rcx = 1. Here it acts as `dec rcx; jmp`.

done:
     nop                                ; the end -- AND NO `ret`. rax holds 3628800.
                                        ;   Running the file is unreliable; see the
                                        ;   header.
