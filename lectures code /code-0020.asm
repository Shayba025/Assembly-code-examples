;;; ============================================================================
;;; code-0020.asm -- Finding the first COUNT prime numbers
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Builds a table of the first 1000 primes by trial division and prints them
;;;   as pi(0) = 2, pi(1) = 3, pi(2) = 5, ...
;;;
;;;   THE ALGORITHM IS SMARTER THAN IT LOOKS. To test a candidate c, you only
;;;   need to try primes p with p*p <= c -- if c had a factor larger than its
;;;   square root, the matching co-factor would be smaller and you would have
;;;   found it already. So the inner loop stops as soon as p*p > c, and it stops
;;;   WITHOUT computing a square root, by keeping a SECOND TABLE of the primes
;;;   already squared. Squares are computed once, when a prime is discovered,
;;;   and looked up thereafter. That is a classic space-for-time trade.
;;;
;;;   Two more small economies: candidates step by 2 (evens cannot be prime past
;;;   2), and the tables are seeded with 2 and 3 so the loop never has to
;;;   special-case them.
;;;
;;;   THE ARRAY IDIOM TO LEARN:
;;;       mov rcx, qword [primes_table + 8*rbx]
;;;   base + 8*index in a single addressing mode, with the 8 being sizeof(qword).
;;;   This is what `a[i]` compiles to, and the scale factor is where the element
;;;   size lives.
;;;
;;;   THE INSTRUCTION TO STUDY -- `div`:
;;;       cqo          ; rdx:rax := sign-extension of rax
;;;       div rcx      ; rax := rdx:rax / rcx  ,  rdx := rdx:rax % rcx
;;;   `div` is unsigned, one-operand, and uses THREE hidden registers: it reads
;;;   the 128-bit dividend in RDX:RAX and writes the quotient to RAX and THE
;;;   REMAINDER TO RDX. Testing `rdx == 0` for divisibility is therefore free --
;;;   you were going to compute it anyway. THE TRAP: you must set rdx before
;;;   dividing, or `div` will use whatever junk is there and usually raise a
;;;   #DE exception. Note that `cqo` is the SIGNED preparation and `div` is the
;;;   UNSIGNED divide -- a mismatch that is harmless only because candidates are
;;;   positive. `xor rdx, rdx` is the correct pairing for `div`; `cqo` pairs
;;;   with `idiv`.
;;;
;;;   *** A REAL BUG IN THIS FILE, AND YOU CAN SEE IT IN gdb ***
;;;   `primes_table` holds exactly COUNT quadwords, so its valid indices are
;;;   0 .. COUNT-1. But the outer loop's guard is
;;;       cmp last_prime_index, COUNT ; jge .done
;;;   which still permits one more prime when last_prime_index == COUNT-1. That
;;;   pass writes to index COUNT -- ONE PAST THE END. Since `primes_square_table`
;;;   is declared immediately afterwards, the stray write lands in
;;;   primes_square_table[0], replacing the seed value 4 with 7927. The program
;;;   prints 1001 primes rather than 1000 and gets away with it only because the
;;;   fill loop has already finished by then. Verified:
;;;       (gdb) p (long)((char*)&primes_square_table - (char*)&primes_table)
;;;       $1 = 8000                       <- exactly COUNT * 8
;;;       (gdb) break print_primes_table
;;;       (gdb) c
;;;       (gdb) x/2gd &primes_square_table
;;;       0x405f71 <primes_square_table>: 7927   9      <- should read 4  9
;;;   THE FIX is to compare against COUNT - 1, or to size the tables COUNT + 1.
;;;   This is the classic off-by-one buffer overflow, in eleven instructions.
;;;
;;;   A SMALLER ONE: rbx and rcx are used as scratch throughout, and rbx is
;;;   CALLEE-SAVED. Neither function pushes it.
;;;
;;;   THE `db 0xcf, 0x80` AT THE TOP is the UTF-8 encoding of the Greek letter
;;;   pi, written as raw bytes because NASM source is easier to keep ASCII.
;;;   Bytes are bytes; printf copies them through untouched.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0020.asm" | head -20
;;;   ./asm "lectures code /code-0020.asm" | tail -5
;;;   ./asm "lectures code /code-0020.asm" | wc -l        # 1001 -- see the bug
;;;
;;;   Check a few against a known list:
;;;   ./asm "lectures code /code-0020.asm" | sed -n '1p;10p;100p;1000p'
;;;
;;;   Change `COUNT equ 1000` at the top to make bigger or smaller tables.
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0020.asm"
;;;
;;;   Useful session -- watch one candidate being tested:
;;;     break code-0020.asm:NN     put NN on the `div rcx` line
;;;     c
;;;     x/1gd $rbp-8               the candidate
;;;     p $rcx                     the prime we are dividing by
;;;     si                         execute the div
;;;     p $rax                     the quotient
;;;     p $rdx                     THE REMAINDER -- zero means composite
;;;
;;;   Watch the sqrt cut-off:
;;;     break code-0020.asm:NN     NN on the `cmp rcx, rax` in .L2
;;;     c
;;;     p $rcx                     prime^2, from the squares table
;;;     x/1gd $rbp-8               the candidate. When rcx > candidate, done.
;;;
;;;   And see the bug with your own eyes:
;;;     p (long)((char*)&primes_square_table - (char*)&primes_table)
;;;     break print_primes_table
;;;     c
;;;     x/2gd &primes_square_table       first value should be 4, and is not
;;;     p (long)last_prime_index         1000, but the last valid index is 999
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   The interesting contrast in this file is between the two KINDS of memory
;;;   it uses, and where each belongs.
;;;
;;;   * `candidate` and `index` are per-invocation scratch. They live in the
;;;     frame, at [rbp - 8*1] and [rbp - 8*2], created by `sub rsp, 8*2`, and
;;;     they cease to exist at `ret`.
;;;   * `primes_table`, `primes_square_table` and `last_prime_index` must
;;;     outlive `fill_primes_table` so that `print_primes_table` can read them.
;;;     They are in .data. A stack frame could not have held them.
;;;
;;;   Watch the handover in gdb:
;;;       break fill_primes_table
;;;       c
;;;       p $rbp                     note the value
;;;       finish                     the whole fill runs and returns
;;;       break print_primes_table
;;;       c
;;;       p $rbp                     THE SAME ADDRESS -- the second function
;;;                                  reuses the exact stack space the first one
;;;                                  gave back
;;;       p (long)last_prime_index   ...and yet the data survived, because it
;;;                                  was never on the stack
;;;   Two functions, one stack address, no interference: that is the whole
;;;   argument for the distinction between automatic and static storage, and you
;;;   can watch it happen in two commands.
;;;
;;;   Also note that neither function takes arguments and neither returns a
;;;   value -- they communicate entirely through globals. That is fine for a
;;;   1000-line program and disastrous for a 100000-line one, and it is worth
;;;   asking yourself, while reading `fill_primes_table`, how you would rewrite
;;;   it to take (table, squares, count) as three stack arguments instead. The
;;;   frame diagram would gain three positive-offset rows, and `print` would
;;;   stop depending on `fill` having run first.
;;;
;;;   Finally, `bt` inside either function shows two frames, never more: this is
;;;   flat, iterative code. Compare code-0017, where the same command showed a
;;;   frame per disk.
;;; ============================================================================

        COUNT equ 1000                                ; `equ` = assemble-time constant: how many primes
                                                      ;   to find. Note the tables below are sized from
                                                      ;   it -- and see the off-by-one note in the header.

