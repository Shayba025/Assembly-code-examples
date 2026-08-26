; ackermann_safe.asm — safe Ackermann A(2, n) using syscalls only

global _start

section .data
msg: db "Ackermann A(2,4) = ", 0
nl:  db 10, 0

section .bss
buf: resb 32

section .text

; -------------------------
; print_str(rdi = address)
; -------------------------
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

; -------------------------
; print_int(rdi = value)
; -------------------------
print_int:
    push rax
    push rbx
    push rcx
    push rdx
    mov rax, rdi
    mov rbx, 10
    lea rdi, [buf+31]
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
    mov rdx, buf+31
    sub rdx, rdi
    mov rax, 1
    mov rdi, 1
    syscall
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -------------------------
; ackermann2(n) = A(2, n)
; -------------------------
ack2:
    push rbp
    mov rbp, rsp

    cmp rdi, 0
    jne .rec
    mov rax, 3
    jmp .out

.rec:
    dec rdi
    push rdi
    call ack2
    add rsp, 8
    add rax, 2
    jmp .out

.out:
    mov rsp, rbp
    pop rbp
    ret

; -------------------------
; _start
; -------------------------
_start:
    mov rdi, msg
    call print_str

    mov rdi, 4
    call ack2

    mov rdi, rax
    call print_int

    mov rdi, nl
    call print_str

    mov rax, 60
    xor rdi, rdi
    syscall
