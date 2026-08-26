;;; ============================================================================
;;; code-0005.asm -- A control paradigm inspired by BALR and CPS: `between`
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Takes one integer on the command line and reports its order of magnitude:
;;;   "in the thousands", "a single digit (unit)", "a negative number", and so on.
;;;
;;;   Functionally that is a boring cascade of range tests. The POINT of the file
;;;   is HOW the cascade is written. Instead of `if`/`else if`, it uses a single
;;;   reusable subroutine `between` that is handed FOUR values:
;;;
;;;       rdi = the number n            rsi = the lower bound
;;;       rdx = the upper bound         rcx = where to go if n IS in range
;;;                                     r8  = where to go if it is NOT
;;;
;;;   and which finishes with `jmp rcx` or `jmp r8`. Note what is missing:
;;;   there is no `call` and no `ret` anywhere near it. `between` never returns
;;;   to its caller -- it JUMPS ONWARD to whichever address it was told to.
;;;
;;;   TWO CLASSICAL IDEAS ARE ON DISPLAY HERE:
;;;
;;;   * BALR (Branch And Link Register), from IBM System/360. Before hardware
;;;     had a call stack, you called a subroutine by putting the return address
;;;     in a register and branching; the subroutine returned by branching to
;;;     that register. Here rcx and r8 are exactly that -- addresses held in
;;;     registers and jumped to indirectly (`jmp rcx` is a computed jump, and
;;;     the jump target is data).
;;;
;;;   * CPS (Continuation-Passing Style), from Scheme and functional programming.
;;;     A function is given "what to do next" as an explicit argument instead of
;;;     returning. `between` gets TWO continuations, one per answer, and picks.
;;;     `.continue8`, `.continue7`, ... are the "and then carry on here" labels
;;;     that chain the tests together.
;;;
;;;   The result is a program that is entirely FLAT: no nesting, no stack growth,
;;;   and one shared comparison routine reused nine times. It also costs nothing
;;;   at run time -- an indirect jump is cheaper than a call/return pair.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0005.asm" 7
;;;   ./asm "lectures code /code-0005.asm" 42
;;;   ./asm "lectures code /code-0005.asm" 5000
;;;   ./asm "lectures code /code-0005.asm" 123456789
;;;   ./asm "lectures code /code-0005.asm" 9999999999
;;;   ./asm "lectures code /code-0005.asm" -3
;;;   ./asm "lectures code /code-0005.asm"          # usage error on stderr
;;;
;;;   To convince yourself stderr really is separate, throw stdout away:
;;;   ./asm "lectures code /code-0005.asm" >/dev/null
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0005.asm" 5000
;;;
;;;   Useful session:
;;;     break between          stop every time the shared routine runs
;;;     c                      continue to the first test
;;;     info registers rdi rsi rdx rcx r8
;;;                            n, lo, hi, and the two continuation ADDRESSES
;;;     info symbol $rcx       ask gdb which label rcx holds -- it will answer
;;;                            with a name like `main.hundreds_of_millions`
;;;     info symbol $r8        ... and the "keep testing" label
;;;     c                      round again; watch the bounds shrink by 10x
;;;     bt                     see below -- this is the interesting part
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Break on `between`, continue a few times, and type `bt` at each stop. The
;;;   backtrace never grows. In fact it shows only `main`, because control
;;;   ARRIVED at `between` by `jmp`, not by `call`: nothing was pushed, so there
;;;   is no frame for `between` at all. gdb may even show the line as being
;;;   inside `main`, and that is the honest answer -- as far as the stack is
;;;   concerned, it still is.
;;;
;;;   Prove it to yourself:
;;;       p $rsp        at `main`, right after `and rsp, -16`
;;;       break between
;;;       c
;;;       p $rsp        identical. Nine "subroutine invocations" later, still
;;;                     identical.
;;;   Compare with code-0004, where every `call bin` visibly lowered rsp by 8.
;;;   That is the whole distinction: `call` = "go there AND remember to come
;;;   back" (costs 8 bytes of stack); `jmp` = "go there" (costs nothing).
;;;
;;;   The follow-up question worth sitting with: if `between` does not return,
;;;   how does the program ever get back to printing? It doesn't get back -- it
;;;   goes FORWARD. rcx and r8 are the return addresses, just handed over
;;;   explicitly in registers instead of implicitly on the stack. Do
;;;       info symbol $r8
;;;   and you are literally reading the return address, in a register, with your
;;;   own eyes. Once you see that a stack is only a convenient DEFAULT place to
;;;   keep continuations, `call` and `ret` stop being magic.
;;;
;;;   One last experiment: `x/3i $rcx` disassembles the three instructions at the
;;;   address rcx points to. You will see the `mov rdi, fmt_...` / `jmp .print`
;;;   pair -- proof that a code address is just a number you can inspect.
;;; ============================================================================

section .data			; initialised, writable memory
fmt_long:
	db `%llu\0`		; %llu = unsigned long long. Declared but never
				;   used in this program -- left over scaffolding.
