;;; ============================================================================
;;; code-0013.asm -- Fibonacci computed RECURSIVELY, C-style convention
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   fib(n) by the textbook recurrence fib(n) = fib(n-1) + fib(n-2). It is to
;;;   code-0012 what code-0010 was to code-0009: the same answer, computed the
;;;   expensive way, so that you can watch the stack do the work.
;;;
;;;   WHAT MAKES THIS FILE DIFFERENT FROM code-0010: `fact` was SINGLY recursive
;;;   -- one call, and whatever came back could be used immediately. `fib` is
;;;   DOUBLY recursive, and that forces a new problem into the open:
;;;
;;;       call fib          ; -> fib(n-1) in rax
;;;       push rax          ; <-- MUST SAVE IT
;;;       ... set up n-2 ...
;;;       call fib          ; -> fib(n-2) in rax, and the first result is GONE
;;;       pop rbx           ; <-- get it back
;;;       add rax, rbx
;;;
;;;   There is exactly one rax, and the second call needs it. So the first
;;;   result has to live somewhere across the second call, and "somewhere" is
;;;   the stack. THIS IS THE CENTRAL LESSON: a register file is a fixed, tiny
;;;   resource; the stack is how a program with more live values than registers
;;;   keeps going. Every compiler you will ever use does exactly this, and calls
;;;   it "spilling".
;;;
;;;   THE COST. This is the classic exponential Fibonacci: fib(n) costs about
;;;   fib(n) calls -- 2^(n/2)-ish. fib(40) is already over 300 million calls.
;;;   code-0012 does the same job in n additions. Do NOT run this with 92; the
;;;   LIMIT check permits it but you would be waiting past the heat death of
;;;   your laptop. That gap between "permitted" and "sensible" is worth sitting
;;;   with: nothing in the code is wrong, and it is still unusable.
;;;
;;;   A BUG WORTH SPOTTING: `pop rbx` clobbers rbx, which is CALLEE-SAVED, and
;;;   `fib` never pushes it in its prologue. It survives here only because every
;;;   caller of `fib` is `fib` itself or `main`, and neither depends on rbx
;;;   afterwards. In real code this is how you produce a crash three functions
;;;   away. The fix is `push rbx` / `pop rbx` around the body. Callee-saved on
;;;   x86-64: rbx, rbp, r12-r15, rsp.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0013.asm" 10         # 55
;;;   ./asm "lectures code /code-0013.asm" 0          # 0
;;;   ./asm "lectures code /code-0013.asm" 1          # 1
;;;   ./asm "lectures code /code-0013.asm" 25         # 75025 -- already slow
;;;   ./asm "lectures code /code-0013.asm" -1         # usage error
;;;
;;;   Feel the exponential yourself:
;;;   for n in 20 25 30 32; do
;;;       echo -n "n=$n  "; time ./asm "lectures code /code-0013.asm" $n
;;;   done
;;;   Then run code-0012 with n = 92 and note it is instant.
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0013.asm" 6
;;;
;;;   Use a SMALL n. With n = 6 there are 25 calls, which you can actually watch.
;;;   Useful session:
;;;     break fib
;;;     c c c                  descend into the recursion
;;;     bt                     the call tree, as a path from root to leaf
;;;     x/1gd $rbp+16          this frame's n
;;;     up  /  down            walk the chain of suspended calls
;;;     finish                 unwind one level; p $rax for the partial answer
;;;
;;;   To count the calls instead of stepping through them:
;;;     break fib
;;;     ignore 1 100000        never actually stop...
;;;     c                      ...run to completion
;;;     info breakpoints       the hit count IS the number of calls
;;;   Do that for n = 10, 15, 20 and watch the count explode.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Run with n = 6, break on `fib`, and hit `c` about ten times, typing `bt`
;;;   each time. You are watching a DEPTH-FIRST TRAVERSAL of the call tree. The
;;;   backtrace is the current path from the root to wherever you are; it grows
;;;   as you descend the fib(n-1) branch, shrinks as results come back, then
;;;   grows again down the fib(n-2) branch. The stack never holds the whole
;;;   tree -- only one root-to-leaf path at a time. That is why the MEMORY cost
;;;   is O(n) while the TIME cost is exponential, and it is the single most
;;;   useful thing to understand about recursion.
;;;
;;;   THE EXPERIMENT FOR THIS FILE -- watch the spill. Break on the `push rax`
;;;   that saves fib(n-1):
;;;       p $rax          fib(n-1), freshly returned
;;;       si              execute the push
;;;       x/1gd $rsp      there it is, on the stack
;;;       break fib
;;;       c               descend into the SECOND recursive call
;;;       p $rax          garbage -- the second call is reusing rax
;;;   The value you needed is untouched on the stack the entire time. Now
;;;   `finish` back out, step the `pop rbx`, and `p $rbx` -- recovered exactly.
;;;   A register is a place values pass through; the stack is where they wait.
;;;
;;;   Also note this frame is BIGGER than fact's. Print `p $rsp` at entry to a
;;;   `fib` and again just before the second `call fib`: the saved fib(n-1) and
;;;   the pushed n-2 are both live at that moment. Frame size is decided by how
;;;   many values must be simultaneously alive, not by how many lines of code
;;;   there are.
;;;
;;;   Finally, the convention: every `call fib` here is followed by
;;;   `add rsp, 8*1`, because this is the C style -- the CALLER cleans up. There
;;;   are two call sites, so the instruction appears twice. In code-0014 both
;;;   copies vanish and `ret 8*1` does the work instead. That is the argument
;;;   for Pascal style in miniature: the more call sites, the more code the C
;;;   convention costs you.
;;; ============================================================================

        LIMIT equ 92                                     ; assemble-time constant. fib(92) is the largest
                                                         ;   Fibonacci number that fits in 64 bits -- though
                                                         ;   see the header: this ALGORITHM cannot reach it.

