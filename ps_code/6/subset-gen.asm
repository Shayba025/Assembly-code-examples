;;; ============================================================================
;;; subset-gen.asm -- every subset of a string, by recursive backtracking
;;; Practice session 6                       (study annotations added)
;;; The original header reads: "generating all subsets of an input string /
;;; based on the logic of Mayer Goldberg"
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints all 2^n subsets of the characters of its argument.
;;;   (Verified: `abc` prints {}, {c}, {b}, {bc}, {a}, {ac}, {ab}, {abc}.)
;;;
;;;   IT IS code-0004.asm WITH LETTERS INSTEAD OF BITS. Read the two together --
;;;   the structure is identical, and the correspondence is exact:
;;;
;;;       code-0004.asm (binary patterns)   subset-gen.asm (subsets)
;;;       ------------------------------    ------------------------------
;;;       write '0' at position i           SKIP character i
;;;       write '1' at position i           APPEND character i
;;;       recurse, then undo                recurse, then undo
;;;       one shared buffer + index i       two indices: i in the input,
;;;                                         j in the output buffer
;;;
;;;   THE PATTERN IS "DO / RECURSE / UNDO", and it is the heart of every
;;;   exhaustive search you will ever write -- n-queens, sudoku, permutations,
;;;   maze solving. Each level owns exactly one decision, tries both answers, and
;;;   restores the state before returning so its caller can try the other branch.
;;;
;;;   THE TWO INDICES ARE THE ONE NEW IDEA. code-0004.asm needed only i, because
;;;   every position produced a character. Here a skipped character produces
;;;   nothing, so the output is SHORTER than the input and needs its own cursor:
;;;       i = how far through the input we are  (0 .. n)
;;;       j = how many characters we have kept  (0 .. i)
;;;   Notice that the "skip" branch increments only i, while the "keep" branch
;;;   increments BOTH -- and that the undo at the bottom decrements both. Get one
;;;   of those four adjustments wrong and the output is subtly, silently wrong.
;;;
;;;   THE INVARIANT that makes it work: every call returns with i and j exactly
;;;   as it found them. Check it in gdb by printing both at entry and after
;;;   `finish` -- they must match. That is what lets the caller reuse position i
;;;   for its second branch.
;;;
;;;   `call strlen` IS WORTH NOTICING. It is an ordinary C library function --
;;;   `size_t strlen(const char *)` -- taking a pointer in rdi and returning a
;;;   count in rax, exactly like atoll and printf. There is nothing special about
;;;   string functions.
;;;
;;;   A LATENT ALIGNMENT BUG, and this one is real. `main` does `and rsp, -16`,
;;;   but `generate_subsets` has NO PROLOGUE and does not re-align. Each nested
;;;   `call` pushes 8 more bytes, so the alignment ALTERNATES with recursion
;;;   depth: half the calls to printf receive a correctly aligned stack and half
;;;   do not. It survives because printf with no floating-point arguments never
;;;   executes the aligned SSE instructions that would fault. Verify it yourself:
;;;       break printf
;;;       c
;;;       p $rsp % 16          8 is correct; 0 means misaligned
;;;       c
;;;       p $rsp % 16          ...and it flips
;;;   code-0004.asm has exactly the same defect. The fix is a prologue with
;;;   `and rsp, -16` in the recursive function, or aligning immediately before
;;;   each call.
;;;
;;;   TWO SMALLER THINGS: `empty_msg` is declared and never used, and
;;;   `result_buf` is 128 bytes with nothing checking the input length against
;;;   it -- an argument of more than 127 characters would write past the end.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/6/subset-gen.asm" abc
;;;   ./asm "ps_code/6/subset-gen.asm" ab
;;;   ./asm "ps_code/6/subset-gen.asm" abcd
;;;   ./asm "ps_code/6/subset-gen.asm" ""          # just the empty set
;;;   ./asm "ps_code/6/subset-gen.asm"             # no argument: prints nothing
;;;
;;;   Confirm the count really is 2^n:
;;;   for s in a ab abc abcd abcde; do
;;;       printf "%-6s %s subsets\n" "$s" \
;;;           "$(./asm "ps_code/6/subset-gen.asm" $s | wc -l | tr -d ' ')"
;;;   done
;;;
;;;   Careful: the work doubles with every character. Twenty characters is a
;;;   million lines.
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/6/subset-gen.asm" abc
;;;
;;;   Useful session:
;;;     break generate_subsets
;;;     c c c                     descend to a leaf
;;;     bt                        one frame per character decided so far
;;;     p (long)i                 how far through the input
;;;     p (long)j                 how many characters kept
;;;     x/s &result_buf           the subset being built
;;;
;;;   Watch the "undo" that makes backtracking work:
;;;     break subset-gen.asm:NN   NN on the `dec qword [i]` after the first call
;;;     c
;;;     p (long)i                 note it
;;;     si
;;;     p (long)i                 one lower -- the state is restored for the
;;;                               caller's second branch
;;;
;;;   And check the invariant directly:
;;;     break generate_subsets
;;;     c
;;;     p (long)i
;;;     p (long)j
;;;     finish
;;;     p (long)i                 IDENTICAL to before the call
;;;     p (long)j                 also identical
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   NOTICE WHAT IS *NOT* ON THE STACK. `i`, `j`, `n`, `input_str` and
;;;   `result_buf` are all globals in .data and .bss. `generate_subsets` has no
;;;   frame, no locals and no arguments -- the only thing each activation puts on
;;;   the stack is the 8-byte return address that `call` pushes.
;;;
;;;   So what is the stack actually holding? THE RETURN ADDRESSES, and nothing
;;;   else. Each one records "when the callee finishes, resume me at the line
;;;   after MY call" -- and that is precisely what makes the second branch (the
;;;   "keep this character" half) happen at every level, automatically, with no
;;;   data structure of your own. Look at them:
;;;       break generate_subsets
;;;       c  c  c
;;;       x/4gx $rsp               the stacked return addresses, one per level
;;;       info symbol *(long*)$rsp
;;;       info symbol *(long*)($rsp+8)
;;;   The two will name DIFFERENT source lines -- one is part-way through the
;;;   "skip" branch, the other through the "keep" branch. THAT IS THE ENTIRE
;;;   BOOKKEEPING OF THE SEARCH, and the call stack is the data structure.
;;;
;;;   Measure the cost:
;;;       break generate_subsets
;;;       c
;;;       p $rsp
;;;       c
;;;       p $rsp                   8 bytes lower per level
;;;   Eight bytes per level, and the depth is n -- NOT 2^n. The stack holds one
;;;   root-to-leaf path at a time, never the whole tree. That is why the memory
;;;   cost is linear while the running time is exponential, and it is the single
;;;   most useful fact about recursion.
;;;
;;;   Compare code-0017.asm (Hanoi), where each level costs 56 bytes because it
;;;   has four stack arguments and a frame. Same shape of recursion, seven times
;;;   the memory -- because that program's state lives in frames and this one's
;;;   lives in globals. Neither is wrong; the trade is that globals make the
;;;   function non-reentrant, so this one could never be used from two threads.
;;; ============================================================================

