;;; ============================================================================
;;; code-0010.asm -- Factorial computed RECURSIVELY, C-style calling convention
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   The same n! as code-0009, but recursively, and with the argument passed ON
;;;   THE STACK rather than in a register. Read this file together with its twin
;;;   code-0011, which is byte-for-byte identical except for who cleans up the
;;;   pushed argument. That single difference is the whole lesson.
;;;
;;;   THE CALLING CONVENTION ON DISPLAY: "C-style", also called `cdecl`.
;;;       * the CALLER pushes the arguments
;;;       * the CALLER removes them afterwards, with `add rsp, 8*k`
;;;       * the callee returns with a plain `ret`
;;;   Why would anyone do it this way? Because the caller is the only one who
;;;   knows how many arguments it actually pushed. That is what makes VARIADIC
;;;   functions like printf possible at all -- printf itself cannot know, so it
;;;   must not be responsible for the cleanup. Every variadic C function in
;;;   existence is a consequence of this one design decision.
;;;
;;;   (Note this is the CLASSIC C convention, used here for teaching. The modern
;;;   64-bit System V ABI that printf and atoll actually use passes the first six
;;;   integer arguments in registers -- rdi, rsi, rdx, rcx, r8, r9 -- and only
;;;   spills to the stack beyond that. `fact` here is deliberately old-fashioned
;;;   so you can watch the mechanism.)
;;;
;;;   THE ACTIVATION FRAME. The professor's diagram inside `fact` is the single
;;;   most important picture in this course:
;;;
;;;       higher addresses
;;;         [rbp + 8*2]   n            <- pushed by the caller, BEFORE the call
;;;         [rbp + 8*1]   ret addr     <- pushed by `call` itself
;;;         [rbp + 8*0]   old rbp      <- pushed by `push rbp` in the prologue
;;;       rbp points here
;;;         [rbp - 8*1]   (locals would go here)
;;;       lower addresses
;;;
;;;   Positive offsets from rbp reach BACKWARD in time -- to what the caller set
;;;   up. Negative offsets are your own scratch space. Every stack frame you
;;;   will ever disassemble, in any language, has this shape.
;;;
;;;   WHY THE ARGUMENT IS RE-READ FROM THE STACK. Look at the multiply:
;;;       mul qword [rbp + 8*2]
;;;   It does not use a register copy of n, because the recursive `call fact`
;;;   in between is entitled to destroy every caller-saved register. The stack
;;;   slot is private to THIS activation and survives the call untouched. That
;;;   is the whole reason arguments live in frames.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0010.asm" 5          # 120
;;;   ./asm "lectures code /code-0010.asm" 0          # 1
;;;   ./asm "lectures code /code-0010.asm" 20         # 2432902008176640000
;;;   ./asm "lectures code /code-0010.asm" 21         # usage error
;;;   ./asm "lectures code /code-0010.asm" -1         # usage error
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0010.asm" 5
;;;
;;;   Useful session:
;;;     break fact             stop on every recursive entry
;;;     c c c                  descend a few levels
;;;     bt                     the recursion, laid out as frames
;;;     p $rsp                 note how it drops by 24 bytes per level:
;;;                            8 (pushed n) + 8 (return addr) + 8 (saved rbp)
;;;     x/1gd $rbp+16          THIS level's n
;;;     up                     move the cursor one frame outward
;;;     x/1gd $rbp+16          the CALLER's n -- one larger. Do it again.
;;;     down                   come back
;;;     finish                 unwind one level; p $rax to see the partial answer
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   This is THE file for understanding the stack. Run with n = 5, break on
;;;   `fact`, and continue until the base case. `bt` will show six frames of
;;;   `fact` plus `main`. Then walk out with repeated `finish` and watch rax
;;;   climb 1, 1, 2, 6, 24, 120 as each suspended multiplication finally runs.
;;;   The multiplications happen on the way BACK OUT, in the opposite order from
;;;   the calls -- and the stack is what remembered them.
;;;
;;;   Now measure the cost. At the deepest frame:
;;;       p $rsp
;;;   and at `main`:
;;;       p $rsp
;;;   Subtract. It will be about 24 * n bytes. Rerun with n = 20 and confirm the
;;;   difference scales. code-0009 computes the identical answer with ZERO extra
;;;   bytes. That is the trade you are making every time you choose recursion.
;;;
;;;   THE EXPERIMENT THAT MAKES THE CONVENTION VISIBLE. Break right after
;;;   `call fact` returns to main, and single-step the `add rsp, 8*1`:
;;;       p $rsp        before
;;;       si
;;;       p $rsp        8 higher -- the pushed n is gone
;;;   That one instruction IS the C calling convention. Delete it and the stack
;;;   leaks 8 bytes per call; do it in a loop and you exhaust the stack. Now
;;;   open code-0011 and look for the same instruction: it is not there, because
;;;   `ret 8*1` at the end of `fact` does the job instead. Two files, one
;;;   instruction moved from caller to callee -- that is the entire difference
;;;   between C and Pascal conventions.
;;;
;;;   One more thing to look at, since it costs nothing: `x/1gx $rbp` at any
;;;   level prints the SAVED rbp, which is the rbp of the frame above. Follow it
;;;   by hand -- `x/1gx` on the value you just printed -- and you are walking the
;;;   frame-pointer chain manually, doing exactly what `bt` does for you.
;;; ============================================================================

        LIMIT equ 20                                     ; `equ` = an assemble-time constant. 20! is the
                                                         ;   largest factorial that fits in 64 bits.

