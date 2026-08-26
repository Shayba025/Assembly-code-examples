;;; code-0023.asm
;;; Solving the quadratic equation using x87
;;;
;;; Programmer: Mayer Goldberg, 2026

%macro fldlit 1
	jmp %%Lcont
%%Lflit:
	dt %1
%%Lcont:
	fld tword [%%Lflit]
%endmacro

section .data
fmt_long_double:
	db `%Lg\0`
fmt_usage:
	db `Usage: ./code-0023 <long double> <long double> <long double>\n\0`
fmt_no_real_solution:
	db `There are no solutions in ℝ! `
	db `Tell your instructor not to be so lazy, `
	db `and to add support for ℂ!\n\0`
fmt_one_solution:
	db `There is one solution: x = %.18Lg\n\0`
fmt_two_solutions:
	db `There are two solutions: x₁ = %.18Lg, x₂ = %.18Lg\n\0`
epsilon:
	dt 1.0e-17

section .bss
a:
	rest 1
b:
	rest 1
c:
	rest 1
desc:
	rest 1
t1:
	rest 1
t2:
	rest 1
x1:
	rest 1
x2:
	rest 1

extern printf, fprintf, stderr, sscanf, exit
global main
section .text
main:
	push rbp		; back up the pointer to the previous frame
	mov rbp, rsp		; set fp to the base of the new frame
	sub rsp, 8*1		; we need to keep local variable for argv
	and rsp, -16		; align the stack for printing

;;; The activation frame
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | argv     | qword [rbp - 8*1] |

	cmp rdi, 4		; program + a + b + c --> 4 arguments
	jne .usage

	mov qword [rbp - 8*1], rsi ; argv
	mov rdi, qword [rsi + 8*1] ; argv[1] == a
	mov rsi, fmt_long_double   ; format for one (long double)
	mov rdx, a		   ; &a
	mov rax, 0		   ; no fp registers used
	call sscanf		   ; try to read one (long double)
	cmp rax, 1		   ; if failed, 
	jne .usage		   ; ...complain!

	mov rbx, qword [rbp - 8*1] ; argv
	mov rdi, qword [rbx + 8*2] ; argv[1] == b
	mov rsi, fmt_long_double   ; format for one (long double)
	mov rdx, b		   ; &b
	mov rax, 0		   ; no fp registers used
	call sscanf		   ; try to read one (long double)
	cmp rax, 1		   ; if failed, 
	jne .usage		   ; ...complain!

	mov rbx, qword [rbp - 8*1] ; argv
	mov rdi, qword [rbx + 8*3] ; argv[2] == c
	mov rsi, fmt_long_double   ; format for one (long double)
	mov rdx, c		   ; &c
	mov rax, 0		   ; no fp registers used
	call sscanf		   ; try to read one (long double)
	cmp rax, 1		   ; if failed,
	jne .usage		   ; ...complain!

	fninit			; reset the x87 subsystem
	fld tword [b]		; b
	fld st0			; b b
	fmulp			; b^2
	fldlit 4.0		; 4
	fld tword [a]		; a
	fmulp			; 4a
	fld tword [c]		; c
	fmulp			; 4ac
	fsubp			; b^2 - 4ac
	fld st0			; (b^2 - 4ac)   (b^2 - 4ac)
	fstp tword [desc]	; desc <-- (b^2 - 4ac)
	fldz			; 0
	fucomip st1		; 0 ? b^2 - 4ac
	ja .no_real_roots	; 0 > b^2 - 4ac ==> .no_real_roots

	fld tword [a]		; a
	fld st0			; a   a
	faddp			; 2*a
	fstp tword [t2]		; t2 <-- 2*a

	fld tword [epsilon]	; desc    epsilon
	fucomip st1		; desc ? epsilon
	fstp st0		; desc < epsilon (desc is positive!)
	ja .one_root		; | desc | < epsilon ==> .one_root

	fld tword [desc]	; desc
	fsqrt			; sqrt(desc)
	fstp tword [t1]		; t1 <-- sqrt(desc)
	fld tword [b]		; b
	fchs			; -b
	fld st0			; -b    -b
	fld tword [t1]		; -b    -b     t1
	faddp			; -b    -b + t1
	fld tword [t2]		; -b    -b + t1    2a
	fdivp			; -b    (-b + t1)/(2a)
	fstp tword [x1]		; x1 <-- root1
	fld tword [t1]		; -b    t1 
	fsubp			; -b - t1
	fld tword [t2]		; -b - t1    2a
	fdivp			; x2 == (-b - t1)/(2a)
	fld tword [x1]		; x2    x1
	sub rsp, 16*2 		; make room on stack; aligned by 16
	mov rdi, fmt_two_solutions ; fmt for x1, x2
	fstp tword [rsp]	; [rsp] <-- x1
	fstp tword [rsp + 16*1]	; [rsp] <-- x2
	mov rax, 0		; no fp registers in use
	call printf
	jmp .done		; cleanup and quit

.no_real_roots:
	mov rdi, fmt_no_real_solution ; fmt for x
	mov rax, 0		; no fp registers in use
	call printf
	jmp .done		; cleanup and quit

.one_root:
	fld tword [b]		; b
	fchs			; -b
	fld tword [a]		; -b    a
	fld st0			; -b    a    a
	faddp			; -b    2a
	fdivp			; -b/(2a)
	sub rsp, 16*1		; make room on stack; aligned by 16
	fstp tword [rsp]	; [rsp] <-- x
	mov rdi, fmt_one_solution ; fmt for x
	mov rax, 0		; no fp registers in use
	call printf

.done:
	fninit			; reset the x87 subsystem
	mov rax, 0		; status: OK
	mov rsp, rbp		; restore the stack pointer
	pop rbp			; point fp to the previous frame
	ret

.usage:
	mov rdi, qword [stderr]	; errors go to FILE *stderr
	mov rsi, fmt_usage	; fmt for usage
	mov rax, 0		; no fp registers in use
	call fprintf
	mov rax, -1		; status: ERROR
	call exit

section .note.GNU-stack noalloc noexec
