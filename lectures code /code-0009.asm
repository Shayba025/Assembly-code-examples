;;; ============================================================================
;;; code-0009.asm -- Factorial, computed ITERATIVELY, argument on the cmd line
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Reads n from the command line and prints n!. It is the first of a trio --
;;;   compare it directly with code-0010 (recursive, C calling convention) and
;;;   code-0011 (recursive, Pascal calling convention). Same answer, three
;;;   completely different shapes.
;;;
;;;   THE THREE NEW INSTRUCTIONS, and they all have sharp edges:
;;;
;;;   * `mul rcx` -- UNSIGNED multiply. It is a ONE-OPERAND instruction with two
;;;     hidden registers: it always multiplies rax by the operand and always
;;;     writes the 128-bit product into RDX:RAX (high half in rdx, low half in
;;;     rax). You do not get to choose. Its signed twin is `imul`, which also
;;;     has friendlier two- and three-operand forms.
;;;
;;;   * `cqo` -- Convert Quadword to Octoword: sign-extend rax into rdx, i.e.
;;;     fill rdx with copies of rax's sign bit. It is the standard preparation
;;;     for `idiv`, which READS rdx:rax as its dividend.
;;;     SUBTLETY WORTH KNOWING: `mul` does not read rdx at all -- it only writes
;;;     it. So the `cqo` in the loop below is harmless but does nothing. Step
;;;     through it in gdb and watch rdx get set by cqo and then immediately
;;;     overwritten by mul. Keep `cqo` firmly associated with DIVISION.
;;;
;;;   * `loopnz .loop` -- decrement rcx, then jump if rcx != 0 AND ZF == 0. So
;;;     rcx is a hard-wired counter. THE PROFESSOR'S COMMENT "LOOPNZ is not
;;;     WHILE!" is the point: `loop`-family instructions test AFTER
;;;     decrementing, so entering with rcx = 0 would wrap around to 2^64-1 and
;;;     run essentially forever. That is why n == 0 is checked and dispatched
;;;     BEFORE the loop is ever entered. (The ZF half of the condition is a
;;;     second sharp edge: `mul` leaves ZF architecturally undefined, so this
;;;     loop leans on behaviour you should not rely on in your own code -- use
;;;     plain `loop`, or `dec`/`jnz`, when the flags are not yours.)
;;;
;;;   WHY LIMIT = 20: 20! = 2432902008176640000, which fits in a signed 64-bit
;;;   register; 21! does not. The bound is a correctness requirement, not a
;;;   style choice.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0009.asm" 5          # 120
;;;   ./asm "lectures code /code-0009.asm" 0          # 1
;;;   ./asm "lectures code /code-0009.asm" 20         # 2432902008176640000
;;;   ./asm "lectures code /code-0009.asm" 21         # usage error (overflow)
;;;   ./asm "lectures code /code-0009.asm" -1         # usage error
;;;   ./asm "lectures code /code-0009.asm"            # usage error
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0009.asm" 5
;;;
;;;   Useful session -- watch the accumulator and the counter move together:
;;;     break code-0009.asm:NN     put NN on the `mul rcx` line
;;;     c
;;;     info registers rax rcx rdx
;;;     si si si                   cqo, mul, loopnz
;;;     info registers rax rcx rdx again -- rax grew, rcx shrank by one
;;;     c                          repeat and watch 1,5,20,60,120 appear
;;;
;;;   The experiment that teaches `mul`: at the `mul rcx` line, do
;;;     set $rdx = 0xdeadbeef      poison rdx
;;;     si                         execute the mul
;;;     p/x $rdx                   0 -- your poison is gone, unread.
;;;   That is the proof that `mul` writes rdx but never reads it, and therefore
;;;   that the preceding `cqo` cannot matter.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Break on `printf` and type `bt`. Two frames: printf and main. Now run it
;;;   with n = 20 and do the same. STILL two frames. The stack does not know or
;;;   care that twenty multiplications happened, because a LOOP reuses one frame
;;;   forever.
;;;
;;;   Keep that picture. Then open code-0010, which computes the identical
;;;   answer recursively, break on `fact`, run with 20, and type `bt`: you will
;;;   get twenty-one frames. The two programs differ in memory cost by a factor
;;;   of n even though they differ in output by nothing at all. `p $rsp` at the
;;;   deepest point of each and subtract -- that difference, in bytes, is the
;;;   price of recursion, and it is the single most useful number to be able to
;;;   estimate when you choose between the two shapes.
;;;
;;;   Also note where this program keeps its state: entirely in registers (rax
;;;   the accumulator, rcx the counter). No `.bss`, no stack locals, no pushes.
;;;   That is only possible because nothing is called from inside the loop. The
;;;   moment a loop body contains a `call`, caller-saved registers stop being
;;;   safe -- exactly the problem code-0002 and code-0003 had to solve.
;;; ============================================================================

        LIMIT equ 20                                     ; `equ` = an assemble-time constant, not a variable.
                                                         ;   20! is the largest factorial that fits in 64
                                                         ;   bits (2432902008176640000 < 2^63).

