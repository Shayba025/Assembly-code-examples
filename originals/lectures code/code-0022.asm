;;; code-0022.asm
;;; A simple file-copying file using the sys_read and sys_write system
;;; calls in linux;;;
;;; Programmer: Mayer Goldberg, 2026

	SIZE equ 1024

section .data
fmt_cp_report:
	db `Copying \"%s\" to \"%s\"...\n\0`
fmt_bytes:
	db `Copied %llu bytes\n\0`
fmt_usage:
	db `Usage: program source-file destination-file\n\0`
fmt_cannot_open_for_read:
	db `Cannot open file for reading\n\0`
fmt_cannot_open_for_write:
	db `Cannot open file for writing\n\0`
fmt_cannot_read:
	db `Cannot read from the input file\n\0`
fmt_cannot_write:
	db `Cannot write to the output file\n\0`

section .bss
buffer:
	resb SIZE

extern printf, fprintf, stderr, exit
global main
section .text
main:
	push rbp
	mov rbp, rsp
	sub rsp, 8*5
	and rsp, -16

;;; The activation frame:
;;; |         | ret addr    | qword [rbp + 8*1] |
;;; | rbp --> | old rbp     | qword [rbp]       |
;;; |         | file_in     | qword [rbp - 8*1] |
;;; |         | file_out    | qword [rbp - 8*2] |
;;; |         | fd_in       | qword [rbp - 8*3] |
;;; |         | fd_out      | qword [rbp - 8*4] |
;;; |         | total bytes | qword [rbp - 8*5] |

	cmp qword rdi, 3
	jne .usage

	mov rbx, qword [rsi + 8*1]
	mov qword [rbp - 8*1], rbx ; file_in
	mov rbx, qword [rsi + 8*2]
	mov qword [rbp - 8*2], rbx ; file_out

	mov rdi, fmt_cp_report
	mov rsi, qword [rbp - 8*1]
	mov rdx, qword [rbp - 8*2]
	mov rax, 0
	call printf

	mov rax, 2		; sys_open
	mov rdi, qword [rbp - 8*1] ; file_in
	mov rsi, 0		; O_RDONLY
	mov rdx, 0		; mode is irrelevant for read
	syscall

	cmp rax, 0
	jl .cannot_open_for_read

	mov qword [rbp - 8*3], rax ; fd_in

	mov rax, 2		; sys_open
	mov rdi, qword [rbp - 8*2] ; file_out
	mov rsi, 0x241          ; O_WRONLY | O_CREAT | O_TRUNC
	mov rdx, 0o644		; user: read/write, else: read
	syscall

	cmp rax, 0
	jl .cannot_open_for_write

	mov qword [rbp - 8*4], rax ; fd_out

	mov qword [rbp - 8*5], 0 ; total # of character

.loop:
	mov rax, 0		; sys_read
	mov rdi, qword [rbp - 8*3]
	mov rsi, buffer
	mov rdx, SIZE
	syscall

	cmp rax, 0
	jl .cannot_read
	cmp rax, SIZE
	jl .last

	mov rax, 1		; sys_write
	mov rdi, qword [rbp - 8*4]
	mov rsi, buffer
	mov rdx, SIZE
	syscall

	cmp rax, 0
	jl .cannot_write

	add qword [rbp - 8*5], SIZE
	jmp .loop

.last:
	mov rdx, rax
	mov r9, rax
	mov rax, 1		; sys_write
	mov rdi, qword [rbp - 8*4]
	mov rsi, buffer
	syscall

	cmp rax, 0
	jl .cannot_write

	add qword [rbp - 8*5], r9

	mov rax, 3		; sys_close
	mov rdi, [rbp - 8*3]	; fd_in
	syscall

	mov rax, 3		; sys_close
	mov rdi, [rbp - 8*4]	; fd_out
	syscall

	mov rdi, fmt_bytes
	mov rsi, qword [rbp - 8*5]
	mov rax, 0
	call printf

	mov rax, 0

	mov rsp, rbp
	pop rbp
	ret
.usage:
	mov rsi, fmt_usage
	jmp .print_and_exit
.cannot_open_for_read:
	mov rsi, fmt_cannot_open_for_read
	jmp .print_and_exit
.cannot_open_for_write:
	mov rsi, fmt_cannot_open_for_write
	jmp .print_and_exit
.cannot_read:
	mov rsi, fmt_cannot_read
	jmp .print_and_exit
.cannot_write:
	mov rsi, fmt_cannot_write
.print_and_exit:
	mov rdi, qword [stderr]
	mov rax, 0
	call fprintf

	mov rax, -1
	call exit
	
section .note.GNU-stack noalloc noexec
