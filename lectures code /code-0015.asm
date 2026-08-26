;;; ============================================================================
;;; code-0015.asm -- The Collatz Chain, computed iteratively
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; The Collatz Chain:
;;; ------------------
;;; Start with a number n > 0:
;;; If n = 1, print and terminate
;;; If n is even, print, divide by two, and loop
;;; If n is odd, print, multiply by 3, add 1, and loop
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints the Collatz chain of n, e.g. `6` gives
;;;       [6] → [3] → [10] → [5] → [16] → [8] → [4] → [2] → [1]
;;;   Whether this always terminates is famously unproven -- but the program
;;;   works for every n anyone has ever tried.
;;;
;;;   FOUR TECHNIQUES WORTH LEARNING HERE, and none of them is the arithmetic:
;;;
;;;   1. `test rax, 1` -- THE PARITY TEST. `test x, y` computes x AND y and
;;;      keeps only the flags, exactly as `cmp` does for subtraction. ANDing
;;;      with 1 isolates the lowest bit, so ZF is set precisely when that bit is
;;;      zero, i.e. when n is even. This is much cheaper than a division and is
;;;      the idiomatic way to ask "is this odd?" in any assembly language.
;;;
;;;   2. `shr rax, 1` -- HALVING BY SHIFTING. Shift-right-logical by one moves
;;;      every bit down one position, which divides by 2 and discards the
;;;      remainder. One cycle, versus roughly twenty for `div`. (Its signed
;;;      cousin is `sar`, which preserves the sign bit. `shr` is right here
;;;      because n is known positive.)
;;;
;;;   3. `lea rax, [rax + 2*rax + 1]` -- ARITHMETIC WITHOUT ADDING. `lea` means
;;;      Load Effective Address: it computes an address expression and stores
;;;      the RESULT rather than loading from memory. The address unit can do
;;;      base + scale*index + displacement for free, so this single instruction
;;;      computes rax + 2*rax + 1 = 3n+1. No memory is touched and no flags are
;;;      changed. Compilers use `lea` for small arithmetic constantly; learn to
;;;      read it as arithmetic, not as a memory access.
;;;
;;;   4. A NAMED STACK SLOT FOR A VALUE THAT MUST SURVIVE printf. n lives in
;;;      rax, printf destroys rax, and the loop needs n afterwards. So each pass
;;;      writes n to [rbp - 8*1] before the call and reads it back after. That
;;;      slot was created by `sub rsp, 8*1` in the prologue -- a local variable,
;;;      declared exactly the way a C compiler declares one.
;;;
;;;   NOTE THE THREE FORMAT STRINGS. The first term prints as `[6]`, every later
;;;   one as ` → [3]`, and a bare `\n` ends the line. That is how you get
;;;   separators BETWEEN items rather than after each one, without a special
;;;   case inside the loop -- the special case is hoisted out before it.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0015.asm" 6
;;;   ./asm "lectures code /code-0015.asm" 27      # famously long: 111 steps
;;;   ./asm "lectures code /code-0015.asm" 1       # the shortest chain
;;;   ./asm "lectures code /code-0015.asm" 0       # usage error
;;;   ./asm "lectures code /code-0015.asm" -5      # usage error
;;;
;;;   Count the steps instead of reading them:
;;;   ./asm "lectures code /code-0015.asm" 27 | tr '→' '\n' | wc -l
;;;
;;;   Find the longest chain under 1000 (this takes a moment):
;;;   for n in $(seq 1 1000); do
;;;       echo "$(./asm "lectures code /code-0015.asm" $n | tr -cd '[' | wc -c) $n"
;;;   done | sort -rn | head -3
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0015.asm" 6
;;;
;;;   Useful session:
;;;     break code-0015.asm:NN     put NN on the `test rax, 1` line
;;;     c
;;;     display/d $rax             show n after every step, automatically
;;;     si                         the test
;;;     info registers eflags      look for ZF -- set means even
;;;     si                         the branch
;;;     si                         either the lea or the shr
;;;     c                          next term of the chain
;;;
;;;   Prove `lea` is arithmetic, not memory access:
;;;     break code-0015.asm:NN     NN on the `lea rax, [rax + 2*rax + 1]` line
;;;     c
;;;     p $rax                     say 3
;;;     si
;;;     p $rax                     10 -- and no memory was read. Compare with
;;;                                `mov rax, [rax+...]`, which would have.
;;;
;;;   And watch the local variable do its job:
;;;     break printf
;;;     c
;;;     x/1gd $rbp-8               n, safely in the frame
;;;     finish
;;;     p $rax                     printf's character count -- n is GONE from rax
;;;     si                         the `mov rax, qword [rbp - 8*1]` that restores it
;;;     p $rax                     n is back
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Look at the professor's diagram in the prologue. It is the first one in
;;;   this course with a NEGATIVE offset:
;;;       [rbp + 8*1]  ret addr    <- pushed by `call`, belongs to the caller
;;;       [rbp + 8*0]  old rbp     <- pushed by the prologue
;;;       [rbp - 8*1]  temp        <- OURS, carved out by `sub rsp, 8*1`
;;;   Positive offsets reach backward into the caller's world; negative offsets
;;;   are your own private scratch space. `sub rsp, k` is how you claim k bytes
;;;   of it, and that is the entire implementation of local variables.
;;;
;;;   THE EXPERIMENT: break on `printf` inside the loop and type `bt`. Two
;;;   frames, every time, however long the chain. Then check the frame itself:
;;;       p $rbp        unchanged across the whole run
;;;       p $rsp        also unchanged, once the prologue is done
;;;   An iterative algorithm allocates its frame once and reuses it forever.
;;;   Compare code-0013, where each level of recursion built a new one.
;;;
;;;   THE SECOND EXPERIMENT -- why the slot must exist at all. Break on the
;;;   `mov qword [rbp - 8*1], rax` inside the loop, then:
;;;       p $rax              n
;;;       break printf
;;;       c
;;;       finish
;;;       p $rax              printf's return value: n has been destroyed
;;;       x/1gd $rbp-8        n, untouched, exactly where you left it
;;;   rax is caller-saved, so printf owes you nothing. The stack slot is the
;;;   promise you made to yourself. Notice that this is the same problem
;;;   code-0002 solved with `push`/`pop` and code-0003 solved with a `.data`
;;;   variable -- three files, three idioms, one underlying rule: A VALUE THAT
;;;   MUST OUTLIVE A CALL CANNOT LIVE IN A CALLER-SAVED REGISTER.
;;; ============================================================================

