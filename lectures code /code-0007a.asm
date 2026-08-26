;;; code-0007.asm
;;; A short program to demonstrate that data read with scanf
;;; need not be placed in a global memory location (in the data
;;; or bss sections), but can be placed on the stack.
;;;
;;; Programmer: Mayer Goldberg, 2026

extern printf, scanf
global main
section .text
main:
	push rbp		; save the old frame-pointer
	mov rbp, rsp		; point to the base of the new frame

	mov rdi, `int> \0`	; a [format] string is just a number!
	push rdi		; ...even on the stack
	mov rdi, rsp		; so the rsp is its address!
	mov rax, 0		; 0 floating-point registers in use
	and rsp, -16		; align the stack downwards, on 16 bytes
	call printf
	mov rsp, rbp		; restore the rsp

	mov rdi, `%lld\0`	; the scanf format-string as a number
	push rdi		; ...on the stack
	mov rdi, rsp		; So the rsp is its address!
	sub rsp, 8*1		; Making room for the integer
	mov rsi, rsp		; So the rsp is its address!
	and rsp, -16		; align the stack downwards, on 16 bytes
	call scanf

	mov rdi, 0x0A64
	push rdi
	mov rdi, 0x6C6C25203A646572 
	push rdi
	mov rdi, 0x65746E6520756F59 
	push rdi
	mov rdi, rsp
	mov rsi, qword [rbp - 8*2] ; this is the number we read with scanf
	mov rax, 0		; 0 floating-point registers in use
	and rsp, -16		; align the stack downwards, on 16 bytes
	call printf

	mov rsp, rbp		; restore the rsp
	pop rbp			; point to the base of the previous frame
	ret

section .note.GNU-stack noalloc noexec
