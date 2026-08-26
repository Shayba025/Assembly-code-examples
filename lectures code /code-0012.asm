;;; ============================================================================
;;; code-0012.asm -- Fibonacci computed ITERATIVELY, argument on the cmd line
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints fib(n) for n on the command line, where fib(0)=0, fib(1)=1.
;;;   Structurally it is code-0009 with the multiplication replaced by an
;;;   addition -- but the addition is done by ONE instruction that is worth the
;;;   whole file:
;;;
;;;       xadd rbx, rax      ; (rbx, rax) <-- (rbx + rax, rbx)
;;;
;;;   `xadd dst, src` (eXchange and ADD) does two things atomically:
;;;       tmp = dst + src;  src = dst;  dst = tmp;
;;;   which is exactly the Fibonacci step. In C you would need a temporary:
;;;       t = a + b;  a = b;  b = t;
;;;   and here the hardware supplies the temporary for you. (`xadd` exists
;;;   mainly for lock-free counters -- `lock xadd` is how atomic fetch-and-add
;;;   is implemented -- but it fits this loop perfectly.)
;;;
;;;   THE SAME `loopnz` TRAP as code-0009 applies: `loop`-family instructions
;;;   decrement rcx and THEN test, so entering with rcx = 0 would wrap to
;;;   2^64-1. That is why n == 0 is caught and dispatched before the loop.
;;;
;;;   WHY LIMIT = 92: fib(92) = 7540113804746346429 fits in a signed 64-bit
;;;   register; fib(93) does not.
;;;
;;;   A BUG WORTH SPOTTING YOURSELF: this program uses `rbx`, and rbx is a
;;;   CALLEE-SAVED register under the System V ABI -- `main` is obliged to give
;;;   it back to the C library unchanged, and this code never saves or restores
;;;   it. It happens to survive here because nothing downstream depends on rbx,
;;;   but it is exactly the kind of thing that produces a crash three functions
;;;   away in a larger program. THE FIX would be `push rbx` in the prologue and
;;;   `pop rbx` in the epilogue. Callee-saved on x86-64: rbx, rbp, r12, r13,
;;;   r14, r15, and rsp. Everything else is fair game.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0012.asm" 10         # 55
;;;   ./asm "lectures code /code-0012.asm" 0          # 0
;;;   ./asm "lectures code /code-0012.asm" 1          # 1
;;;   ./asm "lectures code /code-0012.asm" 92         # 7540113804746346429
;;;   ./asm "lectures code /code-0012.asm" 93         # usage error (overflow)
;;;   ./asm "lectures code /code-0012.asm" -1         # usage error
;;;
;;;   Watch the whole sequence at once:
;;;   for n in $(seq 0 15); do ./asm "lectures code /code-0012.asm" $n; done
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0012.asm" 10
;;;
;;;   Useful session -- this is a two-register dance, so watch both:
;;;     break code-0012.asm:NN     put NN on the `xadd rbx, rax` line
;;;     c
;;;     info registers rax rbx rcx
;;;     si                         execute the xadd
;;;     info registers rax rbx rcx again -- and see the swap-and-add
;;;     c                          repeat: 0/1, 1/1, 1/2, 2/3, 3/5, 5/8 ...
;;;
;;;   Or let gdb do the watching for you:
;;;     display/d $rax
;;;     display/d $rbx
;;;     display/d $rcx
;;;   and then just hit `si` repeatedly -- all three print after every step.
;;;
;;;   The one-line proof of what xadd does:
;;;     set $rax = 100
;;;     set $rbx = 7
;;;     si                         (on the xadd)
;;;     info registers rax rbx     rax = 7 (the OLD rbx), rbx = 107
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Break on `printf` and `bt`: two frames, for n = 0 and for n = 92 alike.
;;;   An iterative algorithm has a constant stack footprint, and this program
;;;   never touches the stack at all after its prologue -- no pushes, no locals,
;;;   no calls inside the loop. All of fib's state fits in three registers.
;;;
;;;   THAT is the observation to carry forward. The recursive Fibonacci you have
;;;   probably written in a high-level language is not merely slower -- it is
;;;   O(fib(n)) CALLS deep in total work and O(n) frames deep at its worst
;;;   moment, while this is O(n) additions and O(1) memory. Try it: write
;;;   recursive fib in the style of code-0010, break on it, run with n = 25, and
;;;   count with `bt`. Then compare the wall-clock times.
;;;
;;;   The second stack lesson here is the missing `push rbx`. Do this in gdb:
;;;       break main
;;;       p/x $rbx        the value the C library handed you
;;;       break printf
;;;       c
;;;       p/x $rbx        different -- you clobbered a register you had promised
;;;                       to preserve
;;;   The stack is where that promise would have been kept: `push rbx` in the
;;;   prologue puts the caller's value in YOUR frame, safe from your own code,
;;;   and `pop rbx` in the epilogue hands it back. Callee-saved registers are
;;;   simply "registers whose old value you must find room for on the stack".
;;; ============================================================================

        LIMIT equ 92                                     ; assemble-time constant. fib(92) is the largest
                                                         ;   Fibonacci number that fits in 64 bits.

