;;; code-0005.asm
;;; A new control-paradigm inspired by BALR and CPS: between
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
fmt_long:
	db `%llu\0`
fmt_bom:
	db `a billion or more\n\0`
fmt_hom:
	db `in the hundreds of millions\n\0`
fmt_tom:
	db `in the tens of millions\n\0`
fmt_m:
	db `in the millions\n\0`
fmt_hot:
	db `in the hundreds of thousands\n\0`
fmt_tot:
	db `in the tens of thousands\n\0`
fmt_t:
	db `in the thousands\n\0`
fmt_h:
	db `in the hundreds\n\0`
fmt_tens:
	db `in the tens\n\0`
fmt_u:
	db `a single digit (unit)\n\0`
fmt_n:
	db `a negative number\n\0`
fmt_usage:
	db `Usage: code-0005 <integer>\n\0`

extern atoll, printf, fprintf, stderr, exit
global main
section .text
main:
	push rbp		; save the old frame-pointer
	mov rbp, rsp		; establish new frame-pointer
	and rsp, -16		; align the stack downward at the 16-byte level
	
	cmp rdi, 2		; |argc| == 2?
	jne .error_usage	; If not, print usage...
	mov rdi, qword [rsi + 8*1] ; rdi <-- arg[1]
	call atoll		; convert to a 64 bit integer --> rax

	mov rdi, rax		; load the number from the command-line
	mov rsi, 1000000000	; compare to upper limit
	cmp rdi, rsi
	jge .billions_or_more

	mov rsi, 100000000	; lower limit
	mov rdx, 999999999	; upper limit
	mov rcx, .hundreds_of_millions
	mov r8, .continue8
	jmp between
.continue8:
	mov rsi, 10000000	; lower limit
	mov rdx, 99999999	; upper limit
	mov rcx, .tens_of_millions
	mov r8, .continue7
	jmp between
.continue7:
	mov rsi, 1000000	; lower limit
	mov rdx, 9999999	; upper limit
	mov rcx, .millions
	mov r8, .continue6
	jmp between
.continue6:
	mov rsi, 100000		; lower limit
	mov rdx, 999999		; upper limit
	mov rcx, .hundreds_of_thousands
	mov r8, .continue5
	jmp between
.continue5:
	mov rsi, 10000		; lower limit
	mov rdx, 99999		; upper limit
	mov rcx, .tens_of_thousands
	mov r8, .continue4
	jmp between
.continue4:
	mov rsi, 1000		; lower limit
	mov rdx, 9999		; upper limit
	mov rcx, .thousands
	mov r8, .continue3
	jmp between
.continue3:
	mov rsi, 100		; lower limit
	mov rdx, 999		; upper limit
	mov rcx, .hundreds
	mov r8, .continue2
	jmp between
.continue2:
	mov rsi, 10		; lower limit
	mov rdx, 99		; upper limit
	mov rcx, .tens
	mov r8, .continue1
	jmp between
.continue1:
	mov rsi, 0		; lower limit
	mov rdx, 9		; upper limit
	mov rcx, .units
	mov r8, .negative
	jmp between
.billions_or_more:
	mov rdi, fmt_bom	; print string
	jmp .print
.hundreds_of_millions:
	mov rdi, fmt_hom	; print string
	jmp .print
.tens_of_millions:
	mov rdi, fmt_tom	; print string
	jmp .print
.millions:
	mov rdi, fmt_m		; print string
	jmp .print
.hundreds_of_thousands:
	mov rdi, fmt_hot	; print string
	jmp .print
.tens_of_thousands:
	mov rdi, fmt_tot	; print string
	jmp .print
.thousands:
	mov rdi, fmt_t		; print string
	jmp .print
.hundreds:
	mov rdi, fmt_h		; print string
	jmp .print
.tens:
	mov rdi, fmt_tens	; print string
	jmp .print
.units:
	mov rdi, fmt_u		; print string
	jmp .print
.negative:
	mov rdi, fmt_n		; print string
.print:
	mov rax, 0		; 0 floating-point registers in use
	call printf

	mov rax, 0		; return value to shell: OK

	mov rsp, rbp		; restore the stack-pointer
	pop rbp			; restore the old frame-pointer
	ret

.error_usage:
	mov rdi, qword [stderr]	; FILE *stderr
	mov rsi, fmt_usage	; format string
	mov rax, 0		; 0 floating-point registers in use
	call fprintf
	mov rax, -1		; return value to shell: error code
	call exit

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
