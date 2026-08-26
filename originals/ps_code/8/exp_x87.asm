global _start

section .data
msg1:   db "Method 1 (2^(log2e)): ", 0
msg2:   db "Method 2 (Taylor):     ", 0
nl:     db 10, 0
dot:    db ".", 0

x_val:  dq 1.0
scale:  dq 10000000000.0        ; 10^10

section .bss
res1:   resq 1
res2:   resq 1
tmp:    resq 1
buf:    resb 64

section .text

_start:
    call compute_method1
    call compute_method2

    mov rdi, msg1
    call print_str
    mov rdi, res1
    call print_float_10dec
    mov rdi, nl
    call print_str

    ;mov rdi, msg2
    ;call print_str
    ;mov rdi, res2
    ;call print_float_10dec
    ;mov rdi, nl
    ;call print_str

    mov rax, 60
    xor rdi, rdi
    syscall

; -------------------------------------------------------
; compute_method1: e^x = 2^(x * log2(e))
;
;   y    = x * log2(e)
;   n    = round(y)          (integer exponent for fscale)
;   frac = y - n             (fraction for f2xm1)
;   e    = (2^frac - 1 + 1) * 2^n = (f2xm1+1) * 2^n
; -------------------------------------------------------
compute_method1:
    finit
	fld qword [x_val]		; st0 = x
    fldl2e                  ; st1 = log2(e)
    fmulp st1, st0          ; st0 = y = 1.0 * log2(e)

    fld st0                 ; st0 = y, st1 = y
    frndint                 ; st0 = n
	fsub st1, st0           ; st1 = frac = y - n, 
    fxch                    ; st0 = frac,  st1 = n

    f2xm1                   ; st0 = 2^frac - 1
    fld1
    faddp st1, st0          ; st0 = 2^frac
    fscale                  ; st0 = 2^frac * 2^n = e
    fstp qword [res1]
	fstp                	; pop n

    ret

; -------------------------------------------------------
; compute_method2: Taylor series  e = sum(1/k!, k=0..20)
; -------------------------------------------------------
compute_method2:
    finit
    fld1                    ; st0 = sum = 1   (k=0 term)
    fld1                    ; st0 = term = 1

    mov rcx, 20
    mov rbx, 1
.taylor_loop:
    mov [tmp], rbx
    fild qword [tmp]        ; st0 = k, st1 = term, st2 = sum
    fdivp st1, st0          ; st0 = term/k
    fadd st1, st0           ; st1 = sum + term/k
    inc rbx
    loop .taylor_loop

    fstp st0                ; pop last term
    fstp qword [res2]
    ret

; -------------------------------------------------------
; print_float_10dec(rdi = pointer to qword float)
;   prints INTPART.FRACDIGITS  (10 decimal digits)
; -------------------------------------------------------
print_float_10dec:
    fld qword [rdi]         ; st0 = value
    fld qword [scale]       ; st0 = 1e10, st1 = value
    fmulp st1, st0          ; st0 = value * 1e10
    fistp qword [tmp]

    mov rax, [tmp]
    mov rbx, 10000000000
    xor rdx, rdx
    div rbx                 ; rax = int part, rdx = frac digits

    mov rdi, rax
    call print_int
    call print_dot
    mov rdi, rdx
    call print_10digits
    ret

; -------------------------------------------------------
print_str:
    push rax
    push rdi
    mov rax, 0
.ps_len:
    cmp byte [rdi+rax], 0
    je .ps_done
    inc rax
    jmp .ps_len
.ps_done:
    mov rdx, rax
    pop rdi
    mov rax, 1
    mov rsi, rdi
    mov rdi, 1
    syscall
    pop rax
    ret

; -------------------------------------------------------
print_int:
    push rax
    push rbx
    push rcx
    push rdx
    mov rax, rdi
    mov rbx, 10
    lea rdi, [buf+63]
    mov byte [rdi], 0
    cmp rax, 0
    jne .pi_loop
    dec rdi
    mov byte [rdi], '0'
    jmp .pi_done
.pi_loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    cmp rax, 0
    jne .pi_loop
.pi_done:
    mov rsi, rdi
    mov rdx, buf+63
    sub rdx, rdi
    mov rax, 1
    mov rdi, 1
    syscall
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -------------------------------------------------------
print_dot:
    push rax
    push rdi
    push rsi
    push rdx
    mov rax, 1
    mov rdi, 1
    mov rsi, dot
    mov rdx, 1
    syscall
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; -------------------------------------------------------
; print_10digits: always prints exactly 10 digits (with leading zeros)
; -------------------------------------------------------
print_10digits:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    mov rcx, 10
    mov rax, rdi
    lea rbx, [buf+63]
    mov byte [rbx], 0

.p10_loop:
    xor rdx, rdx
    mov rsi, 10
    div rsi
    add dl, '0'
    dec rbx
    mov [rbx], dl
    loop .p10_loop

    mov rax, 1
    mov rdi, 1
    mov rsi, rbx
    mov rdx, 10
    syscall

    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret