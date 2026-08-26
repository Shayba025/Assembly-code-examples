;;; code-0016.asm
;;; Convert the command-line argument from hex (string) to its decimal value
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
fmt_output:
	db `Answer: %lld\n\0`
fmt_usage:
	db `Usage: code-0016 hex, where hex = {0..9|a..f|A..F}+\n\0`

extern printf, fprintf, exit, stderr
global main
section .text
main:
	push rbp		; back up the frame-pointer
	mov rbp, rsp		; set fp to the base of current frame
	and rsp, -16		; align stack by 16 (for printf/scanf)
	
	cmp rdi, 2		; argc == 2
	jne .usage		; print usage if not

	mov rbx, qword [rsi + 8*1] ; argv[1]
	mov rax, 0
.L:
	cmp byte [rbx], `\0`
	je .finished
	
	movzx rdi, byte [rbx]	; extend byte to 64-bit quad-word
	mov rsi, '0'
	mov rdx, '9'
	mov rcx, .digit_0_to_9
	mov r8, .cont1
	jmp between
.cont1:
	mov rsi, 'a'
	mov rdx, 'f'
	mov rcx, .digit_a_to_f
	mov r8, .cont2
	jmp between
.cont2:
	mov rsi, 'A'
	mov rdx, 'F'
	mov rcx, .digit_A_to_F
	mov r8, .usage
	jmp between

.digit_0_to_9:
	lea rax, [2*rax]
	lea rax, [rdi + 8*rax - '0']
	jmp .skip_and_continue

.digit_a_to_f:
	lea rax, [2*rax]
	lea rax, [rdi + 8*rax - ('a' - 10)]
	jmp .skip_and_continue

.digit_A_to_F:
	lea rax, [2*rax]
	lea rax, [rdi + 8*rax - ('A' - 10)]
	
.skip_and_continue:
	inc rbx
	jmp .L

.finished:
	mov rdi, fmt_output	; format string for output
	mov rsi, rax		; integer value 
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

;;; Using between:
;;; | rdi | n               |
;;; | rsi | lower bound     |
;;; | rdx | upper bound     |
;;; | rcx | addr if inside  |
;;; | r8  | addr if outside |
between:
	cmp rdi, rsi
	jl .L
	cmp rdi, rdx
	jg .L
	jmp rcx
.L:
	jmp r8

section .note.GNU-stack noalloc noexec
