;;; code-0010.asm
;;; Factorial computed recursively, argument on the command-line, C-style
;;;
;;; Programmer: Mayer Goldberg, 2026

	LIMIT equ 20

section .data
fmt_output:
	db `Answer: %lld\n\0`
fmt_usage:
	db `Usage: code-0010 n, where 0 <= n <= 20\n\0`

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
	cmp rax, LIMIT		; (LIMIT + 1)! > 2^64
	jg .usage		; print usage if input is too large

	push rax		; push n
	call fact		; call fact
	add rsp, 8*1		; C-style: Caller cleans the stack!

	mov rdi, fmt_output	; format string for output
	mov rsi, rax		; n!
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

fact:
	push rbp		; back up the frame-pointer
	mov rbp, rsp		; set fp to the base of the current frame

;;; The structure of the activation frame:	
;;; |         | n        | qword [rbp + 8*2] |
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |

	mov rax, qword [rbp + 8*2] ; rax <-- n
	cmp rax, 0		; n = 0?
	je .zero		; return 1
	dec rax			; compute n-1
	push rax		; push n-1
	call fact		; compute fact(n - 1) --> rax
	add rsp, 8*1		; C-style: caller cleans the stack!
	cqo			; extend RAX --> RDX:RAX
	mul qword [rbp + 8*2]	; RDX:RAX = n * fact(n - 1)
	jmp .done
.zero:
	mov rax, 1		; fact(0) = 1
.done:	
	mov rsp, rbp		; restore original stack-pointer
	pop rbp			; set fp to point to previous frame
	ret

section .note.GNU-stack noalloc noexec