section .data                                            ; initialised, writable data
fmt_output:
        db `Answer: %lld\n\0`                            ; printf format: one 64-bit signed decimal
fmt_usage:
        db `Usage: code-0010 n, where 0 <= n <= 20\n\0`  ; the error message

extern printf, fprintf, atoll, exit, stderr              ; supplied by the C library
global main                                              ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- validate n, call fact(n) C-style, print the result.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 on bad input
;;;   How it works: pushes n, calls fact, and then -- being the C-style CALLER --
;;;                 removes the pushed argument itself with `add rsp, 8*1`.
;;; ----------------------------------------------------------------------------
main:
        push rbp                                         ; back up the frame-pointer (rbp is callee-saved)
        mov rbp, rsp                                     ; set fp to the base of current frame -- the anchor
        and rsp, -16                                     ; align stack by 16 bytes (for printf/scanf) by
                                                         ;   clearing rsp's low 4 bits

        cmp rdi, 2                                       ; argc == 2 -- subtract, keep only the flags
        jne .usage                                       ; print usage if not

        mov rdi, qword [rsi + 8*1]                       ; get argv[1]: rsi is argv, base+8*1 is element 1
        call atoll                                       ; convert to a 64-bit integer -> rax
        cmp rax, 0                                       ; test if negative
        jl .usage                                        ; print usage if negative (`jl` = signed less-than)
        cmp rax, LIMIT                                   ; (LIMIT + 1)! > 2^64
        jg .usage                                        ; print usage if input is too large

        push rax                                         ; push n. THE ARGUMENT GOES ON THE STACK, not in a
                                                         ;   register: this is the classic C convention the
                                                         ;   file is demonstrating. rsp drops by 8.
        call fact                                        ; call fact. `call` pushes the return address (rsp
                                                         ;   drops another 8) and jumps. Inside fact, n is
                                                         ;   therefore at [rbp + 8*2] once rbp is set up.
        add rsp, 8*1                                     ; C-style: Caller cleans the stack!
                                                         ;   Undo our own `push rax`. The callee did NOT do
                                                         ;   this -- compare `ret 8*1` in code-0011. This is
                                                         ;   what makes variadic functions possible: only the
                                                         ;   caller knows how many arguments it pushed.

        mov rdi, fmt_output                              ; format string for output (printf argument 1)
        mov rsi, rax                                     ; n! -- fact's return value, in rax as always
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
;;; fact -- n! by recursion, C-style (caller-cleans) calling convention.
;;;   Pseudo-C   : long long fact(long long n)
;;;                { return n == 0 ? 1 : n * fact(n - 1); }
;;;   Receives   : n on the STACK, at [rbp + 8*2] once the prologue has run
;;;   Returns    : rax = n!
;;;   Clobbers   : rax, rdx (mul writes the high half of the product there)
;;;   Cleanup    : NONE -- the caller does it. This function ends with a plain
;;;                `ret`, and every call site must follow it with `add rsp, 8`.
;;;   Stack cost : 24 bytes per level (argument + return address + saved rbp),
;;;                so depth n costs about 24n bytes.
;;;
;;;   How it works: reads n from its own frame, and if n is zero returns 1.
;;;   Otherwise it pushes n-1, recurses, cleans up, and multiplies the returned
;;;   (n-1)! by n -- re-read from the STACK, because the recursive call has
;;;   destroyed every caller-saved register in the meantime.
;;; ----------------------------------------------------------------------------
fact:
        push rbp                                         ; back up the frame-pointer. rsp drops by 8; the
                                                         ;   caller's rbp is now safe at [rsp].
        mov rbp, rsp                                     ; set fp to the base of the current frame. From
                                                         ;   this instant the offsets in the diagram below
                                                         ;   are valid and stay valid for this activation.

