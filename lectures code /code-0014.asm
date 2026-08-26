;;; ============================================================================
;;; code-0014.asm -- Fibonacci computed RECURSIVELY, PASCAL-style convention
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Identical to code-0013 in every respect except the argument cleanup. This
;;;   is the second half of the C-vs-Pascal pair, exactly as code-0011 was to
;;;   code-0010 -- but with a twist that makes it the better of the two demos.
;;;
;;;   THE DIFFERENCE, all of it:
;;;
;;;       code-0013 (C / cdecl)         code-0014 (Pascal / stdcall)
;;;       ------------------------      ----------------------------
;;;       push rax                      push rax
;;;       call fib                      call fib
;;;       add rsp, 8*1   <-- gone       (nothing)
;;;       push rax                      push rax
;;;       ...                           ...
;;;       push rax                      push rax
;;;       call fib                      call fib
;;;       add rsp, 8*1   <-- gone       (nothing)
;;;       pop rbx                       pop rbx
;;;       ...                           ...
;;;       ret                           ret 8*1
;;;
;;;   THREE `add rsp, 8*1` INSTRUCTIONS DISAPPEAR AND ONE OPERAND APPEARS. That
;;;   is the argument for the Pascal convention in one picture: the cleanup cost
;;;   is paid once per FUNCTION rather than once per CALL SITE, and `fib` has
;;;   three call sites (two inside itself, one in main). In a real program with
;;;   dozens of call sites the saving is substantial, which is exactly why
;;;   16-bit Windows, OS/2 and the Win32 API (`__stdcall`) chose it.
;;;
;;;   AND THE COUNTER-ARGUMENT: printf could not possibly be written this way,
;;;   because a variadic function does not know how many arguments it received
;;;   and therefore cannot know what to subtract. Every variadic function in C
;;;   exists because the C convention leaves cleanup to the caller.
;;;
;;;   WHY THIS FILE IS THE BEST PLACE TO SEE IT: `ret 8*1` here is executed
;;;   thousands of times, from a recursion that is constantly interleaving two
;;;   different call sites. If the operand were wrong, the damage would be
;;;   immediate and total. The fact that it is not is a live demonstration that
;;;   caller and callee agree.
;;;
;;;   (Note: the usage string still says "code-0013". That is the professor's
;;;   copy-paste; the program is code-0014.)
;;;
;;;   The spill-to-the-stack lesson, the exponential cost, and the unsaved rbx
;;;   are all identical to code-0013 -- read that file's header for those.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0014.asm" 10         # 55
;;;   ./asm "lectures code /code-0014.asm" 0          # 0
;;;   ./asm "lectures code /code-0014.asm" 25         # 75025 -- already slow
;;;   ./asm "lectures code /code-0014.asm" -1         # usage error
;;;
;;;   Confirm the two conventions agree on every answer:
;;;   for n in $(seq 0 20); do
;;;       a=$(./asm "lectures code /code-0013.asm" $n)
;;;       b=$(./asm "lectures code /code-0014.asm" $n)
;;;       [ "$a" = "$b" ] && echo "n=$n ok" || echo "n=$n MISMATCH"
;;;   done
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0014.asm" 6
;;;
;;;   Useful session:
;;;     break fib
;;;     c c c                  descend into the recursion
;;;     bt                     the current root-to-leaf path
;;;     x/1gd $rbp+16          this frame's n
;;;     finish                 unwind one level
;;;     p $rsp                 <-- already correct, with no cleanup instruction
;;;                                in sight. That is the whole point.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Put a breakpoint directly on the `ret 8*1` line and single-step it:
;;;       break code-0014.asm:NN
;;;       c
;;;       p $rsp             just before
;;;       si                 execute the ret
;;;       p $rsp             SIXTEEN higher, not eight
;;;   Eight bytes for the return address it popped, eight more for the argument
;;;   it discarded. One instruction, two effects. Do the same on code-0013's
;;;   plain `ret` and rsp moves by only 8 -- and the caller's next instruction
;;;   moves it the rest of the way.
;;;
;;;   NOW THE EXPERIMENT THAT REALLY TEACHES THE CONVENTION. In this file the
;;;   stack discipline is genuinely delicate, because `fib` parks fib(n-1) on
;;;   the stack ACROSS the second recursive call. Break just after the second
;;;   `call fib` returns and check:
;;;       x/1gd $rsp         must be fib(n-1), the value you parked
;;;   It is correct only because `ret 8*1` removed exactly the 8 bytes of
;;;   argument and not a byte more or less. Change the operand to `ret 8*2`,
;;;   rebuild, and run: every return over-pops, the parked value is destroyed,
;;;   `pop rbx` picks up rubbish, and the program produces wrong numbers before
;;;   crashing. Change it to plain `ret` and the stack grows without bound
;;;   instead. Both failures are silent for a while and then catastrophic --
;;;   which is precisely why a convention has to be a convention.
;;;
;;;   Finally, compare frame counts. Break on `fib`, `ignore 1 1000000`, run to
;;;   completion, and `info breakpoints` gives the call count. It is identical
;;;   to code-0013's for the same n. The calling convention changes the code
;;;   size and who does the bookkeeping; it changes neither the algorithm nor
;;;   its cost.
;;; ============================================================================

        LIMIT equ 92                         ; assemble-time constant. fib(92) is the largest
                                             ;   Fibonacci number that fits in 64 bits.

