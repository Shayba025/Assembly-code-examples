;;; code-0006.asm
;;; Demonstrating that the format string can be on the stack too!
;;;
;;; Programmer: Mayer Goldberg, 2026

extern printf
global main
section .text
main:
	push rbp		; save the old frame-pointer
	mov rbp, rsp		; point to the base of the new frame
	and rsp, -16		; align the stack downwards, on 16 bytes
	
	mov rdi, `%lld\n\0`	; A [format] string is just a number!
	push rdi		; ...even on the stack
	mov rdi, rsp		; So the rsp is its address!
	mov rsi, 496351		; This is what we wish to print
	mov rax, 0		; 0 floating-point registers in use
	call printf

	mov rsp, rbp		; reset the stack-pointer
	pop rbp			; point to the base of the PREVIOUS frame
	ret

section .note.GNU-stack noalloc noexec