section .data                                      ; initialised, writable data
fmt_usage:
        db `Usage: code-0015 n, where 1 <= n\n\0`  ; the error message
fmt_first:
        db `[%lld]\0`                              ; the FIRST term: no separator in front of it.
                                                   ;   Note: no \n either -- the whole chain is one
                                                   ;   line, closed by fmt_end at the very end.
fmt_next:
        db ` → [%lld]\0`                           ; every LATER term, with the arrow separator built
                                                   ;   in. The → is UTF-8 (3 bytes); printf copies the
                                                   ;   bytes through without caring.
fmt_end:
        db `\n\0`                                  ; just a newline, to close the line

extern printf, fprintf, atoll, exit, stderr        ; supplied by the C library
global main                                        ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- print the Collatz chain of n.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 on bad input
;;;   Locals      : [rbp - 8*1] = n, parked across each printf call
;;;   Registers   : rax = the current term of the chain (between calls only)
;;;   How it works: prints the first term specially, then loops -- test for 1,
;;;                 test parity, apply 3n+1 or n/2, print with the separator
;;;                 format, repeat. The value of n is written to the frame
;;;                 before every printf and reloaded after it.
;;; ----------------------------------------------------------------------------
main:
        push rbp                                   ; back up the frame-pointer (rbp is callee-saved)
        mov rbp, rsp                               ; set fp to the base of current frame -- the anchor
        sub rsp, 8*1                               ; temporary storage. Moves rsp DOWN 8 bytes, which
                                                   ;   ALLOCATES one quadword of local space. This is
                                                   ;   literally how `long long temp;` is compiled.
        and rsp, -16                               ; align the rsp on the 16 byte boundary. Done AFTER
                                                   ;   the sub, so the slot at [rbp-8] is already
                                                   ;   reserved; rounding rsp further down can only
                                                   ;   move away from it.

