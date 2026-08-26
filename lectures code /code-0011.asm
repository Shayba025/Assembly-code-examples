;;; ============================================================================
;;; code-0011.asm -- Factorial computed RECURSIVELY, PASCAL-style convention
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Identical output to code-0010. Diff the two files -- there are exactly TWO
;;;   differences, and both concern who removes the pushed argument:
;;;
;;;       code-0010 (C / cdecl)          code-0011 (Pascal / stdcall)
;;;       -------------------------      ---------------------------
;;;       push rax                       push rax
;;;       call fact                      call fact
;;;       add rsp, 8*1     <-- caller    (nothing)
;;;       ...                            ...
;;;       ret              <-- callee    ret 8*1
;;;
;;;   `ret 8*1` means: pop the return address into rip AS USUAL, and then also
;;;   add 8 to rsp, discarding that many bytes of arguments. One instruction,
;;;   one operand, and the entire cleanup obligation moves from the caller to
;;;   the callee.
;;;
;;;   WHY YOU WOULD CHOOSE PASCAL-STYLE:
;;;     + Smaller code. The `add rsp, k` disappears from EVERY call site, and
;;;       there is usually more than one call site per function. On a large
;;;       program this is a real saving, which is why 16-bit Windows and OS/2
;;;       used it throughout and why the Win32 API still does (`__stdcall`).
;;;     + The cleanup is written once, next to the function's own definition,
;;;       where the argument count is obviously correct.
;;;
;;;   WHY YOU WOULD CHOOSE C-STYLE:
;;;     + VARIADIC FUNCTIONS BECOME POSSIBLE. printf cannot know how many
;;;       arguments it received, so it cannot clean them up. Only the caller
;;;       knows. This is not a small point -- it is why C has printf at all, and
;;;       why Pascal's `write` had to be a compiler-level special form rather
;;;       than an ordinary library function.
;;;     + Mismatches are less catastrophic. Get the count wrong in Pascal style
;;;       and the callee corrupts rsp for everybody.
;;;
;;;   THE ACTIVATION FRAME is exactly as in code-0010 -- the convention changes
;;;   only the teardown, never the layout:
;;;       [rbp + 8*2]   n           <- pushed by the caller
;;;       [rbp + 8*1]   ret addr    <- pushed by `call`
;;;       [rbp + 8*0]   old rbp     <- pushed by the prologue
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0011.asm" 5          # 120
;;;   ./asm "lectures code /code-0011.asm" 20         # 2432902008176640000
;;;   ./asm "lectures code /code-0011.asm" 0          # 1
;;;   ./asm "lectures code /code-0011.asm" 21         # usage error
;;;
;;;   Prove the two files agree, then look at how differently they get there:
;;;   for n in 0 1 5 12 20; do ./asm "lectures code /code-0010.asm" $n; done
;;;   for n in 0 1 5 12 20; do ./asm "lectures code /code-0011.asm" $n; done
;;;   diff <(cat originals/"lectures code"/code-0010.asm) \
;;;        <(cat originals/"lectures code"/code-0011.asm)
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0011.asm" 5
;;;
;;;   Useful session:
;;;     break fact
;;;     c c                    descend two levels
;;;     bt                     the recursion as frames
;;;     x/1gd $rbp+16          this level's n
;;;     p $rsp                 24 bytes lower per level, same as code-0010
;;;     finish                 unwind one level
;;;     p $rsp                 <-- THE POINT: see below
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Run BOTH programs side by side in two terminals and compare one number.
;;;
;;;   In code-0010, break just after `call fact` returns and print rsp; it is
;;;   still 8 bytes low, because the argument is still sitting there. The very
;;;   next instruction, `add rsp, 8*1`, removes it.
;;;
;;;   In THIS file, break at the same place -- immediately after `call fact` --
;;;   and print rsp. It is already correct. Nothing follows the call, because
;;;   `ret 8*1` inside `fact` did the cleanup on the way out, before control
;;;   ever came back. Step it directly:
;;;       break code-0011.asm:NN     put NN on the `ret 8*1` line
;;;       c
;;;       p $rsp                     just before
;;;       si                         execute the ret
;;;       p $rsp                     16 higher, not 8: 8 for the return address
;;;                                  it popped, plus 8 for the argument it
;;;                                  discarded
;;;   Seeing rsp jump by 16 in one instruction is the clearest demonstration of
;;;   `ret imm16` you will get.
;;;
;;;   THE EXPERIMENT WORTH DOING ONCE. Change `ret 8*1` to `ret 8*2` (claiming
;;;   two arguments were passed when only one was), rebuild, and run under gdb.
;;;   The recursion will destroy its own frames: each return over-pops by 8, so
;;;   rsp climbs past the caller's saved rbp and the return addresses stop
;;;   lining up. `bt` will show garbage, and you will usually get a segfault
;;;   somewhere unrelated. THAT is why the callee-cleans convention demands that
;;;   caller and callee agree exactly -- and why a variadic function, which by
;;;   definition cannot agree, must use the C convention instead.
;;;
;;;   Everything else about the stack -- the 24-bytes-per-level cost, the
;;;   frame-pointer chain at [rbp], the multiplications unwinding in reverse --
;;;   is identical to code-0010. Read that file's notes for those; this one is
;;;   purely about the teardown.
;;; ============================================================================

        LIMIT equ 20                                     ; assemble-time constant: 20! is the largest
                                                         ;   factorial representable in 64 bits

