;;; code-0012.asm
;;; Fibonacci computed iteratively, argument on the command-line
;;;
;;; Programmer: Mayer Goldberg, 2026

	LIMIT equ 92

section .data
fmt_output:
	db `Answer: %lld\n\0`
fmt_usage:
	db `Usage: code-0012 n, where 0 <= n <= 92\n\0`

extern printf, fprintf, atoll, exit, stderr
global main
section .text
main:
	push rbp		; back up the frame-pointer
	mov rbp, rsp		; set fp to the base of current frame
	and rsp, -16		; align stack by 16 (for printf/scanf)
	
	cmp rdi, 2		; argc == 2
	jne .usage		; print usage if not

	mov rdi, qword [rsi + 8*1] ; get argv[1]
	call atoll		; convert to a 64-bit integer

	mov rcx, rax		; prepare to iterate!
	mov rax, 0		; initialize accumulator
	mov rbx, 1
	cmp rcx, 0		; must test, because LOOPNZ is not WHILE!
	jl .usage		; print usage if negative
	je .finished		; print 0 if done
	cmp rcx, LIMIT		; fib(LIMIT + 1) > 2^64
	jg .usage		; print usage if input is too large

.loop:
	xadd rbx, rax		; compute: (rbx, rax) <-- (rax + rbx, rbx)
	loopnz .loop		; loop if positive

.finished:
	mov rdi, fmt_output	; format string for output
	mov rsi, rax		; fib(n)
	mov rax, 0		; no fp registers in use
	call printf
	jmp .done

.done:
	mov rax, 0		; status OK for OS

	mov rsp, rbp		; restore original stack-pointer
	pop rbp			; set fp to point to previous frame
	ret

.usage:
	mov rdi, qword [stderr]	; errors go to stderr
	mov rsi, fmt_usage	; explain correct usage
	mov rax, 0		; no fp registers in use
	call fprintf		; send output to stderr...

	mov rax, -1		; status NOT OK
	call exit		; exit as per error

section .note.GNU-stack noalloc noexec
