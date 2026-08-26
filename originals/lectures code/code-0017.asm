;;; code-0017.asm
;;; The Towers of Hanoi in assembly
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
fmt_usage:
	db `Usage: ./code-0017 n, where n >= 0\n\0`
fmt_move:
	db `Move a disk from peg %s to peg %s\n\0`
peg_a:
	db `A\0`
peg_b:
	db `B\0`
peg_c:
	db `C\0`

extern printf, fprintf, atoll, exit, stderr
global main
section .text
main:
	push rbp
	mov rbp, rsp

	cmp rdi, 2
	jne .usage
	mov rdi, qword [rsi + 8*1]
	call atoll
	cmp rax, 0
	jl .usage

	push peg_a
	push peg_b
	push peg_c
	push rax
	call hanoi

	mov rax, 0

	mov rsp, rbp
	pop rbp
	ret
.usage:
	mov rdi, qword [stderr]
	mov rsi, fmt_usage
	mov rax, 0
	call fprintf
	mov rax, -1
	call exit

hanoi:
	push rbp
	mov rbp, rsp
	and rsp, -16

;;; The Activation Frame:
;;; |         | peg a    | qword [rbp + 8*5]  |
;;; |         | peg b    | qword [rbp + 8*4]  |
;;; |         | peg c    | qword [rbp + 8*3]  |
;;; |         | n        | qword [rbp + 8*2]  |
;;; |         | ret addr | qword [rbp + 8*1]  |
;;; | rbp --> | old rbp  | qword [rbp]        |
;;; |         | ???      | possible alignment |

	cmp qword [rbp + 8*2], 0
	jz .done

	push qword [rbp + 8*5]
	push qword [rbp + 8*3]
	push qword [rbp + 8*4]
	mov rax, qword [rbp + 8*2]
	dec rax
	push rax
	call hanoi

	mov rdi, fmt_move
	mov rsi, qword [rbp + 8*5]
	mov rdx, qword [rbp + 8*4]
	mov rax, 0
	call printf

	push qword [rbp + 8*3]
	push qword [rbp + 8*4]
	push qword [rbp + 8*5]
	mov rax, qword [rbp + 8*2]
	dec rax
	push rax
	call hanoi
.done:
	mov rsp, rbp
	pop rbp
	ret 8*4	

section .note.GNU-stack noalloc noexec