section .data                                ; initialised, writable data
fmt_output:
        db `Answer: %lld\n\0`                ; printf format: one 64-bit signed decimal
fmt_usage:
        db `Usage: code-0013 n, where 0 <= n <= 92\n\0`
                                             ; NOTE: says 0013, not 0014 -- a copy-paste in the
                                             ;   original. Harmless, but the kind of thing worth
                                             ;   noticing in your own code.

extern printf, fprintf, atoll, exit, stderr  ; supplied by the C library
global main                                  ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- validate n, call fib(n) Pascal-style, print the result.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 on bad input
;;;   How it works: pushes n and calls fib -- and then nothing, because `fib`
;;;                 removes the argument itself via `ret 8*1`.
;;; ----------------------------------------------------------------------------
main:
        push rbp                             ; back up the frame-pointer (rbp is callee-saved)
        mov rbp, rsp                         ; set fp to the base of current frame -- the anchor
        and rsp, -16                         ; align stack by 16 bytes (for printf/scanf)

        cmp rdi, 2                           ; argc == 2 -- subtract, keep only the flags
        jne .usage                           ; print usage if not

        mov rdi, qword [rsi + 8*1]           ; get argv[1]: base + 8*1 into the argv array
        call atoll                           ; convert to a 64-bit integer -> rax
        cmp rax, 0                           ; test if negative
        jl .usage                            ; print usage if negative (signed comparison)
        cmp rax, LIMIT                       ; fib(LIMIT + 1) > 2^64
        jg .usage                            ; print usage if input is too large

        push rax                             ; push n -- the argument, on the stack
        call fib                             ; call fib, Pascal-style
                                             ;   No `add rsp, 8*1` follows: when control returns
                                             ;   here, rsp is already back where it belongs.

        mov rdi, fmt_output                  ; format string for output (printf argument 1)
        mov rsi, rax                         ; fib(n) -- the return value, in rax
        mov rax, 0                           ; no fp registers in use (the variadic rule)
        call printf

        mov rax, 0                           ; status OK for OS

        mov rsp, rbp                         ; restore original stack-pointer from the anchor
        pop rbp                              ; set fp to point to previous frame
        ret                                  ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; main.usage -- bad or missing argument. NEVER RETURNS.
