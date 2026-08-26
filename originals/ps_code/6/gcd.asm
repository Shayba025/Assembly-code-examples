;;; gcd.asm
;;; Read two integers from stdin and print gcd(a,b)
;;; Programmer: Oren

section .data
fmt_prompt_for_input: db 'Enter two integers a, b: ', 0
fmt_input:            db '%ld %ld', 0
fmt_output:           db 'The gcd(a,b) is %ld', 10, 0

section .bss
a:  resq 1
b:  resq 1

extern printf, scanf
global main

section .text
; ---------------------------------------------------------
; ------------------ EUCLID GCD FUNCTION ----------------------
; ---------------------------------------------------------
gcd:
	.gcd_loop:
		cmp rsi, 0                ; while (b != 0)
		je .gcd_done

		mov rax, rdi              ; rax = a
		xor rdx, rdx              ; clear high part for division
		div rsi                   ; rax = a / b, rdx = a % b

		mov rdi, rsi              ; a = b
		mov rsi, rdx              ; b = a % b
		jmp .gcd_loop

	.gcd_done:
		mov rax, rdi              ; gcd result in rax
		ret
main:
    enter 0,0                 ; create stack frame

    ; ----------------------------------------------------
    ; Print prompt
    ; ----------------------------------------------------
    mov rdi, fmt_prompt_for_input
    xor rax, rax
    call printf

    ; ----------------------------------------------------
    ; Read a and b
    ; ----------------------------------------------------
    mov rdi, fmt_input
    mov rsi, a
    mov rdx, b
    xor rax, rax
    call scanf

    ; ----------------------------------------------------
    ; Load a and b into registers and call gcd
    ; ----------------------------------------------------
    mov rdi, [a]              ; rdi = a
    mov rsi, [b]              ; rsi = b
	call gcd
	
	; ----------------------------------------------------
	; Print result
	; ----------------------------------------------------
	mov rdi, fmt_output
	mov rsi, rax
	xor rax, rax
	call printf
		

    leave
    ret
