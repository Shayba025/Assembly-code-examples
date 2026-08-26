;;; code-0001.asm
;;; Reading two numbers from stdin, printing the maximum
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
fmt_prompt_for_input:
	db `Enter two integers, a, b: \0`
fmt_input:
	db `%ld, %ld\0`
fmt_output:
	db `The max value is %ld\n\0`

section .bss
a:
	resq 1
b:
	resq 1

extern printf, scanf
global main
section .text
main:
	push rbp		; saving the old frame-pointer
	mov rbp, rsp		; establishing the new frame
	and rsp, -16		; align the stack downward at the 16-byte level

	; printf(fmt_prompt_for_input)
	mov rdi, fmt_prompt_for_input ; the format-string for printf
	mov rax, 0		      ; 0 floating-point registers in use
	call printf

	; scanf(fmt_input, &a, &b)
	mov rdi, fmt_input	; the format string for scanf
	mov rsi, a		; the address of a
	mov rdx, b		; the address of b
	mov rax, 0		; 0 floating-point registers in use
	call scanf

	; printf(fmt_output, (a > b) ? a : b)
	mov rdi, fmt_output	; the format string for printing the max
	mov rsi, qword [a]	; loading a into the first argument
	mov rax, qword [b]	; loading b into a temporary
	cmp rsi, rax		; comparing a ? b
	jg .continue		; if a is greater continue...
	mov rsi, rax		; else b is max, so set rsi to b
.continue:
	mov rax, 0		; 0 floating-point registers in use
	call printf

	mov rax, 0		; return value from main: Everything is OK
	
	mov rsp, rbp		; restore the stack-pointer
	pop rbp			; restore the OLD base-pointer
	ret

section .note.GNU-stack noalloc noexec