section .data                                            ; initialised, writable data
fmt_output:
        db `Answer: %lld\n\0`                            ; printf format: one 64-bit signed decimal
fmt_usage:
        db `Usage: code-0012 n, where 0 <= n <= 92\n\0`  ; the error message

extern printf, fprintf, atoll, exit, stderr              ; supplied by the C library
global main                                              ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- read n, compute fib(n) in a loop, print it.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 on bad input
;;;   Registers   : rax = fib(k)   (the answer so far)
;;;                 rbx = fib(k+1) (the look-ahead)
;;;                 rcx = the countdown, because `loopnz` insists on rcx
;;;   Invariant   : after k iterations, (rax, rbx) == (fib(k), fib(k+1)).
;;;                 Starting from (0, 1) == (fib(0), fib(1)) and applying
;;;                 xadd n times therefore leaves fib(n) in rax.
;;;   Caveat      : rbx is callee-saved and is neither pushed nor popped here --
;;;                 see the note in the header.
;;; ----------------------------------------------------------------------------
main:
        push rbp                                         ; back up the frame-pointer (rbp is callee-saved)
        mov rbp, rsp                                     ; set fp to the base of current frame -- the anchor
        and rsp, -16                                     ; align stack by 16 (for printf/scanf): clear the
                                                         ;   low 4 bits of rsp, as every `call` requires

        cmp rdi, 2                                       ; argc == 2 -- subtract, keep only the flags
        jne .usage                                       ; print usage if not

        mov rdi, qword [rsi + 8*1]                       ; get argv[1]: rsi is argv, base+8*1 is element 1
        call atoll                                       ; convert to a 64-bit integer -> rax

        mov rcx, rax                                     ; prepare to iterate! rcx is the counter that
                                                         ;   `loopnz` decrements -- the register is wired
                                                         ;   into the instruction, not a choice.
        mov rax, 0                                       ; initialize accumulator: fib(0) = 0
        mov rbx, 1                                       ; the look-ahead: fib(1) = 1. (rbx is callee-saved
                                                         ;   and is being clobbered without a push -- see
                                                         ;   the header note.)
        cmp rcx, 0                                       ; must test, because LOOPNZ is not WHILE!
                                                         ;   `loopnz` decrements first and tests after, so
                                                         ;   rcx = 0 would wrap around to 2^64-1.
        jl .usage                                        ; print usage if negative (`jl` = signed less-than)
        je .finished                                     ; print 0 if done: fib(0) = 0, already in rax
        cmp rcx, LIMIT                                   ; fib(LIMIT + 1) > 2^64
        jg .usage                                        ; print usage if input is too large

.loop:
        xadd rbx, rax                                    ; compute: (rbx, rax) <-- (rax + rbx, rbx)
                                                         ;   eXchange-and-ADD: tmp = rbx + rax; rax = rbx;
                                                         ;   rbx = tmp. One instruction performs the whole
                                                         ;   Fibonacci step, temporary included. It also
                                                         ;   sets the flags from the addition, which is what
                                                         ;   the ZF half of `loopnz` will read.
        loopnz .loop                                     ; loop if positive. Decrement rcx, then jump back
                                                         ;   if rcx != 0 AND ZF == 0. Runs the body exactly
                                                         ;   n times, leaving fib(n) in rax.

.finished:
        mov rdi, fmt_output                              ; format string for output (printf argument 1)
        mov rsi, rax                                     ; fib(n) (printf argument 2)
        mov rax, 0                                       ; no fp registers in use -- the variadic rule
        call printf
        jmp .done                                        ; (a jump to the very next line -- harmless, and a
                                                         ;   leftover from an earlier version of the file)

.done:
        mov rax, 0                                       ; status OK for OS

        mov rsp, rbp                                     ; restore original stack-pointer from the anchor
        pop rbp                                          ; set fp to point to previous frame
        ret                                              ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; main.usage -- bad or missing argument. NEVER RETURNS.
;;;   Writes the usage line to stderr and terminates with status -1. Reached
;;;   from three tests: wrong argc, negative n, and n greater than LIMIT.
;;; ----------------------------------------------------------------------------
.usage:
        mov rdi, qword [stderr]                          ; errors go to stderr. Brackets: `stderr` is a
                                                         ;   VARIABLE holding a FILE*; load its contents.
        mov rsi, fmt_usage                               ; explain correct usage (fprintf's argument 2)
        mov rax, 0                                       ; no fp registers in use
        call fprintf                                     ; send output to stderr...

        mov rax, -1                                      ; status NOT OK
        call exit                                        ; exit as per error. Never returns.

section .note.GNU-stack noalloc noexec                   ; required Linux marker: stack is not exec
