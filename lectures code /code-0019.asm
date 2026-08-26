;;; code-0019.asm
;;; Our implementation of read_hex to read a hex number from fd(in) == 0
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
fmt_prompt:
	db `Enter a number in hex: \0`
fmt_output:
	db `The value is %lld\n\0`

extern printf, fflush, stdout
global main
section .text
main:
	push rbp		; backup the old fp
	mov rbp, rsp		; set the fp to the base of the top frame
	and rsp, -16		; align the stack by 16 bytes for printing

	mov rdi, fmt_prompt	; prompt for input
	mov rax, 0		; no fp registers in use
	call printf

	mov rdi, qword [stdout]	; the printf didn't end with \n so nothing is
	call fflush		; ...printed before we flush the buffer!
	                        ; same as fflush(stdout) in C

	call read_hex		; read in a number in hex

	mov rdi, fmt_output	; format string for output
	mov rsi, rax		; the value of the hex string
	mov rax, 0		; no fp registers in use
	call printf

	mov rsp, rbp		; reset the stack pointer
	pop rbp			; restore fp to the base of the previous frame
	ret

read_hex:
	mov rbx, 0		; accumulator = 0
.inner:
	call getchar		; rax <-- char from fd(in) = 0

	mov rdi, rax		; char read
	mov rsi, '0'		; '0' <= ch
	mov rdx, '9'		; && ch <= '9'
	mov rcx, .digit_0_to_9	; handle 0..9
	mov r8, .cont1		; or else...
	jmp between
.cont1:
	mov rsi, 'a'		; 'a' <= ch
	mov rdx, 'f'		; && ch <= 'f'
	mov rcx, .digit_a_to_f	; handle a..f
	mov r8, .cont2		; or else...
	jmp between
.cont2:
	mov rsi, 'A'		; 'A' <= ch
	mov rdx, 'F'		; && ch <= 'F'
	mov rcx, .digit_A_to_F	; handle A..F
	mov r8, .cont3		; or else...
	jmp between
.cont3:
	push rax		; return char to unget-buffer
	call ungetchar

	mov rax, rbx		; rax <-- accumulator
	ret
.digit_0_to_9:
	lea rbx, [2*rbx]
	lea rbx, [rax + 8*rbx - '0'] ; (16 * accumulator) + (ch - '0')
	jmp .inner		; loop again
.digit_a_to_f:
	lea rbx, [2*rbx]
	lea rbx, [rax + 8*rbx - ('a' - 10)] ; 16 * accumulator + (ch - 'a' + 10)
	jmp .inner		; loop again
.digit_A_to_F:
	lea rbx, [2*rbx]
	lea rbx, [rax + 8*rbx - ('A' - 10)] ; 16 * accumulator + (ch - 'A' + 10)
	jmp .inner		; loop again

section .data
;;; is_fresh == 1 means we read the next call to getchar
;;; reads the char from the unget_buffer, and not from fd(in) == 0
is_fresh:
	dq 0			

section .bss
unget_buffer:
	resb 1

section .text
getchar:
	cmp qword [is_fresh], 0	; is_fresh == 0 --> read char from fd(in)
	jz .must_read
	mov qword [is_fresh], 0	; set is_fresh to 0
	jmp .done
.must_read:
	mov rax, 0		; sys_read
	mov rdi, 0		; in = 0
	mov rsi, unget_buffer	; place char directly into the unget_buffer
	mov rdx, 1		; only read 1 char
	syscall
.done:
	movzx rax, byte [unget_buffer] ; movzx extends the byte into a quadword
	ret

ungetchar:
	mov rax, [rsp + 8*1]	; grab the argument
	mov byte [unget_buffer], al ; write into the unget_buffer
	mov qword [is_fresh], 1	; set is_fresh <-- 1, so that the next
	                        ; call to getchar reads from unget_buffer
	ret 8*1			; Pascal-style: callee cleans the argument

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
