;;; ============================================================================
;;; code-0001.asm -- Read two integers from stdin, print the larger one
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prompts, reads two integers with scanf, and prints whichever is bigger.
;;;   It is the first example that actually CALLS C library functions, so it
;;;   introduces the three rules you will use for the rest of the course:
;;;
;;;   1. ARGUMENTS GO IN REGISTERS, in this fixed order (System V AMD64 ABI):
;;;          rdi, rsi, rdx, rcx, r8, r9     then the stack for the 7th onward.
;;;   2. FOR VARIADIC FUNCTIONS (printf, scanf, ...) rax must hold the number of
;;;      vector (floating-point) registers used. We pass no floats, so rax = 0.
;;;      Forget this and printf may crash or print garbage.
;;;   3. THE STACK MUST BE 16-BYTE ALIGNED at the moment you execute `call`.
;;;      That is what `and rsp, -16` is for.
;;;
;;;   It also shows the branch-free-ish idiom for max: assume the first value
;;;   wins, then overwrite only if you were wrong.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0001.asm"
;;;
;;;   It waits for input. Type two integers separated by a comma, e.g.  3, 9
;;;   (the format string is "%ld, %ld", so the comma matters). Or pipe it in:
;;;   echo "3, 9" | ./asm "lectures code /code-0001.asm"
;;;
;;; DEBUG IT
;;;   echo "3, 9" | ./debug "lectures code /code-0001.asm"     # scripted input
;;;   ./debug "lectures code /code-0001.asm"                   # or type it live
;;;
;;;   Useful session:
;;;     break scanf         stop just before the C library reads
;;;     c                   continue until you hit it
;;;     info registers rdi rsi rdx rax
;;;                         rdi = format string, rsi = &a, rdx = &b, rax = 0
;;;     x/s $rdi            print the format string rdi points at
;;;     finish              run scanf to completion and come back
;;;     x/1gd &a            look at the quadword now stored in `a`
;;;     x/1gd &b            ... and in `b`
;;;     break *(main+NN)    or just `si` your way down to the cmp
;;;     info registers eflags
;;;                         after `cmp`, this is where the answer lives
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Stop at `main` and run `bt`. One frame of yours, then the C library. Now
;;;   `break printf`, `c`, and `bt` again:
;;;       #0  printf (...)
;;;       #1  main () at code-0001.asm:NN
;;;   Frame #1 did not disappear while #0 runs -- `main` is SUSPENDED, its
;;;   return address and saved rbp still sitting on the stack, waiting. That is
;;;   the whole idea of a call stack: an unfinished-business list.
;;;
;;;   The lesson specific to THIS file is the prologue/epilogue pair. Do:
;;;       p $rsp        right at `main`, before `push rbp`
;;;       si  si  si    execute push rbp / mov rbp,rsp / and rsp,-16
;;;       p $rsp        rsp dropped by 8 (the push) and then down to a
;;;                     multiple of 16 (the and)
;;;       p $rbp        rbp now marks the fixed base of this frame
;;;   rsp wanders as you push and pop; rbp does not. That is exactly why the
;;;   epilogue is `mov rsp, rbp` then `pop rbp`: restoring rsp from the anchor
;;;   undoes the alignment fiddling in one step, no matter what happened between.
;;;   Check `x/1gx $rsp` right before `ret` -- that quadword is the return
;;;   address into the C library, and it is the only thing `ret` needs.
;;; ============================================================================

section .data			; `.data` = initialised, writable memory. Anything
				;   you spell out here occupies real bytes in the
				;   executable file.
fmt_prompt_for_input:		; label = the address of the bytes that follow
	db `Enter two integers, a, b: \0`
				; `db` ("define byte") emits raw bytes. NASM's
				;   BACKQUOTED string is the only kind that expands
				;   escapes, so \0 really becomes byte 0 -- the NUL
				;   terminator every C string must end with.
fmt_input:
	db `%ld, %ld\0`		; scanf's format: two `long` decimals separated by
				;   a comma and optional space. %ld = 64-bit signed.
fmt_output:
	db `The max value is %ld\n\0` ; printf's format. \n = newline (byte 10).

section .bss			; `.bss` = zero-initialised, writable memory. It
				;   costs NO space in the file on disk; the loader
				;   just zeroes it at start-up. Use it for
				;   variables whose initial value you don't care
				;   about.
a:
	resq 1			; `resq n` RESERVES n quadwords (n * 8 bytes).
				;   So `a` is one 64-bit slot.
