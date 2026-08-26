;;; code-0027.asm
;;; Finding the maximum and the minimum of a sample of doubles using SSE/AVX
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
sample:
        dq 96.1718, 80.8484, 95.2312, 12.1916
        dq 32.5818, 11.4896, 42.8641, 51.2455
        dq 52.1779, 56.3347, 14.8188, 92.1523
        dq 43.8695, 34.1928, 16.7395, 85.6557
        dq 44.5534, 94.9655, 86.8459, 32.1999
        dq 62.2914, 96.9621, 58.5607, 93.5703
        dq 22.3382, 96.7021, 35.8124, 57.9127
        dq 10.9557, 23.7534, 96.8266, 51.9063
        dq 34.8289, 21.8146, 90.9442, 13.7077
        dq 76.9575, 32.8763, 31.5055, 42.4096
        dq 53.8326, 32.4243, 73.5602, 85.7678
        dq 66.4255, 69.5429, 41.7452, 93.1886
        dq 27.9286, 47.5015, 89.9464, 42.7962
        dq 44.1866, 85.6127, 68.9273, 16.6703
        dq 48.8974, 80.5159, 77.6592, 12.7647
        dq 30.8304, 79.5308, 94.7173, 36.2284
        dq 87.2777, 27.4244, 56.3336, 15.6792
        dq 21.3969, 85.3258, 34.4592, 57.1645
        dq 32.6628, 35.8243, 12.1827, 61.9408
        dq 73.1785, 31.8773, 63.6888, 18.4526
        dq 63.7494, 94.3193, 12.1066, 50.5095
        dq 82.3048, 27.9579, 25.4646, 39.3162
        dq 52.8395, 36.1814, 54.4841, 87.5964
        dq 52.1535, 97.2988, 99.9001, 92.5129
        dq 84.9077, 80.9838, 97.6403, 14.6752
        dq 61.3047, 81.3916, 73.1201, 43.9868
        dq 58.7898, 21.4613, 60.2337, 10.7538
        dq 34.1944, 26.3309, 93.2193, 47.3578
        dq 20.3761, 45.5243, 12.7449, 54.3413
        dq 81.6804, 68.6813, 48.7148, 54.1934
        dq 62.8312, 90.3593, 72.9626, 79.6045
        dq 19.6616, 64.8917, 43.5148, 29.5925
        dq 71.9392, 79.4136, 78.5343, 81.6629
        dq 84.6281, 54.8005, 62.3565, 95.8625
        dq 61.5016, 58.4369, 86.4835, 80.3342
        dq 12.7024, 32.5363, 52.5692, 67.8161
        dq 79.3387, 18.1344, 57.5913, 64.5804
        dq 21.5105, 80.5835, 93.4775, 82.5121
        dq 61.4172, 35.9423, 75.9389, 31.8715
        dq 73.4112, 98.7219, 53.2434, 49.5041
        dq 74.2182, 94.5252, 53.1548, 52.7846
        dq 89.9503, 65.9427, 46.6071, 11.3474
        dq 69.7084, 90.3573, 37.8022, 11.8797       
N:
	dq ($ - sample) >> 3
fmt_output:
	db `min(sample) = %g; max(sample) = %g\n\0`
        

section .bss

extern printf
global main
section .text
main:
	push rbp
	mov rbp, rsp
        and rsp, -16

        mov rcx, qword [N]
        shr rcx, 2
        dec rcx
        mov rdx, 32
        vmovupd ymm0, [sample]
        vmovapd ymm1, ymm0

.Loop:
        vmovupd ymm2, [sample + rdx]
        vminpd ymm0, ymm0, ymm2
        vmaxpd ymm1, ymm1, ymm2
        add rdx, 8*4
        loopnz .Loop

        vextractf128 xmm2, ymm0, 1
        vminpd xmm0, xmm0, xmm2
        vextractf128 xmm2, ymm1, 1
        vmaxpd xmm1, xmm1, xmm2

        movapd xmm2, xmm0
        unpckhpd xmm2, xmm2
        vminsd xmm0, xmm0, xmm2

        movapd xmm2, xmm1
        unpckhpd xmm2, xmm2
        vmaxsd xmm1, xmm1, xmm2

        mov rdi, fmt_output
        mov rax, 2              ; |{xmm0, xmm1}| = 2
        call printf        

        mov rax, 0
	mov rsp, rbp
	pop rbp
	ret

section .note.GNU-stack noalloc noexec
