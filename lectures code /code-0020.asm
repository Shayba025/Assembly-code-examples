;;; code-0020.asm
;;; Finding the first COUNT prime numbers
;;;
;;; Programmer: Mayer Goldberg, 2026

	COUNT equ 1000

section .data
fmt_prime_n:
	db 0xcf, 0x80, `(%lld) = %lld\n\0`
last_prime_index:
	dq 1
primes_table:
	dq 2, 3
	times (COUNT - 2) dq 0
primes_square_table:
	dq 4, 9
	times (COUNT - 2) dq 0

extern printf
global main
section .text
main:
	push rbp		; save old frame-pointer
	mov rbp, rsp		; set frame-pointer to base of new frame

	call fill_primes_table
	call print_primes_table

	mov rsp, rbp		; restore the stack pointer
	pop rbp			; set frame-pointer to base of previous frame
	ret

fill_primes_table:
	push rbp		; save old frame-pointer
	mov rbp, rsp		; set frame-pointer to base of new frame
	sub rsp, 8*2		; reserve two local variables

;;; |        | old ret   | qword [rbp + 8*2] |
;;; | rbp -> | old rbp   | qword [rbp]       |
;;; |        | candidate | qword [rbp - 8*1] |
;;; |        | index     | qword [rbp - 8*2] |

	mov rax, qword [primes_table + 8*1] ; pi(1) == 3
	mov qword [rbp - 8*1], rax	    ; last candidate <-- pi(1) == 3

.L1:
	mov rax, qword [last_prime_index] ; just found a prime
	cmp rax, COUNT			  ; do we need more??
	jge .done			  ; if not, we're happy!

.next:
	mov rax, qword [rbp - 8*1] ; last candidate is ODD
	add rax, 2		   ; next candidate: last candidate + 2
	mov qword [rbp - 8*1], rax ; set candidate
	mov qword [rbp - 8*2], 1   ; start dividing from pi(1) == 3

.L2:
	mov rbx, qword [rbp - 8*2] ; index
	mov rcx, qword [primes_square_table + 8*rbx] ; look at the square
	mov rax, qword [rbp - 8*1] ; candidate
	cmp rcx, rax		   ; square > candidate?
	jg .new_prime		   ; we found a new prime number!
	mov rcx, qword [primes_table + 8*rbx] ; pi(i)
	cqo				      ; prepare for division/remainder
	div rcx				      ; candidate / pi(i)
	cmp rdx, 0			      ; remainder == 0??
	jz .next			      ; try next candidate
	inc qword [rbp - 8*2]		      ; ++i
	jmp .L2				      ; continue to test for primality

.new_prime:
	mov rcx, qword [last_prime_index] 
	inc rcx			; ++last_prime_index
	mov rax, qword [rbp - 8*1]	      ; candidate
	mov qword [primes_table + 8*rcx], rax ; next_prime <-- candidate
	cqo				      ; prepare to square
	mul rax				      ; candidate^2
	mov qword [primes_square_table + 8*rcx], rax ; set in prime^2 table
	mov qword [last_prime_index], rcx	     ; set in prime table
	jmp .L1				      ; search for next prime

.done:
	mov rsp, rbp		; restore the original stack-pointer
	pop rbp			; set frame-pointer to point to previous frame
	ret

print_primes_table:
	push rbp		; save the old frame-pointer
	mov rbp, rsp		; set frame-pointer to base of the new frame
	sub rsp, 8*1		; reserve storage for one local variable
	and rsp, -16		; align the stack for printing

;;; The activation frame:
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | i        | qword [rbp - 8*1] |

	mov qword [rbp - 8*1], 0 ; i <-- 0
.L:
	mov rax, qword [rbp - 8*1] ; i
	cmp rax, qword [last_prime_index] ; i > last_prime_index ?
	jg .done			  ; if so, done!

	mov rdi, fmt_prime_n	; load the format for printing the i-th prime
	mov rsi, rax		; i
	mov rdx, qword [primes_table + 8*rax] ; pi(i)
	mov rax, 0	        ; no fp registers in use
	call printf
	inc qword [rbp - 8*1]	; ++i
	jmp .L

.done:
	mov rax, 0		; Status: OK

	mov rsp, rbp		; restore the old stack-pointer
	pop rbp			; set fp to base of previous frame
	ret

section .note.GNU-stack noalloc noexec