section .data                                            ; initialised, writable data
fmt_output:
        db `Answer: %lld\n\0`                            ; printf format: one 64-bit signed decimal
fmt_usage:
        db `Usage: code-0013 n, where 0 <= n <= 92\n\0`  ; the error message

extern printf, fprintf, atoll, exit, stderr              ; supplied by the C library
global main                                              ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- validate n, call fib(n) C-style, print the result.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 on bad input
;;;   How it works: pushes n, calls fib, then -- being the C-style CALLER --
;;;                 removes the argument itself with `add rsp, 8*1`.
;;; ----------------------------------------------------------------------------
main:
        push rbp                                         ; back up the frame-pointer (rbp is callee-saved)
        mov rbp, rsp                                     ; set fp to the base of current frame -- the anchor
        and rsp, -16                                     ; align stack by 16 bytes (for printf/scanf) by
                                                         ;   clearing rsp's low 4 bits

        cmp rdi, 2                                       ; argc == 2 -- subtract, keep only the flags
        jne .usage                                       ; print usage if not

        mov rdi, qword [rsi + 8*1]                       ; get argv[1]: rsi is argv, base+8*1 selects
                                                         ;   element 1, a char*
        call atoll                                       ; convert to a 64-bit integer -> rax
        cmp rax, 0                                       ; test if negative
        jl .usage                                        ; print usage if negative (`jl` = signed less-than)
        cmp rax, LIMIT                                   ; fib(LIMIT + 1) > 2^64
        jg .usage                                        ; print usage if input is too large

        push rax                                         ; push n -- the argument goes on the STACK
        call fib                                         ; call fib. `call` pushes the return address, so
                                                         ;   inside fib the argument sits at [rbp + 8*2].
        add rsp, 8*1                                     ; C-style: Caller cleans the stack!
                                                         ;   Undo our own push. Compare code-0014, where
                                                         ;   this line does not exist.

        mov rdi, fmt_output                              ; format string for output (printf argument 1)
        mov rsi, rax                                     ; fib(n) -- the return value, in rax as always
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
;;; fib -- fib(n) by double recursion, C-style (caller-cleans) convention.
;;;   Pseudo-C   : long long fib(long long n)
;;;                { return n < 2 ? n : fib(n-1) + fib(n-2); }
;;;   Receives   : n on the STACK, at [rbp + 8*2] once the prologue has run
;;;   Returns    : rax = fib(n)
;;;   Clobbers   : rax, AND rbx -- which is callee-saved and is NOT preserved
;;;                here. See the header note; a correct version would push it.
;;;   Cleanup    : none of its own arguments -- callers must `add rsp, 8` after
;;;                every `call fib`. There are two such sites inside this very
;;;                function.
;;;
;;;   THE SHAPE THAT MATTERS: because there are TWO recursive calls and only one
;;;   rax, the result of the first must be parked on the stack while the second
;;;   runs. `push rax` ... `pop rbx` is that parking, and it is the whole reason
;;;   this function is more interesting than `fact` in code-0010.
;;;
;;;   Stack at the deepest point of one activation:
;;;       [rbp + 8*2]  n                 (the caller pushed it)
;;;       [rbp + 8*1]  return address    (pushed by `call`)
;;;       [rbp + 8*0]  saved rbp         (pushed by the prologue)
;;;       [rbp - 8*1]  fib(n-1), parked  (pushed by us, between the two calls)
;;;       [rbp - 8*2]  n-2, the argument for the second call
;;; ----------------------------------------------------------------------------
fib:
        push rbp                                         ; back up the frame-pointer; the caller's rbp is now
                                                         ;   safe at [rsp]
        mov rbp, rsp                                     ; set fp to the base of the current frame -- from
                                                         ;   here the offsets below are fixed for this
                                                         ;   activation, no matter what rsp does

