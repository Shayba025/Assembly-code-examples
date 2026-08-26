;;; code-0015.asm
;;; The Collatz Chain computed iteratively, argument on the command-line
;;;
;;; The Collatz Chain:
;;; ------------------
;;; Start with a number n > 0:
;;; If n = 1, print and terminate
;;; If n is even, print, divide by two, and loop
;;; If n is odd, print, multiply by 3, add 1, and loop
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
fmt_usage:
	db `Usage: code-0015 n, where 1 <= n\n\0`
fmt_first:
	db `[%lld]\0`
fmt_next:
	db ` → [%lld]\0`
fmt_end:
	db `\n\0`

extern printf, fprintf, atoll, exit, stderr
global main
section .text
main:
	push rbp		; back up the frame-pointer
	mov rbp, rsp		; set fp to the base of current frame
	sub rsp, 8*1		; temporary storage
	and rsp, -16		; align the rsp on the 16 byte boundary

;;; The Activation Frame:
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | temp     | qword [rbp - 8*1] |
	
	cmp rdi, 2		; argc == 2
	jne .usage		; print usage if not

	mov rdi, qword [rsi + 8*1] ; get argv[1]
	call atoll		; convert to a 64-bit integer

	cmp rax, 1		; invalid input: n < 1?
	jl .usage		; print usage

	mov rdi, fmt_first	; format string for first term in the sequence
	mov rsi, rax		; n
	mov qword [rbp - 8*1], rax ; backup
	mov rax, 0		; no fp registers in use
	call printf
	mov rax, qword [rbp - 8*1] ; restore n

.loop:
	cmp rax, 1		; base case: n == 1
	je .one
	test rax, 1		; is even?
	jz .even
	lea rax, [rax + 2*rax + 1] ; n <-- 3*n + 1
	jmp .continue

.even:
	shr rax, 1		; n <-- n/2

.continue:
	mov qword [rbp - 8*1], rax ; backup n
	mov rdi, fmt_next	; format string for middle term in the sequence
	mov rsi, rax		; n
	mov rax, 0		; no fp registers in use
	call printf
	mov rax, qword [rbp - 8*1] ; restore n from backup
	jmp .loop		; remain in loop

.one:
	mov rdi, fmt_end	; done: print a newline
	mov rax, 0
	call printf

.done:
	mov rax, 0		; status OK for OS

	mov rsp, rbp		; restore original stack-pointer
	pop rbp			; set fp to point to previous frame
	ret

.usage:
	mov rdi, qword [stderr]	; errors go to stderr
	mov rsi, fmt_usage	; explain correct usage
	mov rax, 0		; no fp registers in use
	call fprintf		; send output to stderr...

	mov rax, -1		; status NOT OK
	call exit		; exit as per error

section .note.GNU-stack noalloc noexec