section .data                                         ; initialised, writable data
fmt_prime_n:
        db 0xcf, 0x80, `(%lld) = %lld\n\0`
                                                      ; 0xcf 0x80 is the UTF-8 encoding of the Greek
                                                      ;   letter pi, emitted as raw bytes so the source
                                                      ;   stays ASCII. Then the printable format:
                                                      ;   two 64-bit decimals, the index and the prime.
last_prime_index:
        dq 1                                          ; the highest index currently filled in. Starts at
                                                      ;   1 because two primes are seeded below.
primes_table:
        dq 2, 3                                       ; seed the table with the first two primes, so the
                                                      ;   loop never needs a special case for them
        times (COUNT - 2) dq 0                        ; `times k <directive>` repeats the directive k
                                                      ;   times at assembly time. This reserves the
                                                      ;   remaining COUNT-2 slots, zero-filled. Total
                                                      ;   size: COUNT quadwords, indices 0..COUNT-1.
primes_square_table:
        dq 4, 9                                       ; the squares of the seeded primes: 2^2 and 3^2.
                                                      ;   Keeping squares avoids ever computing a square
                                                      ;   root in the primality test.
        times (COUNT - 2) dq 0                        ; and COUNT-2 more slots. NOTE: this table starts
                                                      ;   exactly COUNT*8 = 8000 bytes after
                                                      ;   primes_table, which is why the off-by-one write
                                                      ;   described in the header lands right here.