;;; The structure of the activation frame:
;;; |         | n        | qword [rbp + 8*2] |
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
                                                         ; Reading upward from rbp: our saved rbp, then the
                                                         ;   return address `call` pushed, then the argument
                                                         ;   the caller pushed before that.

        mov rax, qword [rbp + 8*2]                       ; rax <-- n, read from our own frame slot
        cmp rax, 2                                       ; n < 2?
        jl .base                                         ; return n -- the BASE CASE covers both fib(0)=0
                                                         ;   and fib(1)=1, since fib(n)=n for n<2

        dec rax                                          ; compute n-1
        push rax                                         ; push n-1 -- the argument for the first call
        call fib                                         ; compute fib(n-1). Result comes back in rax.
        add rsp, 8*1                                     ; C-style: caller cleans up! Remove the n-1.
        push rax                                         ; save fib(n-1)
                                                         ;   THE SPILL. rax is about to be reused by the
                                                         ;   second recursive call, so this value has to
                                                         ;   wait somewhere the callee cannot reach. It
                                                         ;   lands at [rbp - 8*1].
        mov rax, qword [rbp + 8*2]                       ; rax <-- n. RE-READ from the frame: our
                                                         ;   register copy was consumed by `dec` and then by
                                                         ;   the call.
        sub rax, 2                                       ; compute n-2
        push rax                                         ; push n-2 -- the argument for the second call
        call fib                                         ; compute fib(n-2) --> rax
        add rsp, 8*1                                     ; C-style: caller cleans up! Remove the n-2.
                                                         ;   Now [rsp] is once again our parked fib(n-1).
        pop rbx                                          ; rbx <-- fib(n-1). Recover the spilled value.
                                                         ;   (This clobbers callee-saved rbx -- see header.)
        add rax, rbx                                     ; fib(n-1) + fib(n). `add dst, src` = dst := dst+src,
                                                         ;   so rax becomes the answer for this level.
        jmp .done                                        ; skip the base-case assignment
.base:
        mov rax, qword [rbp + 8*2]                       ; return n. Re-read rather than trusting rax,
                                                         ;   which is fine either way here but keeps the
                                                         ;   "the frame is the truth" habit.
.done:
        mov rsp, rbp                                     ; restore original stack-pointer from the anchor.
                                                         ;   Note this also discards anything still pushed --
                                                         ;   nothing is, at this point, but it makes the
                                                         ;   function robust.
        pop rbp                                          ; set fp to point to previous frame
        ret                                              ; plain `ret`: pop the return address and LEAVE the
                                                         ;   argument in place -- the caller removes it.
                                                         ;   Contrast `ret 8*1` in code-0014.

section .note.GNU-stack noalloc noexec                   ; required Linux marker: stack is not exec
