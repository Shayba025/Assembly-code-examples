;;; code-0002.asm
;;; Reading the command-line arguments to a program
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
fmt_argc:
	db `There were %d argument(s) passed, `
	db `including the executable path:\n\0`
fmt_executable:
	db `Executable: %s\n\0`
fmt_command_line_arg:
	db `argv[%d] = \"%s\"\n\0`

section .bss
argc:
	resq 1
argv:
	resq 1

extern printf
global main
section .text
main:
	push rbp		; save the old frame-pointer
	mov rbp, rsp		; set RBP to the base of the new frame
	and rsp, -16		; align the stack downward at the 16-byte level

	mov qword [argc], rdi	; first argument: argc
	mov qword [argv], rsi	; second argument: argv

	mov rdi, fmt_argc	; format-string for printf
	mov rsi, qword [argc]	; the argument count
	mov rax, 0		; 0 floating-point registers in use
	call printf

	mov rdi, fmt_executable	; format-string for the executable
	mov rsi, qword [argv]	; the address of the argv array
	mov rsi, qword [rsi]	; the address of argv[0]
	mov rax, 0		; 0 floating-point registers in use
	call printf

	mov rsi, 1		; we print argv[1] ... argv[argc - 1] in a loop
.L:
	cmp rsi, qword [argc]	; are we done?
	je .done		; commense exit from program
	mov rdi, fmt_command_line_arg ; the format string to print argv[j]
	mov rdx, qword [argv]	; the address of the argv array
	mov rdx, [rdx + 8*rsi]	; the address of argv[8 * rsi]
	mov rax, 0		; 0 floating-point registers in use
	push rsi		; back-up the index
	call printf
	pop rsi			; restore the index
	inc rsi			; increment the index
	jmp .L			; continue...

.done:
	mov rax, 0		; return value from main: Everything is OK
	mov rsp, rbp		; restore the old stack-pointer
	pop rbp			; restore the old frame-pointer
	ret

section .note.GNU-stack noalloc noexec