fmt_bom:
	db `a billion or more\n\0`	; "bom" = billions-or-more
fmt_hom:
	db `in the hundreds of millions\n\0`   ; "hom"
fmt_tom:
	db `in the tens of millions\n\0`       ; "tom"
fmt_m:
	db `in the millions\n\0`
fmt_hot:
	db `in the hundreds of thousands\n\0`  ; "hot"
fmt_tot:
	db `in the tens of thousands\n\0`      ; "tot"
fmt_t:
	db `in the thousands\n\0`
fmt_h:
	db `in the hundreds\n\0`
fmt_tens:
	db `in the tens\n\0`
fmt_u:
	db `a single digit (unit)\n\0`
fmt_n:
	db `a negative number\n\0`
fmt_usage:
	db `Usage: code-0005 <integer>\n\0`
				; every one of these is a plain NUL-terminated C
				;   string; `db` emits the bytes, backquotes make
				;   \n and \0 real control characters.

extern atoll, printf, fprintf, stderr, exit ; supplied by the C library
global main			; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- classify the command-line number by order of magnitude.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0 (or exits with -1 on a usage error)
;;;   How it works: after converting argv[1] with atoll, it keeps the number in
;;;                 rdi for the whole program and runs a chain of range tests.
;;;                 Each test loads (lo, hi, hit-label, miss-label) and jumps to
;;;                 the shared `between`; `between` jumps to one of the two
;;;                 labels. The "miss" label is always the NEXT test, so the
;;;                 chain walks down through the decades until something matches
;;;                 or it falls off the bottom into .negative.
;;;
;;;   REGISTER CONTRACT used throughout (mirrors the comment above `between`):
;;;       rdi = n   rsi = lo   rdx = hi   rcx = if-inside   r8 = if-outside
;;; ----------------------------------------------------------------------------
main:
	push rbp		; save the old frame-pointer (rbp is callee-saved)
	mov rbp, rsp		; establish new frame-pointer: the fixed anchor
	and rsp, -16		; align the stack downward at the 16-byte level by
				;   clearing rsp's low 4 bits (-16 = 0xFF..F0)

	cmp rdi, 2		; |argc| == 2?  `cmp` subtracts, keeps only flags
	jne .error_usage	; If not, print usage... (`jne` = jump if not equal)
	mov rdi, qword [rsi + 8*1] ; rdi <-- arg[1]. rsi is still argv; base +
				;   8*index picks element 1, a char*.
	call atoll		; convert to a 64 bit integer --> rax.
				;   long long atoll(const char *) -- pointer in
				;   rdi, result in rax.

	mov rdi, rax		; load the number from the command-line. From here
				;   to the end, rdi means "n" and nothing else.
	mov rsi, 1000000000	; compare to upper limit
	cmp rdi, rsi		; n - 1000000000, flags only
	jge .billions_or_more	; `jge` = jump if greater or equal, SIGNED. Handled
				;   specially because there is no upper bound above
				;   this one, so `between` cannot express it.

	mov rsi, 100000000	; lower limit
	mov rdx, 999999999	; upper limit
	mov rcx, .hundreds_of_millions ; the continuation if n IS in range
	mov r8, .continue8	; the continuation if it is NOT: the next test.
				;   Loading a label into a register loads its
				;   ADDRESS -- code addresses are ordinary numbers.
	jmp between		; note: JMP, not CALL. Nothing is pushed; we hand
				;   control over for good.
.continue8:			; <-- r8 above pointed here; this is where a "no"
				;   answer resumes
	mov rsi, 10000000	; lower limit
	mov rdx, 99999999	; upper limit
	mov rcx, .tens_of_millions ; continuation on success
	mov r8, .continue7	; continuation on failure
	jmp between		; tail-jump into the shared comparator
.continue7:
	mov rsi, 1000000	; lower limit
	mov rdx, 9999999	; upper limit
	mov rcx, .millions	; continuation on success
	mov r8, .continue6	; continuation on failure
	jmp between
.continue6:
	mov rsi, 100000		; lower limit
	mov rdx, 999999		; upper limit
	mov rcx, .hundreds_of_thousands ; continuation on success
	mov r8, .continue5	; continuation on failure
	jmp between
.continue5:
	mov rsi, 10000		; lower limit
	mov rdx, 99999		; upper limit
	mov rcx, .tens_of_thousands ; continuation on success
	mov r8, .continue4	; continuation on failure
	jmp between
.continue4:
	mov rsi, 1000		; lower limit
	mov rdx, 9999		; upper limit
	mov rcx, .thousands	; continuation on success
	mov r8, .continue3	; continuation on failure
	jmp between
.continue3:
	mov rsi, 100		; lower limit
	mov rdx, 999		; upper limit
	mov rcx, .hundreds	; continuation on success
	mov r8, .continue2	; continuation on failure
	jmp between
