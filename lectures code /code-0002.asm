;;; ============================================================================
;;; code-0002.asm -- Reading the command-line arguments passed to a program
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints how many command-line arguments it got, the name it was invoked
;;;   under, and then every remaining argument, one per line.
;;;
;;;   The point of the example is that `main` is an ORDINARY FUNCTION and gets
;;;   its parameters the ordinary way. In C you write
;;;       int main(int argc, char *argv[])
;;;   and in assembly that means, on entry to `main`:
;;;       rdi = argc   (the argument count, an int)
;;;       rsi = argv   (the address of an array of char* pointers)
;;;   Nothing magic happens; the C library filled those registers before
;;;   calling us, exactly as we fill rdi before calling printf.
;;;
;;;   The second idea is the DOUBLE INDIRECTION of argv. `argv` is a pointer to
;;;   an array of pointers to strings, so getting at the characters of argv[j]
;;;   takes two memory loads:
;;;       rdx = [argv]            the address of the array
;;;       rdx = [rdx + 8*j]       the j-th pointer in it (8 = sizeof a pointer)
;;;   and only then does rdx point at actual characters.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0002.asm" hello world "two words"
;;;
;;;   Run it with no arguments too, and watch the loop body never execute:
;;;   ./asm "lectures code /code-0002.asm"
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0002.asm" alpha beta
;;;
;;;   Useful session:
;;;     info registers rdi rsi   at the very first instruction: argc and argv
;;;     x/3gx $rsi               the first 3 pointers of the argv array
;;;     x/s *(char**)$rsi        the string argv[0] points at
;;;     x/s *((char**)$rsi+1)    argv[1]
;;;     break code-0002.asm:NN   put NN on the `cmp rsi, qword [argc]` line
;;;     c                        then `p $rsi` each time to watch the index climb
;;;     p (long)argc             gdb can read your .bss labels by name
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   This file contains a small, very common bug-source, and the stack is how
;;;   you see it. rsi is a CALLER-SAVED (volatile) register: printf is entitled
;;;   to destroy it. But rsi is also this loop's counter. That is why the loop
;;;   body reads
;;;       push rsi
;;;       call printf
;;;       pop rsi
;;;   Try it yourself in gdb: break on the `call printf` inside the loop,
;;;   `p $rsi`, then `finish`, then `p $rsi` again -- it will have changed.
;;;   The push/pop pair is the fix.
;;;
;;;   Watch what that does to alignment, too. At the `call` the stack was
;;;   16-byte aligned; `push rsi` makes it 8 mod 16, and then `call printf`
;;;   pushes another 8 and brings it back to a multiple of 16. Do
;;;       p $rsp % 16
;;;   before and after the push to see it. Getting this wrong is the classic
;;;   "my printf segfaults for no reason" bug.
;;;
;;;   Finally, `bt` while stopped inside printf shows only ONE frame of yours
;;;   no matter how many times the loop has gone round: a loop does not grow the
;;;   stack. Compare this with code-0004, where recursion does.
;;; ============================================================================

section .data			; initialised, writable data
fmt_argc:
	db `There were %d argument(s) passed, `
	db `including the executable path:\n\0`
				; TWO `db` directives, no terminator on the first:
				;   the bytes are simply emitted one after another,
				;   so this is a single C string split across two
				;   source lines for readability. Only the last one
				;   carries the \0.
				;   %d prints a 32-bit int (argc really is an int).
fmt_executable:
	db `Executable: %s\n\0`	; %s takes a POINTER to a NUL-terminated string
				;   and prints the characters it finds there.
fmt_command_line_arg:
	db `argv[%d] = \"%s\"\n\0` ; \" is an escaped double-quote, so the output
				;   is surrounded by real quote marks -- handy for
				;   seeing arguments that contain spaces.

section .bss			; zero-filled at load time, costs no file space
argc:
	resq 1			; one quadword to stash the incoming argc
argv:
	resq 1			; one quadword to stash the incoming argv pointer

