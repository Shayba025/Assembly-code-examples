;;; code-0014.asm
;;; Fibonacci computed recursively, argument on the command-line, Pascal-style
;;;
;;; Programmer: Mayer Goldberg, 2026

	LIMIT equ 92

section .data
fmt_output:
	db `Answer: %lld\n\0`
fmt_usage:
	db `Usage: code-0013 n, where 0 <= n <= 92\n\0`

extern printf, fprintf, atoll, exit, stderr
global main
section .text
main:
	push rbp		; back up the frame-pointer
	mov rbp, rsp		; set fp to the base of current frame
	and rsp, -16		; align stack by 16 bytes (for printf/scanf)
	
	cmp rdi, 2		; argc == 2
	jne .usage		; print usage if not

	mov rdi, qword [rsi + 8*1] ; get argv[1]
	call atoll		; convert to a 64-bit integer
	cmp rax, 0		; test if negative
	jl .usage		; print usage if negative
	cmp rax, LIMIT		; fib(LIMIT + 1) > 2^64
	jg .usage		; print usage if input is too large

	push rax		; push n
	call fib		; call fib, Pascal-style

	mov rdi, fmt_output	; format string for output
	mov rsi, rax		; fib(n)
	mov rax, 0		; no fp registers in use
	call printf

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

fib:
	push rbp		; back up the frame-pointer
	mov rbp, rsp		; set fp to the base of the current frame

;;; The structure of the activation frame:	
;;; |         | n        | qword [rbp + 8*2] |
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |

	mov rax, qword [rbp + 8*2] ; rax <-- n
	cmp rax, 2		; n < 2?
	jl .base		; return n

	dec rax			; compute n-1
	push rax		; push n-1
	call fib		; compute fib(n-1), Pascal-style
	push rax		; save fib(n-1)
	mov rax, qword [rbp + 8*2] ; rax <-- n
	sub rax, 2		; compute n-2
	push rax		; push n-2
	call fib		; compute fib(n-2) --> rax, Pascal-style
	pop rbx			; rbx <-- fib(n-1)
	add rax, rbx		; fib(n-1) + fib(n)
	jmp .done
.base:
	mov rax, qword [rbp + 8*2] ; return n
.done:	
	mov rsp, rbp		; restore original stack-pointer
	pop rbp			; set fp to point to previous frame
	ret 8*1

section .note.GNU-stack noalloc noexec