section .data                                            ; initialised, writable data
fmt_output:
        db `Answer: %lld\n\0`                            ; printf format: one 64-bit signed decimal
fmt_usage:
        db `Usage: code-0011 n, where 0 <= n <= 20\n\0`  ; the error message

extern printf, fprintf, atoll, exit, stderr              ; supplied by the C library
global main                                              ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- validate n, call fact(n) Pascal-style, print the result.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 on bad input
;;;   How it works: pushes n and calls fact -- and then does NOTHING, because in
;;;                 the Pascal convention `fact` removes the argument itself on
;;;                 its way out. Compare code-0010's `add rsp, 8*1` here.
;;; ----------------------------------------------------------------------------
main:
        push rbp                                         ; back up the frame-pointer (rbp is callee-saved)
        mov rbp, rsp                                     ; set fp to the base of the current frame
        and rsp, -16                                     ; align stack by 16 bytes (for printf/scanf) by
                                                         ;   clearing rsp's low 4 bits

        cmp rdi, 2                                       ; argc == 2 -- subtract, keep only the flags
        jne .usage                                       ; print usage if not

        mov rdi, qword [rsi + 8*1]                       ; get argv[1]: base + 8*1 into the argv array
        call atoll                                       ; convert to a 64-bit integer -> rax
        cmp rax, 0                                       ; test if negative
        jl .usage                                        ; print usage if negative (signed comparison)
        cmp rax, LIMIT                                   ; (LIMIT + 1)! > 2^64
        jg .usage                                        ; print usage if input is too large

        push rax                                         ; push n -- the argument, on the stack
        call fact                                        ; call fact (Pascal-style: fact cleans stack)
                                                         ;   NOTE what is NOT here: no `add rsp, 8*1`
                                                         ;   follows. When control comes back, rsp is
                                                         ;   already correct.

        mov rdi, fmt_output                              ; format string for output (printf argument 1)
        mov rsi, rax                                     ; n! -- the return value, in rax
        mov rax, 0                                       ; no fp registers in use (the variadic rule)
        call printf

        mov rax, 0                                       ; status OK for OS

        mov rsp, rbp                                     ; restore original stack-pointer from the anchor
        pop rbp                                          ; set fp to point to previous frame
        ret                                              ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; main.usage -- bad or missing argument. NEVER RETURNS.