section .data                                            ; initialised, writable data
fmt_output:
        db `Answer: %lld\n\0`                            ; printf format: one 64-bit signed decimal
fmt_usage:
        db `Usage: code-0009 n, where 0 <= n <= 20\n\0`  ; the error message

extern printf, fprintf, atoll, exit, stderr              ; supplied by the C library
global main                                              ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- read n, compute n! in a loop, print it.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 on bad input
;;;   Registers   : rax = the running product, rcx = the loop counter (which
;;;                 counts DOWN, so the product is built n * (n-1) * ... * 1)
;;;   How it works: validate, then a `loopnz` countdown that multiplies the
;;;                 accumulator by the counter each pass. Everything lives in
;;;                 registers; the stack is never touched after the prologue.
;;; ----------------------------------------------------------------------------
main:
        push rbp                                         ; back up the frame-pointer (rbp is callee-saved)
        mov rbp, rsp                                     ; set fp to the base of current frame -- the anchor
        and rsp, -16                                     ; align stack by 16 (for printf/scanf): clear the
                                                         ;   low 4 bits of rsp, as every `call` requires

        cmp rdi, 2                                       ; argc == 2 -- `cmp` subtracts, keeps only the flags
        jne .usage                                       ; print usage if not (`jne` = jump if not equal)

        mov rdi, qword [rsi + 8*1]                       ; get argv[1] -- rsi is argv, and base+8*index
                                                         ;   selects element 1, a char*
        call atoll                                       ; convert to a 64-bit integer.
                                                         ;   long long atoll(const char *): pointer in rdi,
                                                         ;   result in rax.
        mov rcx, rax                                     ; prepare to iterate! rcx is the counter `loopnz`
                                                         ;   decrements -- the register is not optional, it
                                                         ;   is wired into the instruction.
        mov rax, 1                                       ; initialize accumulator: the empty product is 1
        cmp rcx, 0                                       ; must test, because LOOPNZ is not WHILE!
                                                         ;   `loopnz` decrements FIRST and tests after, so
                                                         ;   entering with rcx = 0 would wrap to 2^64-1.
        jl .usage                                        ; print usage if negative (`jl` = jump if less,
                                                         ;   SIGNED -- essential, atoll can return < 0)
        je .finished                                     ; print 1 if done: 0! = 1, and rax already holds 1
        cmp rcx, LIMIT                                   ; (LIMIT + 1)! > 2^64...
        jg .usage                                        ; print usage if input is too large

.loop:
        cqo                                              ; extend RAX to RDX:RAX. Sign-extends rax into rdx.
                                                         ;   Harmless here but unnecessary -- `mul` below
                                                         ;   OVERWRITES rdx and never reads it. `cqo` is the
                                                         ;   partner of `idiv`, not of `mul`. (See the gdb
                                                         ;   poison experiment in the header.)
        mul rcx                                          ; multiply by counter. One-operand UNSIGNED
                                                         ;   multiply: RDX:RAX := RAX * rcx. The low 64 bits
                                                         ;   land in rax -- our accumulator -- and the high
                                                         ;   64 in rdx, which the LIMIT check guarantees is
                                                         ;   zero.
        loopnz .loop                                     ; loop if positive. Decrement rcx, then jump back
                                                         ;   if rcx != 0 AND ZF == 0. So the counter walks
                                                         ;   n, n-1, ..., 1 and the products accumulate.

.finished:
        mov rdi, fmt_output                              ; format string for output (printf argument 1)
        mov rsi, rax                                     ; n! (printf argument 2)
        mov rax, 0                                       ; no fp registers in use -- the variadic rule
        call printf
        jmp .done                                        ; (a jump to the very next line: harmless, and a
                                                         ;   leftover from an earlier version of the file)

.done:
        mov rax, 0                                       ; status OK for OS

        mov rsp, rbp                                     ; restore original stack-pointer from the anchor
        pop rbp                                          ; set fp to point to previous frame
        ret                                              ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; main.usage -- bad or missing argument. NEVER RETURNS.
;;;   Writes the usage line to stderr and terminates the process with status -1.
;;;   Reached from four different tests above: wrong argc, negative n, and n
;;;   greater than LIMIT.
;;; ----------------------------------------------------------------------------
.usage:
        mov rdi, qword [stderr]                          ; errors go to stderr. The brackets matter:
                                                         ;   `stderr` is a VARIABLE holding a FILE*, so we
                                                         ;   load its contents, not its address.
        mov rsi, fmt_usage                               ; explain correct usage (argument 2 -- fprintf's
                                                         ;   first argument is the stream)
        mov rax, 0                                       ; no fp registers in use
        call fprintf                                     ; send output to stderr...

        mov rax, -1                                      ; status NOT OK
        call exit                                        ; exit as per error. (exit() reads its argument
                                                         ;   from rdi, not rax -- check `p $rdi` here.)
                                                         ;   Never returns, so no epilogue follows.

section .note.GNU-stack noalloc noexec                   ; required Linux marker: stack is not exec
