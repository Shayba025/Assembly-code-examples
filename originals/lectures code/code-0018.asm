;;; code-0018.asm
;;; Printing a multiplication table
;;;
;;; Programmer: Mayer Goldberg, 2026

	M equ 10

section .data
fmt_product:
	db `%4lld\0`
fmt_newline:
	db `\n\0`

extern printf
global main
section .text
main:
	push rbp		; saving the old fp
	mov rbp, rsp		; setting the fp to the base of the new frame
	sub rsp, 8*3		; reserving 3 local variables
	and rsp, -16		; aligning the stack on 16 bytes for printf

;;; The Activation Frame:
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | i        | qword [rbp - 8*1] |
;;; |         | j        | qword [rbp - 8*2] |
;;; |         | p        | qword [rbp - 8*3] |

	mov qword [rbp - 8*1], 1 ; initializing the outer loop: i = 1

.loop_1:			; printing rows
	cmp qword [rbp - 8*1], M ; when i > M we are done
	jg .done

	mov qword [rbp - 8*2], 1 ; initialize the inner loop: j = 1
	mov qword [rbp - 8*3], 0 ; p (product) = 0

.loop_2:
	cmp qword [rbp - 8*2], M ; when j > M we are done with inner loop
	jg .exit_loop_2
	mov rax, qword [rbp - 8*1] 
	add qword [rbp - 8*3], rax ; p += i to get the next product

	mov rdi, fmt_product	; format string for printing the product
	mov rsi, qword [rbp - 8*3] ; p
	mov rax, 0		   ; no fp registers in use
	call printf
	inc qword [rbp - 8*2]	; ++j
	jmp .loop_2

.exit_loop_2:			; we print a newline, and update
	mov rdi, fmt_newline	; '\n'
	mov rax, 0		; no fp registers in use
	call printf
	inc qword [rbp - 8*1]	; ++i
	jmp .loop_1

.done:
	mov rax, 0		; status: OK
	mov rsp, rbp		; restore the stack pointer
	pop rbp			; restore the frame pointer
	ret

section .note.GNU-stack noalloc noexec