;;; subset-gen.asm
;;; יצירת כל תתי-הקבוצות של מחרוזת קלט
;;; מבוסס על הלוגיקה של Mayer Goldberg

section .data
                                        ;   initialised, writable data
    fmt_subset: db `{%s}\n\0`
                                        ;   printf format: one string in braces, then a newline
    empty_msg:  db `Empty set included\n\0`
                                        ;   declared but NEVER USED -- leftover scaffolding
    i:          dq 0                    ; אינדקס במחרוזת המקורית
                                        ;   the cursor into the INPUT string, 0 .. n. Also the
                                        ;   current recursion depth.
    j:          dq 0                    ; אינדקס בבאפר התוצאה
                                        ;   the cursor into the OUTPUT buffer, 0 .. i. Smaller than
                                        ;   i whenever characters have been skipped.
    input_str:  dq 0                    ; מצביע למחרוזת שקיבלנו מהמשתמש
                                        ;   a pointer to argv[1], saved so the recursion can reach it

section .bss
                                        ;   zero-filled at load time, no file space
    n:          resq 1                  ; אורך מחרוזת הקלט
                                        ;   the length of the input, computed once by strlen
    result_buf: resb 128                ; באפר לבניית תת-הקבוצה הנוכחית
                                        ;   `resb 128` reserves 128 BYTES. Nothing checks the input
                                        ;   length against this -- see the header.

extern printf, strlen
                                        ;   both supplied by the C library. `strlen` is an ordinary
                                        ;   function: size_t strlen(const char *).
global main
                                        ;   export `main` for the C library start-up
section .text
                                        ;   the executable-code section

