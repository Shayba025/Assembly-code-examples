;;; dot-product-i32.asm
;;; demonstrating the dot-product of two 64-tuple vectors of 32-bit integers, 
;;; in only 8 iterations, using SSE/AVX
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
fmt_dot_product:
	db `The dot product is %ld\n\0`
align 64
A:
	dd 71, 50, 61, 64, 88, 68, 89, 99, 70, 59, 86, 41, 57, 10, 84, 57
	dd 90, 44, 68, 56, 87, 16, 95, 32, 56, 85, 52, 42, 71, 96, 56, 18
        dd 44, 47, 75, 80, 53, 84, 37, 25, 74, 58, 58, 60, 21, 72, 67, 79
        dd 24, 41, 29, 42, 52, 76, 33, 31, 91, 90, 83, 71, 92, 67, 76, 93
B:
	dd 80, 40, 74, 57, 98, 61, 84, 31, 96, 38, 87, 45, 60, 55, 64, 76
	dd 49, 86, 21, 47, 44, 28, 36, 56, 25, 72, 19, 12, 42, 82, 18, 34
        dd 96, 11, 51, 16, 17, 98, 70, 67, 17, 50, 55, 88, 40, 32, 52, 17
        dd 13, 37, 24, 73, 81, 18, 79, 55, 56, 67, 94, 17, 33, 72, 83, 33

;;; The dot product should be 211052

section .bss

extern printf
global main
section .text
main:
	push rbp
	mov rbp, rsp
	and rsp, -16

	mov rcx, 8		; loop counter
        mov rdx, 0
	vpxor ymm0, ymm0, ymm0	; zero out a 256-bit register
.L:
	vmovdqu ymm1, [A + rdx]	; load a packed 32-bit ints
	vmovdqu ymm2, [B + rdx]	; load a packed 32-bit ints
	vpmulld ymm3, ymm1, ymm2 ; packed multiply 32-bit ints
	vpaddd ymm0, ymm0, ymm3	 ; packed add 32-bit ints
        add rdx, 4*8 		 ; next displacement
	loopnz .L
.Lout:
	vextracti128 xmm1, ymm0, 1 ; move the upper (1) 128-bits to xmm1
	vpaddd xmm0, xmm0, xmm1	   ; packed add 32-bit ints
	vpshufd xmm1, xmm0, 0b10_11_00_01 ; shuffle 4 32-bit ints
	vpaddd xmm0, xmm0, xmm1		  ; packed add 32-bit ints
	vpshufd xmm1, xmm0, 0b01_00_10_11 ; shuffle 4 32-bit ints
	vpaddd xmm0, xmm0, xmm1		  ; packed add 32-bit ints

	movd eax, xmm0		; move the lower 32-bit int to eax, zero ext
	mov rsi, rax		; move the zero-extended eax to rsi --- arg
	mov rdi, fmt_dot_product ; format string for output
	mov rax, 0		 ; 0 xmm regs to preserve
	call printf		 ; ...and print

	mov rax, 0
	mov rsp, rbp
	pop rbp
	ret

section .note.GNU-stack noalloc noexec