.continue2:
	mov rsi, 10		; lower limit
	mov rdx, 99		; upper limit
	mov rcx, .tens		; continuation on success
	mov r8, .continue1	; continuation on failure
	jmp between
.continue1:
	mov rsi, 0		; lower limit
	mov rdx, 9		; upper limit
	mov rcx, .units		; continuation on success
	mov r8, .negative	; the LAST link in the chain: anything that fails
				;   even [0,9] must be negative
	jmp between

;;; --- the eleven "answer" continuations. Each loads a string and converges on
;;; --- the single shared .print tail. This is the CPS pay-off: many entry
;;; --- points, one exit.
.billions_or_more:
	mov rdi, fmt_bom	; print string -- rdi is now printf's 1st argument,
				;   overwriting n, which is no longer needed
	jmp .print		; converge on the shared tail
.hundreds_of_millions:
	mov rdi, fmt_hom	; print string
	jmp .print
.tens_of_millions:
	mov rdi, fmt_tom	; print string
	jmp .print
.millions:
	mov rdi, fmt_m		; print string
	jmp .print
.hundreds_of_thousands:
	mov rdi, fmt_hot	; print string
	jmp .print
.tens_of_thousands:
	mov rdi, fmt_tot	; print string
	jmp .print
.thousands:
	mov rdi, fmt_t		; print string
	jmp .print
.hundreds:
	mov rdi, fmt_h		; print string
	jmp .print
.tens:
	mov rdi, fmt_tens	; print string
	jmp .print
.units:
	mov rdi, fmt_u		; print string
	jmp .print
.negative:
	mov rdi, fmt_n		; print string -- no `jmp .print` needed: .print is
				;   the very next line, so control FALLS THROUGH.
.print:				; the single shared exit path
	mov rax, 0		; 0 floating-point registers in use (variadic rule)
	call printf		; the only real `call` on the success path

	mov rax, 0		; return value to shell: OK

	mov rsp, rbp		; restore the stack-pointer from the anchor
	pop rbp			; restore the old frame-pointer
	ret			; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; main.error_usage -- bad command line. NEVER RETURNS.
;;;   Prints the usage message on stderr (not stdout) and terminates the process.
;;; ----------------------------------------------------------------------------
.error_usage:
	mov rdi, qword [stderr]	; FILE *stderr. The brackets matter: `stderr` is a
				;   VARIABLE holding a FILE*, so we must load its
				;   contents, not its address.
	mov rsi, fmt_usage	; format string -- argument 2, because fprintf's
				;   first argument is the stream
	mov rax, 0		; 0 floating-point registers in use
	call fprintf		; fprintf(stderr, fmt_usage)
	mov rax, -1		; return value to shell: error code
	call exit		; terminate. (exit() actually reads its argument
				;   from rdi, not rax -- inspect `p $rdi` here in
				;   gdb and compare with the intent.) Never returns,
				;   so no epilogue follows.

;;; ----------------------------------------------------------------------------
;;; between -- the shared, non-returning range test. THE POINT OF THIS FILE.
;;;
;;; Using between:
;;; | rdi | n               |
;;; | rsi | lower bound     |
;;; | rdx | upper bound     |
;;; | rcx | addr if inside  |
;;; | r8  | addr if outside |
;;;
;;;   Semantics  : if (lo <= n && n <= hi) goto rcx; else goto r8;
;;;   Reached by : `jmp between`, never `call between`
;;;   Returns    : NEVER. It transfers control onward to rcx or r8.
;;;   Stack cost : zero. Nothing is pushed, no frame is built, rsp is untouched.
;;;   Clobbers   : nothing at all -- it only reads registers and jumps.
;;;
;;;   How it works: two signed comparisons and a short-circuit. Fail either one
;;;   and you land on .L, whose only job is to jump to the "outside"
;;;   continuation. Pass both and you fall through to `jmp rcx`.
;;;
;;;   `jmp rcx` is an INDIRECT (computed) jump: the target is the VALUE in the
;;;   register, decided at run time. This is the same machinery that implements
;;;   jump tables, switch statements, virtual method dispatch and function
;;;   pointers. Learn to read it here, where there are only two possibilities.
;;; ----------------------------------------------------------------------------
between:
	cmp rdi, rsi		; n - lo, flags only
	jl .L			; `jl` = jump if less (SIGNED). n < lo, so n is
				;   below the range: take the "outside" exit.
				;   Signedness is essential here -- negative inputs
				;   must compare as smaller, not as huge.
	cmp rdi, rdx		; n - hi, flags only
	jg .L			; `jg` = jump if greater (signed). n > hi: also
				;   outside.
	jmp rcx			; both tests passed => lo <= n <= hi. Jump to the
				;   "inside" continuation. INDIRECT jump: the target
				;   address is the contents of rcx.
.L:
	jmp r8			; the "outside" continuation, likewise indirect.
				;   Two lines up and one line down, and this single
				;   routine replaces nine if/else blocks.

section .note.GNU-stack noalloc noexec ; required Linux marker: stack is not exec