main:
    push rbp
                                        ;   prologue: save the caller's frame pointer
    mov rbp, rsp
                                        ;   anchor the frame
    and rsp, -16
                                        ;   round rsp DOWN to a multiple of 16 -- but see the
                                        ;   alignment note in the header: generate_subsets does not
                                        ;   maintain this.

    cmp rdi, 2                          ; בדיקה שקיבלנו ארגומנט (מחרוזת)
                                        ;   exactly one argument expected
    jne .exit
                                        ;   `.exit` is LOCAL to main, i.e. `main.exit`

    mov rsi, qword [rsi + 8*1]          ; קבלת כתובת המחרוזת (argv[1])
                                        ;   rsi is argv; base + 8*1 selects element 1, a char*.
                                        ;   Note rsi is overwritten with its own dereference.
    mov qword [input_str], rsi
                                        ;   save the pointer in .data, where no callee can clobber it

    mov rdi, rsi
                                        ;   strlen's one argument: the string
    call strlen                         ; חישוב אורך המחרוזת
                                        ;   size_t strlen(const char *): pointer in rdi, count in rax
    mov qword [n], rax
                                        ;   save the length; the recursion compares i against it

    call generate_subsets
                                        ;   ONE call, which unfolds into the whole 2^n-leaf search tree

.exit:
                                        ;   the shared exit, reached either normally or from the
                                        ;   argument-count check
    mov rsp, rbp
                                        ;   epilogue: restore rsp from the anchor
    pop rbp
                                        ;   restore the caller's frame pointer
    ret
                                        ;   pop the return address into rip. rax is not reset, so the
                                        ;   exit status is incidental.

generate_subsets:
                                        ;   NO PROLOGUE: no push rbp, no locals, no arguments. All
                                        ;   state is global, so the only stack cost is the 8-byte
                                        ;   return address `call` pushed.
    mov rax, qword [i]
                                        ;   load the input cursor
    cmp rax, qword [n]                  ; תנאי עצירה: הגענו לסוף המחרוזת
                                        ;   THE BASE CASE test: every character has been decided
    je .print_subset
                                        ;   `.print_subset` is local to generate_subsets

                                        ; אפשרות 1: לא להכליל את האות הנוכחית
    inc qword [i]                       ; עוברים לאות הבאה
                                        ;   BRANCH 1 -- skip this character. Only i advances; j does
                                        ;   not, because nothing was added to the output.
    call generate_subsets
                                        ;   recurse. The return address pushed here is what brings us
                                        ;   back to try the other branch.
    dec qword [i]                       ; חוזרים (Backtrack)
                                        ;   UNDO. Restore i so the caller's invariant holds and so
                                        ;   branch 2 below sees the right position.

                                        ; אפשרות 2: כן להכליל את האות הנוכחית
    mov rsi, qword [input_str]
                                        ;   BRANCH 2 -- keep this character. Reload the input pointer;
                                        ;   rsi was destroyed by the recursion.
    mov rdx, qword [i]
                                        ;   the current input position
    mov al, byte [rsi + rdx]            ; טעינת האות הנוכחית
                                        ;   load one BYTE: input_str[i]. `al` is the low 8 bits of rax,
                                        ;   and the operand widths must match the one-byte source.

    mov rdx, qword [j]
                                        ;   the current output position
    mov byte [result_buf + rdx], al     ; הוספה לבאפר התוצאה
                                        ;   append the character: result_buf[j] = c. `byte` is required
                                        ;   -- the brackets alone do not say how wide the store is.

    inc qword [j]
                                        ;   one more character in the output
    inc qword [i]
                                        ;   ...and one more consumed from the input. BOTH advance in
                                        ;   this branch, unlike branch 1.
    call generate_subsets
                                        ;   recurse again, with the character included

                                        ; חזרה למצב קודם (Backtrack)
    dec qword [i]
                                        ;   UNDO both adjustments, in the opposite order to the
                                        ;   increments. This restores the invariant: every call returns
                                        ;   with i and j exactly as it found them.
    dec qword [j]
                                        ;   ...and j
    ret
                                        ;   pop the return address into rip

.print_subset:
                                        ;   THE BASE CASE: i == n, so every character has been decided
                                        ; סגירת המחרוזת בבאפר התוצאה עם NULL
    mov rdx, qword [j]
                                        ;   the length of the subset built so far
    mov byte [result_buf + rdx], 0
                                        ;   plant the NUL terminator, so result_buf is a valid C string
                                        ;   for %s. Written afresh at every leaf, because j differs.

    mov rdi, fmt_subset
                                        ;   printf argument 1: the `{%s}` format
    mov rsi, result_buf
                                        ;   argument 2: the subset. A bare label is its ADDRESS.
    mov rax, 0
                                        ;   THE VARIADIC RULE: 0 vector registers carry arguments
    call printf
    ret
                                        ;   return to whichever `call generate_subsets` got us here
