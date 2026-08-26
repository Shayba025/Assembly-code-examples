;;; code-0004.asm
;;; Read command-line argument, print all binary patterns of that many bits
;;;
;;; Programmer: Mayer Goldberg, 2026

%define MAX_BITS 128		; one-line macro

section .data
i:				; the index into the string
	dq 0
fmt_binary_pattern:
	db `%s\n\0`
fmt_error_incorrect_usage:
	db `Usage: code-0004 <n>, where n in [0, ... , %ld]\n\0`

section .bss
n:
	resq 1			; the total number of bits
buffer:				; the one string we need
	resb MAX_BITS + 1

extern atoi, printf, fprintf, stderr, exit
global main
section .text
main:
	push rbp		; saving the old frame-pointer
	mov rbp, rsp		; setting the frame-pointer to the top frame
	and rsp, -16		; align the stack downward at the 16-byte level

	cmp rdi, 2		; |argc| == 2: exec name + argument
	jne .error_incorrect_usage ; print to stderr and exit!

	mov rdi, qword [rsi + 8*1] ; the argv[1] string
	call atoi		   ; RAX <--- atoi(argv[i])
	mov qword [n], rax	   ; the number of bits
	cmp rax, 0		   ; if negative
	jl .error_incorrect_usage  ; ...complain and exit!
	cmp rax, MAX_BITS	   ; if n > MAX_BITS (too big!)
	jge .error_incorrect_usage ; ...complain and exit!

	mov rdi, buffer		; load the buffer
	mov rax, qword [n]	; load n
	mov byte [rdi + 1*rax], 0 ; buffer[n] is the sentinel! '\0'

	call bin		; print all binary combinations

	mov rsp, rbp		; restore the old stack-pointer
	pop rbp			; restore the old frame-pointer
	ret

.error_incorrect_usage:
	mov rdi, qword [stderr]	; load the address of FILE *stderr structure
	mov rsi, fmt_error_incorrect_usage ; then the format string
	mov rdx, MAX_BITS - 1		   ; then limit
	mov rax, 0	        ; 0 floating-point registers
	call fprintf		; fprintf when using a FILE * like stderr!
	mov rax, -1		; return to shell with a non-zero value
	call exit		; ...indicating an error

bin:
	mov rax, qword [i]	; load i
	cmp rax, qword [n]	; if i == n 
	je .print_line		; ...we print the line and backtrack

	mov byte [buffer + 1*rax], '0' ; set the i-th char to be '0'
	inc qword [i]		       ; point to the next char
	call bin		       ; recurse!
	mov rax, qword [i]	       ; reload i
	mov byte [buffer + 1*rax], '1' ; set the i-th char to be '1'
	inc qword [i]		       ; point to the next char
	call bin		       ; recurse!
	dec qword [i]		       ; decrement i for backtracking!
	ret

.print_line:
	mov rdi, fmt_binary_pattern ; load the format for printing a string
	mov rsi, buffer		; load the address of the string
	mov rax, 0		; 0 floating-point registers used
	call printf
	dec qword [i]		; decrement i for backtracking!
	ret

section .note.GNU-stack noalloc noexec