extern printf			; defined in the C library, resolved by the linker
global main			; export main for the C library start-up code

section .text
;;; ----------------------------------------------------------------------------
;;; main -- print the program's command-line arguments.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0
;;;   How it works: immediately copies its two parameters into .bss globals so
;;;                 that later `call printf`s cannot clobber them, prints argc
;;;                 and argv[0], then walks j = 1 .. argc-1 printing argv[j].
;;;                 The loop counter lives in rsi and is push/pop-protected
;;;                 around each call.
;;; ----------------------------------------------------------------------------
main:
	push rbp		; prologue 1/2: save the caller's frame pointer.
				;   `push` = rsp -= 8, then store at [rsp].
	mov rbp, rsp		; prologue 2/2: rbp becomes the immovable anchor of
				;   this frame.
	and rsp, -16		; round rsp DOWN to a multiple of 16 by clearing
				;   its low 4 bits (-16 == 0xFFFF...F0). Required
				;   stack alignment before any `call`.

	mov qword [argc], rdi	; save argc into memory. Registers are scratch --
				;   printf may overwrite rdi -- but .bss memory is
				;   ours and survives every call.
	mov qword [argv], rsi	; save argv likewise. `qword` = an 8-byte store.

	mov rdi, fmt_argc	; printf argument 1: the format string's address
	mov rsi, qword [argc]	; printf argument 2: the value of argc, reloaded
				;   from memory. Note %d will print only its low
				;   32 bits, which is correct for an int.
	mov rax, 0		; variadic convention: 0 vector registers in use
	call printf		; push return address, jump to printf

	mov rdi, fmt_executable	; argument 1: format string "Executable: %s\n"
	mov rsi, qword [argv]	; argument 2, step 1: rsi = the address of the
				;   argv ARRAY
	mov rsi, qword [rsi]	; step 2: dereference it. [rsi] is the first
				;   element of the array, i.e. argv[0] -- a pointer
				;   to the executable's name. Now rsi points at
				;   characters, which is what %s wants.
	mov rax, 0		; no floating-point arguments
	call printf

	mov rsi, 1		; the loop counter j, starting at 1: argv[0] has
				;   already been printed, so the interesting
				;   arguments are argv[1] .. argv[argc-1].
.L:				; top of the loop. '.'-prefixed => local to `main`.
	cmp rsi, qword [argc]	; compare j against argc. `cmp` subtracts and keeps
				;   only the flags.
	je .done		; `je` = jump if equal (i.e. if the subtraction gave
				;   zero). j reached argc, so the loop is finished.
	mov rdi, fmt_command_line_arg ; argument 1: `argv[%d] = "%s"\n`
	mov rdx, qword [argv]	; argument 3, step 1: address of the argv array
	mov rdx, [rdx + 8*rsi]	; step 2: EFFECTIVE ADDRESS arithmetic. The CPU
				;   computes base + 8*index for free inside the
				;   addressing mode; 8 because each element is a
				;   64-bit pointer. So rdx = argv[j], a char*.
				;   (rsi is already argument 2, the index j -- it
				;   was set before the loop and restored each pass.)
	mov rax, 0		; no floating-point arguments
	push rsi		; PROTECT the loop counter: rsi is caller-saved, so
				;   printf may legally destroy it. Pushing also
				;   flips the stack from 16-aligned to 8 mod 16 --
				;   and the `call` below pushes 8 more, restoring
				;   alignment at printf's first instruction.
	call printf
	pop rsi			; recover the loop counter (and re-align rsp)
	inc rsi			; `inc` adds 1. Cheaper than `add rsi, 1` and, note,
				;   it does NOT touch the carry flag.
	jmp .L			; `jmp` is an unconditional jump: go round again

.done:
	mov rax, 0		; main's return value: 0 = success
	mov rsp, rbp		; epilogue 1/2: undo all our stack changes at once
	pop rbp			; epilogue 2/2: restore the caller's frame pointer
	ret			; pop the return address into rip

section .note.GNU-stack noalloc noexec ; required Linux marker: no executable stack