extern printf                                         ; supplied by the C library
global main                                           ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- fill the table, then print it.
;;;   C signature : int main(void)
;;;   Returns     : rax = whatever print_primes_table left (it sets 0)
;;;   How it works: two calls, no arguments, no return values -- the two helpers
;;;                 communicate entirely through the globals above.
;;; ----------------------------------------------------------------------------
main:
        push rbp                                      ; save old frame-pointer (rbp is callee-saved)
        mov rbp, rsp                                  ; set frame-pointer to base of new frame

        call fill_primes_table                        ; compute all COUNT primes into the .data tables
        call print_primes_table                       ; walk the table and print it

        mov rsp, rbp                                  ; restore the stack pointer from the anchor
        pop rbp                                       ; set frame-pointer to base of previous frame
        ret                                           ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; fill_primes_table -- trial-division sieve into primes_table.
;;;   Receives   : nothing (reads and writes the globals)
;;;   Returns    : nothing; the tables and last_prime_index are the output
;;;   Clobbers   : rax, rbx (CALLEE-SAVED, not preserved), rcx, rdx
;;;   Locals     : [rbp - 8*1] = candidate, [rbp - 8*2] = index into the tables
;;;
;;;   How it works: candidates walk upward by 2 from 3. For each candidate, the
;;;   inner loop divides by primes_table[1], [2], [3], ... For each divisor it
;;;   first checks primes_square_table[i] against the candidate:
;;;       square > candidate  =>  no divisor can exist below sqrt: PRIME
;;;       remainder == 0      =>  divisible: composite, next candidate
;;;       otherwise           =>  try the next prime
;;;   When a prime is found it is appended to both tables -- value and square --
;;;   and the search resumes.
;;;
;;;   *** Contains the off-by-one described in the file header: the guard
;;;   permits a write at index COUNT, one past the end of primes_table. ***
;;; ----------------------------------------------------------------------------
fill_primes_table:
        push rbp                                      ; save old frame-pointer
        mov rbp, rsp                                  ; set frame-pointer to base of new frame
        sub rsp, 8*2                                  ; reserve two local variables: moving rsp down 16
                                                      ;   bytes claims that much stack. No `and rsp,-16`
                                                      ;   is needed -- this function calls nothing.

;;; |        | old ret   | qword [rbp + 8*2] |
;;; | rbp -> | old rbp   | qword [rbp]       |
;;; |        | candidate | qword [rbp - 8*1] |
;;; |        | index     | qword [rbp - 8*2] |
                                                      ; (the diagram's "+ 8*2" is a slip in the original;
                                                      ;   the return address is at [rbp + 8*1], since no
                                                      ;   arguments were pushed. Check it in gdb with
                                                      ;   `info symbol *(long*)($rbp+8)`.)

        mov rax, qword [primes_table + 8*1]           ; pi(1) == 3. base + 8*index is the
                                                      ;   array idiom: 8 because elements are quadwords.
        mov qword [rbp - 8*1], rax                    ; last candidate <-- pi(1) == 3

.L1:                                                  ; the OUTER loop: "do we still need more primes?"
        mov rax, qword [last_prime_index]             ; just found a prime
        cmp rax, COUNT                                ; do we need more??
        jge .done                                     ; if not, we're happy!
                                                      ;   *** THE OFF-BY-ONE: the last valid index is
                                                      ;   COUNT-1, so this should compare against
                                                      ;   COUNT-1. As written, one extra prime is stored
                                                      ;   one element past the end of the table. ***

.next:                                                ; advance to the next candidate
        mov rax, qword [rbp - 8*1]                    ; last candidate is ODD
        add rax, 2                                    ; next candidate: last candidate + 2
                                                      ;   Stepping by 2 skips every even number: past 2,
                                                      ;   no even number is prime.
        mov qword [rbp - 8*1], rax                    ; set candidate
        mov qword [rbp - 8*2], 1                      ; start dividing from pi(1) == 3
                                                      ;   Index 1, not 0: divisibility by 2 is impossible
                                                      ;   for an odd candidate, so 2 is skipped.