;;; The Activation Frame:
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | temp     | qword [rbp - 8*1] |
                                                   ; The first frame diagram in this course with a
                                                   ;   NEGATIVE offset. Positive = the caller's doing;
                                                   ;   negative = your own locals.

        cmp rdi, 2                                 ; argc == 2 -- subtract, keep only the flags
        jne .usage                                 ; print usage if not

        mov rdi, qword [rsi + 8*1]                 ; get argv[1]: rsi is argv, base+8*1 is element 1
        call atoll                                 ; convert to a 64-bit integer -> rax

        cmp rax, 1                                 ; invalid input: n < 1?
        jl .usage                                  ; print usage (`jl` = signed less-than; 0 and all
                                                   ;   negatives are rejected here)

        mov rdi, fmt_first                         ; format string for first term in the sequence --
                                                   ;   the one WITHOUT a leading arrow
        mov rsi, rax                               ; n (printf argument 2)
        mov qword [rbp - 8*1], rax                 ; backup. printf is about to destroy rax, so
                                                   ;   park n in the local slot first.
        mov rax, 0                                 ; no fp registers in use (the variadic rule)
        call printf
        mov rax, qword [rbp - 8*1]                 ; restore n from the slot -- printf left its own
                                                   ;   character count in rax

.loop:
        cmp rax, 1                                 ; base case: n == 1
        je .one                                    ; the chain ends here
        test rax, 1                                ; is even? `test x, y` = AND, flags only. ANDing
                                                   ;   with 1 isolates the lowest bit, so ZF is set
                                                   ;   exactly when n is even.
        jz .even                                   ; `jz` (== `je`) fires when ZF is set: n is even
        lea rax, [rax + 2*rax + 1]                 ; n <-- 3*n + 1
                                                   ;   `lea` computes an ADDRESS EXPRESSION and keeps
                                                   ;   the number instead of dereferencing it, so this
                                                   ;   is pure arithmetic: rax + 2*rax + 1. One
                                                   ;   instruction, no memory access, no flags touched.
        jmp .continue                              ; skip the even branch

.even:
        shr rax, 1                                 ; n <-- n/2. Shift-right-logical by one: every bit
                                                   ;   moves down a position, the low bit falls off.
                                                   ;   Exact here because n is known even. Far cheaper
                                                   ;   than `div`.

.continue:
        mov qword [rbp - 8*1], rax                 ; backup n -- again, before the call destroys rax
        mov rdi, fmt_next                          ; format string for middle term in the sequence --
                                                   ;   the one WITH the leading arrow
        mov rsi, rax                               ; n (printf argument 2)
        mov rax, 0                                 ; no fp registers in use
        call printf
        mov rax, qword [rbp - 8*1]                 ; restore n from backup
        jmp .loop                                  ; remain in loop

.one:
        mov rdi, fmt_end                           ; done: print a newline
        mov rax, 0                                 ; no fp registers in use
        call printf

.done:
        mov rax, 0                                 ; status OK for OS

        mov rsp, rbp                               ; restore original stack-pointer -- this frees the
                                                   ;   local slot and undoes the alignment in one go
        pop rbp                                    ; set fp to point to previous frame
        ret                                        ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; main.usage -- bad or missing argument. NEVER RETURNS.
;;;   Writes the usage line to stderr and terminates with status -1. Reached
;;;   from two tests: wrong argc, and n < 1.
;;; ----------------------------------------------------------------------------
.usage:
        mov rdi, qword [stderr]                    ; errors go to stderr. Brackets: `stderr` is a
                                                   ;   VARIABLE holding a FILE*; load its contents.
        mov rsi, fmt_usage                         ; explain correct usage (fprintf's argument 2)
        mov rax, 0                                 ; no fp registers in use
        call fprintf                               ; send output to stderr...

        mov rax, -1                                ; status NOT OK
        call exit                                  ; exit as per error. Never returns.

section .note.GNU-stack noalloc noexec             ; required Linux marker: stack is not exec