b:
	resq 1			; likewise `b`.

extern printf, scanf		; `extern` declares symbols defined ELSEWHERE
				;   (here: in the C library). It generates no code;
				;   it just stops NASM complaining and leaves the
				;   linker to fill in the real addresses.
global main			; export `main` so the C library start-up can call it

section .text			; back to the executable-code section
;;; ----------------------------------------------------------------------------
;;; main -- prompt, read two longs, print the maximum.
;;;   C signature : int main(void)
;;;   Uses        : the globals `a` and `b` in .bss as scanf's output slots
;;;   Returns     : rax = 0
;;;   How it works: build a standard stack frame, make three C library calls in
;;;                 sequence, and between the 2nd and 3rd pick the max with a
;;;                 compare-and-conditional-jump.
;;; ----------------------------------------------------------------------------
main:
	push rbp		; `push src` = subtract 8 from rsp, then store src
				;   at [rsp]. This SAVES the caller's frame pointer,
				;   because rbp is callee-saved: we must give it
				;   back unchanged. First half of the prologue.
	mov rbp, rsp		; copy the current stack top into rbp, making rbp
				;   the fixed ANCHOR of our frame. From now on every
				;   local can be addressed as [rbp - k], which never
				;   shifts even as rsp moves.
	and rsp, -16		; `and dst, src` = bitwise AND. -16 is 0xFFFF...F0,
				;   i.e. all ones except the low 4 bits, so this
				;   clears the low 4 bits of rsp: it rounds rsp DOWN
				;   to a multiple of 16. The ABI requires 16-byte
				;   stack alignment at every `call`; SSE
				;   instructions inside printf will fault otherwise.

	; printf(fmt_prompt_for_input)
	mov rdi, fmt_prompt_for_input ; 1st argument goes in rdi. A bare label used
				      ;   as a value is its ADDRESS, so this loads a
				      ;   pointer to the string, not the string.
	mov rax, 0		      ; variadic rule: rax = how many vector (xmm)
				      ;   registers carry arguments. Zero floats here.
	call printf		      ; `call` pushes the address of the NEXT
				      ;   instruction (the return address) and jumps.
				      ;   That push is why the stack had to be
				      ;   aligned first.

	; scanf(fmt_input, &a, &b)
	mov rdi, fmt_input	; 1st argument: the format string
	mov rsi, a		; 2nd argument: the ADDRESS of a. scanf must be
				;   able to write into it, so it needs a pointer --
				;   this is `&a` in C.
	mov rdx, b		; 3rd argument: the address of b
	mov rax, 0		; again: no floating-point arguments
	call scanf		; reads from stdin and stores into [a] and [b]

	; printf(fmt_output, (a > b) ? a : b)
	mov rdi, fmt_output	; 1st argument: the output format string
	mov rsi, qword [a]	; SQUARE BRACKETS mean "the contents of that
				;   address". Without them we would load the
				;   address itself. `qword` tells NASM the access
				;   is 8 bytes wide. So: rsi = a. We optimistically
				;   assume a is the maximum.
	mov rax, qword [b]	; rax = b, used here purely as a scratch register
	cmp rsi, rax		; `cmp x, y` computes x - y and THROWS THE RESULT
				;   AWAY, keeping only the flags. It is a subtract
				;   whose only product is "how do these compare".
	jg .continue		; `jg` = jump if greater (signed). It reads the
				;   flags cmp just set. If a > b our guess was
				;   right, so skip the fix-up.
	mov rsi, rax		; we get here only when a <= b, so b is the max:
				;   overwrite the argument register with b.
.continue:			; a label starting with '.' is LOCAL: it belongs to
				;   the preceding non-local label (`main`), so other
				;   functions may reuse the name `.continue`.
	mov rax, 0		; no floating-point arguments to printf
	call printf		; prints "The max value is <n>"

	mov rax, 0		; the value main returns to the C library, which
				;   passes it to the shell as the exit status.
				;   0 = success by universal convention.

	mov rsp, rbp		; EPILOGUE, step 1: throw away everything this
				;   frame did to rsp (including the alignment) by
				;   restoring it from the anchor.
	pop rbp			; step 2: `pop dst` loads [rsp] into dst and adds 8
				;   to rsp. This restores the CALLER's frame pointer
				;   that we pushed on entry.
	ret			; pop the return address into rip -- back into the
				;   C library, which will call exit(rax).

section .note.GNU-stack noalloc noexec ; "this program does not need an executable
				;   stack" -- required boilerplate on Linux.