.L2:                                                  ; the INNER loop: test this candidate for primality
        mov rbx, qword [rbp - 8*2]                    ; index -- into a register so it can be used as
                                                      ;   an addressing-mode scale index
        mov rcx, qword [primes_square_table + 8*rbx]  ; look at the square
        mov rax, qword [rbp - 8*1]                    ; candidate
        cmp rcx, rax                                  ; square > candidate?
        jg .new_prime                                 ; we found a new prime number!
                                                      ;   THE SQUARE-ROOT CUT-OFF: if p*p already exceeds
                                                      ;   the candidate, no divisor remains to be tried,
                                                      ;   because a factor above sqrt(c) implies one
                                                      ;   below it, which we have already checked.
        mov rcx, qword [primes_table + 8*rbx]         ; pi(i) -- the divisor to try
        cqo                                           ; prepare for division/remainder.
                                                      ;   Sign-extends rax into rdx, giving the 128-bit
                                                      ;   dividend RDX:RAX that `div` requires. (Strictly
                                                      ;   `cqo` is the SIGNED preparation; `xor rdx,rdx`
                                                      ;   is the right partner for unsigned `div`. It
                                                      ;   works here only because the candidate is
                                                      ;   positive, so cqo yields rdx = 0.)
        div rcx                                       ; candidate / pi(i)
                                                      ;   One-operand UNSIGNED divide with three hidden
                                                      ;   registers: reads RDX:RAX, writes the quotient
                                                      ;   to RAX and THE REMAINDER TO RDX.
        cmp rdx, 0                                    ; remainder == 0??
        jz .next                                      ; try next candidate -- divisible,
                                                      ;   therefore composite
        inc qword [rbp - 8*2]                         ; ++i -- try the next prime divisor
        jmp .L2                                       ; continue to test for primality

.new_prime:                                           ; the candidate survived every divisor
        mov rcx, qword [last_prime_index]
        inc rcx                                       ; ++last_prime_index -- the slot to fill
        mov rax, qword [rbp - 8*1]                    ; candidate
        mov qword [primes_table + 8*rcx], rax         ; next_prime <-- candidate
                                                      ;   *** this is the store that can run one element
                                                      ;   past the end; see the header. ***
        cqo                                           ; prepare to square (again, cqo is
                                                      ;   unnecessary before `mul`, which writes rdx
                                                      ;   without reading it)
        mul rax                                       ; candidate^2. One-operand UNSIGNED
                                                      ;   multiply: RDX:RAX := RAX * rax, so the low 64
                                                      ;   bits of the square land in rax.
        mov qword [primes_square_table + 8*rcx], rax  ; set in prime^2 table --
                                                      ;   computed ONCE here, looked up thereafter
        mov qword [last_prime_index], rcx             ; set in prime table
                                                      ;   (i.e. publish the new highest index)
        jmp .L1                                       ; search for next prime

.done:
        mov rsp, rbp                                  ; restore the original stack-pointer -- frees both
                                                      ;   locals in one instruction
        pop rbp                                       ; set frame-pointer to point to previous frame
        ret                                           ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; print_primes_table -- print every entry of primes_table as pi(i) = p.
;;;   Receives   : nothing (reads the globals)
;;;   Returns    : rax = 0
;;;   Clobbers   : rax and the printf argument registers
;;;   Locals     : [rbp - 8*1] = i, the loop index
;;;   How it works: a simple counted loop from 0 to last_prime_index INCLUSIVE
;;;                 (`jg`, not `jge`), printing one line per entry. The index
;;;                 lives in the frame, so nothing needs protecting across the
;;;                 printf calls -- the same idiom as code-0018.
;;; ----------------------------------------------------------------------------
print_primes_table:
        push rbp                                      ; save the old frame-pointer
        mov rbp, rsp                                  ; set frame-pointer to base of the new frame
        sub rsp, 8*1                                  ; reserve storage for one local variable
        and rsp, -16                                  ; align the stack for printing. AFTER the sub, so
                                                      ;   the padding comes from below the local.

;;; The activation frame:
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | i        | qword [rbp - 8*1] |

        mov qword [rbp - 8*1], 0                      ; i <-- 0, straight into the frame slot
.L:
        mov rax, qword [rbp - 8*1]                    ; i
        cmp rax, qword [last_prime_index]             ; i > last_prime_index ?
        jg .done                                      ; if so, done!
                                                      ;   `jg` rather than `jge`, so the last index is
                                                      ;   INCLUDED -- which is why the count of printed
                                                      ;   lines is last_prime_index + 1.

        mov rdi, fmt_prime_n                          ; load the format for printing the i-th prime
        mov rsi, rax                                  ; i (printf argument 2)
        mov rdx, qword [primes_table + 8*rax]         ; pi(i) (argument 3) -- base +
                                                      ;   8*index, the array idiom again
        mov rax, 0                                    ; no fp registers in use (the variadic rule)
        call printf
        inc qword [rbp - 8*1]                         ; ++i -- incremented in memory, so printf cannot
                                                      ;   disturb it
        jmp .L                                        ; round again

.done:
        mov rax, 0                                    ; Status: OK

        mov rsp, rbp                                  ; restore the old stack-pointer
        pop rbp                                       ; set fp to base of previous frame
        ret                                           ; pop the return address into rip

section .note.GNU-stack noalloc noexec                ; required Linux marker: stack is not exec