;;;   Writes the usage line to stderr and terminates with status -1.
;;; ----------------------------------------------------------------------------
.usage:
        mov rdi, qword [stderr]              ; errors go to stderr. Brackets: `stderr` is a
                                             ;   VARIABLE holding a FILE*; load its contents.
        mov rsi, fmt_usage                   ; explain correct usage (fprintf's argument 2)
        mov rax, 0                           ; no fp registers in use
        call fprintf                         ; send output to stderr...

        mov rax, -1                          ; status NOT OK
        call exit                            ; exit as per error. Never returns.

;;; ----------------------------------------------------------------------------
;;; fib -- fib(n) by double recursion, PASCAL-style (callee-cleans) convention.
;;;   Pseudo-C   : long long fib(long long n)
;;;                { return n < 2 ? n : fib(n-1) + fib(n-2); }
;;;   Receives   : n on the STACK, at [rbp + 8*2] once the prologue has run
;;;   Returns    : rax = fib(n)
;;;   Clobbers   : rax, AND callee-saved rbx, which is never preserved -- the
;;;                same latent bug as code-0013.
;;;   Cleanup    : ITS OWN, via `ret 8*1`. Call sites must NOT follow the call
;;;                with an `add rsp, ...` -- and, correspondingly, none do.
;;;
;;;   The algorithm is identical to code-0013: read n, return it if n < 2,
;;;   otherwise recurse twice and add. The first result is PARKED ON THE STACK
;;;   across the second call, because there is only one rax. What changes is
;;;   that no cleanup instruction follows either `call fib` -- which is what
;;;   makes the parked value's position predictable with one fewer moving part.
;;; ----------------------------------------------------------------------------
fib:
        push rbp                             ; back up the frame-pointer; the caller's rbp is now
                                             ;   safe at [rsp]
        mov rbp, rsp                         ; set fp to the base of the current frame

;;; The structure of the activation frame:
;;; |         | n        | qword [rbp + 8*2] |
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
                                             ; Reading upward from rbp: our saved rbp, the
                                             ;   return address pushed by `call`, and the
                                             ;   argument the caller pushed before that.

        mov rax, qword [rbp + 8*2]           ; rax <-- n, from our own private frame slot
        cmp rax, 2                           ; n < 2?
        jl .base                             ; return n -- the BASE CASE, covering fib(0)=0 and
                                             ;   fib(1)=1 at once

        dec rax                              ; compute n-1
        push rax                             ; push n-1 -- the argument for the first call
        call fib                             ; compute fib(n-1), Pascal-style
                                             ;   The callee's `ret 8*1` has already removed the
                                             ;   n-1 by the time we get here.
        push rax                             ; save fib(n-1)
                                             ;   THE SPILL: rax is about to be overwritten by
                                             ;   the second recursive call, so park the value.
                                             ;   It lands at [rbp - 8*1] and must still be there
                                             ;   after the second call returns -- which is only
                                             ;   true if `ret 8*1` pops exactly the right amount.
        mov rax, qword [rbp + 8*2]           ; rax <-- n. Re-read from the frame; the
                                             ;   register copy is long gone.
        sub rax, 2                           ; compute n-2
        push rax                             ; push n-2 -- the argument for the second call
        call fib                             ; compute fib(n-2) --> rax, Pascal-style
        pop rbx                              ; rbx <-- fib(n-1). Recover the spilled value; the
                                             ;   argument above it was already cleaned by the
                                             ;   callee. (Clobbers callee-saved rbx -- see header.)
        add rax, rbx                         ; fib(n-1) + fib(n). rax now holds this level's answer.
        jmp .done                            ; skip the base-case assignment
.base:
        mov rax, qword [rbp + 8*2]           ; return n
.done:
        mov rsp, rbp                         ; restore original stack-pointer from the anchor
        pop rbp                              ; set fp to point to previous frame
        ret 8*1                              ; Pascal-style: the CALLEE cleans the stack. Pops
                                             ;   the return address into rip, then adds 8 to rsp
                                             ;   to discard the argument. In gdb, rsp jumps by
                                             ;   16 in this single step. Change the operand and
                                             ;   the recursion destroys its own parked values --
                                             ;   try it, it is instructive.

section .note.GNU-stack noalloc noexec       ; required Linux marker: stack is not exec
