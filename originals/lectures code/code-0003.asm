;;; code-0003.asm
;;; Add the numbers on the command line, and print the sum
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
fmt_sum:
	db `The sum of %ld number(s) is %ld\n\0`
i:
	dq 1
sum:
	dq 0

section .bss
argc:
	resq 1
argv:
	resq 1

extern atoll, printf
global main
section .text
main:
	push rbp		; backup the old frame-pointer
	mov rbp, rsp		; set RBP to the base of the current frame
	and rsp, -16		; align the stack downward at the 16-byte level
	
	; recall: int main(int argc, char *argv[]) { ... }
	mov qword [argc], rdi	; backup RDI == argc
	mov qword [argv], rsi	; backup RSI == argv
.L:				; the start of the loop
	mov rax, qword [i]	; loading the index
	cmp rax, qword [argc]	; comparing to argc
	je .done		; if equal, we are done!

	mov rdi, qword [argv]	; load the argument vector
	mov rdi, qword [rdi + 8*rax] ; the address of the argv[i] string
	call atoll		     ; recall: long long atoll(char *);
	add qword [sum], rax	; add the integer value of argv[i] to sum
	inc qword [i]		; increment i
	jmp .L			; jump to the start of the loop

.done:
	mov rdi, fmt_sum	; the format-string for printing the sum
	mov rsi, qword [argc]	; number of arguments, incl the executable name
	dec rsi			; ...but we don't count the executable name!
	mov rdx, qword [sum]	; the sum of the values of the arguments
	mov rax, 0		; 0 floating-point registers
	call printf

	mov rax, 0		; return 0 to the shell: OK
	
	mov rsp, rbp		; restore the old stack-pointer
	pop rbp			; restore the old frame-pointer
	ret

section .note.GNU-stack noalloc noexec