;;;   Writes the usage line to stderr and terminates with status -1.
;;; ----------------------------------------------------------------------------
.usage:
        mov rdi, qword [stderr]                          ; errors go to stderr. Brackets: `stderr` is a
                                                         ;   VARIABLE holding a FILE*; load its contents.
        mov rsi, fmt_usage                               ; explain correct usage (fprintf's argument 2)
        mov rax, 0                                       ; no fp registers in use
        call fprintf                                     ; send output to stderr...

        mov rax, -1                                      ; status NOT OK
        call exit                                        ; exit as per error. Never returns.

;;; ----------------------------------------------------------------------------
;;; fact -- n! by recursion, PASCAL-style (callee-cleans) calling convention.
;;;   Pseudo-C   : long long fact(long long n)
;;;                { return n == 0 ? 1 : n * fact(n - 1); }
;;;   Receives   : n on the STACK, at [rbp + 8*2] once the prologue has run
;;;   Returns    : rax = n!
;;;   Clobbers   : rax, rdx (mul writes the high half of the product there)
;;;   Cleanup    : ITS OWN. It exits with `ret 8*1`, which pops the return
;;;                address and then discards 8 more bytes -- the argument. Call
;;;                sites must NOT follow the call with an `add rsp, ...`.
;;;   Stack cost : 24 bytes per level, exactly as in code-0010; the convention
;;;                changes the teardown, not the layout.
;;;
;;;   How it works: identical to code-0010 line for line, right up to the final
;;;   `ret`. Read n from the frame, return 1 at zero, otherwise push n-1,
;;;   recurse, and multiply the result by n re-read from the frame (a register
;;;   copy would not have survived the recursive call).
;;; ----------------------------------------------------------------------------
fact:
        push rbp                                         ; back up the frame-pointer; the caller's rbp is now
                                                         ;   safe at [rsp]
        mov rbp, rsp                                     ; set fp to the base of the current frame -- from
                                                         ;   here the offsets in the diagram are fixed

;;; The structure of the activation frame:
;;; |         | n        | qword [rbp + 8*2] |
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
                                                         ; Reading upward from rbp: our saved rbp, the
                                                         ;   return address pushed by `call`, then the
                                                         ;   argument the caller pushed before that.

        mov rax, qword [rbp + 8*2]                       ; rax <-- n, from our own private frame slot
        cmp rax, 0                                       ; n = 0?
        je .zero                                         ; return 1 -- the BASE CASE
        dec rax                                          ; compute n-1
        push rax                                         ; push n-1 -- the argument for the recursive call
        call fact                                        ; compute fact(n - 1) --> rax (Pascal-style)
                                                         ;   ...and note again: NO cleanup instruction
                                                         ;   follows, because the callee will have done it.
        cqo                                              ; extend RAX --> RDX:RAX (sign-extend into rdx).
                                                         ;   Unnecessary before `mul`, which overwrites rdx
                                                         ;   without reading it; `cqo` pairs with `idiv`.
        mul qword [rbp + 8*2]                            ; RDX:RAX = n * fact(n - 1). Unsigned one-operand
                                                         ;   multiply: rax times the memory operand. n is
                                                         ;   RE-READ FROM THE FRAME because the recursive
                                                         ;   call destroyed the caller-saved registers.
        jmp .done                                        ; skip the base-case assignment
.zero:
        mov rax, 1                                       ; fact(0) = 1
.done:
        mov rsp, rbp                                     ; restore original stack-pointer from the anchor
        pop rbp                                          ; set fp to point to previous frame
        ret 8*1                                          ; Pascal-style: Callee cleans the stack!
                                                         ;   `ret imm16` pops the return address into rip
                                                         ;   AND THEN adds 8 to rsp, throwing away the
                                                         ;   argument the caller pushed. In gdb this shows
                                                         ;   up as rsp jumping by 16 in a single step.
                                                         ;   THIS ONE OPERAND IS THE WHOLE DIFFERENCE
                                                         ;   BETWEEN THIS FILE AND code-0010.

section .note.GNU-stack noalloc noexec                   ; required Linux marker: stack is not exec