;;; The structure of the activation frame:
;;; |         | n        | qword [rbp + 8*2] |
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
                                                         ; Read upward from rbp: our own saved rbp, then the
                                                         ;   return address `call` pushed, then the argument
                                                         ;   the caller pushed before that. Three quadwords,
                                                         ;   in the order they were pushed, newest lowest.

        mov rax, qword [rbp + 8*2]                       ; rax <-- n. Fetched from OUR frame, which no
                                                         ;   callee can disturb.
        cmp rax, 0                                       ; n = 0?
        je .zero                                         ; return 1 -- the BASE CASE that stops the recursion
        dec rax                                          ; compute n-1 (`dec` subtracts 1 in place)
        push rax                                         ; push n-1 -- the argument for the recursive call,
                                                         ;   in the caller's-responsibility C style
        call fact                                        ; compute fact(n - 1) --> rax. Pushes a return
                                                         ;   address pointing at the next line, which is how
                                                         ;   the multiplication below eventually happens.
        add rsp, 8*1                                     ; C-style: caller cleans the stack!
                                                         ;   We are the caller of this inner call, so we
                                                         ;   remove the n-1 we pushed.
        cqo                                              ; extend RAX --> RDX:RAX. Sign-extends rax into rdx.
                                                         ;   Not actually needed before `mul`, which writes
                                                         ;   rdx without reading it; `cqo` belongs with
                                                         ;   `idiv`. Harmless here.
        mul qword [rbp + 8*2]                            ; RDX:RAX = n * fact(n - 1). One-operand UNSIGNED
                                                         ;   multiply: rax (the recursive result) times the
                                                         ;   memory operand (our own n), product into
                                                         ;   RDX:RAX. Note n is RE-READ FROM THE FRAME -- a
                                                         ;   register copy would have been destroyed by the
                                                         ;   recursive call.
        jmp .done                                        ; skip the base-case assignment
.zero:
        mov rax, 1                                       ; fact(0) = 1
.done:
        mov rsp, rbp                                     ; restore original stack-pointer from the anchor
        pop rbp                                          ; set fp to point to previous frame
        ret                                              ; plain `ret`: pop the return address into rip and
                                                         ;   LEAVE THE ARGUMENT WHERE IT IS. Cleaning it up
                                                         ;   is the caller's job. Contrast `ret 8*1` in
                                                         ;   code-0011.

section .note.GNU-stack noalloc noexec                   ; required Linux marker: stack is not exec
