;;; dot-product-f64.asm
;;; demonstrating the dot-product of two 64-tuple vectors of doubles,
;;; in only 16 iterations, using SSE/AVX
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
fmt_dot_product:
	db `The dot product is %f\n\0`
align 64
A:
        dq 58.31, 58.27, 84.72, 44.64, 50.70, 62.36, 46.86, 78.24
        dq 91.10, 95.37, 89.10, 96.47, 39.68, 22.91, 60.69, 77.88
        dq 23.58, 40.96, 58.31, 11.26, 18.24, 91.79, 63.92, 73.12
        dq 28.26, 29.76, 62.17, 98.93, 38.16, 33.87, 80.68, 23.68
        dq 22.37, 54.64, 81.46, 11.13, 78.57, 41.89, 83.30, 97.28
        dq 77.21, 85.38, 80.78, 46.94, 45.31, 51.45, 39.19, 12.60
        dq 56.80, 75.85, 17.56, 21.66, 23.57, 61.59, 21.29, 89.68
        dq 97.39, 64.10, 13.10, 77.91, 74.66, 77.85, 42.66, 69.84
B:
        dq 74.80, 66.13, 96.63, 14.69, 54.21, 45.71, 66.39, 37.81
        dq 50.73, 37.78, 84.43, 33.61, 45.97, 49.80, 14.49, 43.76
        dq 18.96, 37.93, 93.11, 29.90, 19.81, 53.22, 75.32, 32.18
        dq 69.17, 74.99, 71.34, 39.87, 42.30, 15.72, 63.75, 66.40
        dq 52.22, 80.36, 79.35, 63.58, 40.21, 57.12, 34.19, 90.87
        dq 43.69, 63.77, 87.68, 52.57, 56.92, 43.21, 70.41, 67.25
        dq 40.64, 51.19, 68.23, 26.75, 37.41, 66.67, 86.45, 28.10
        dq 45.36, 66.58, 12.30, 94.94, 36.39, 32.33, 94.39, 29.26

;;; The dot product should be 198188.457200

section .bss

extern printf
global main
section .text
main:
	push rbp
	mov rbp, rsp
	and rsp, -16

	mov rcx, 16
        mov rdx, 0
	vxorpd ymm0, ymm0, ymm0
.L:
	vmovupd ymm1, [A + rdx]
	vmovupd ymm2, [B + rdx]
        vfmadd231pd ymm0, ymm1, ymm2
        add rdx, 8*4
	loopnz .L
.Lout:
        vextractf128 xmm1, ymm0, 1
        vaddpd xmm0, xmm0, xmm1

        ; Either this:
        ; movhlps xmm1, xmm0

        ; Or these two lines
        movapd xmm1, xmm0
        unpckhpd xmm1, xmm1
        
        addsd xmm0, xmm1

	mov rsi, rax
	mov rdi, fmt_dot_product
	mov rax, 1
	call printf

	mov rax, 0
	mov rsp, rbp
	pop rbp
	ret

section .note.GNU-stack noalloc noexec
