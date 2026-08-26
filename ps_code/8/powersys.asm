; power_syscall.asm — compute 3^5 recursively and print result using syscalls

global _start

section .data
msg_pow:    db "3^5 = ", 0
msg_nl:     db 10, 0

section .bss
buf:        resb 32          ; buffer for integer to string

section .text

; -------------------------
; print_str(rdi = address)
; -------------------------
print_str:
    push rax
    push rdi
    mov rax, 0
.len_loop:
    cmp byte [rdi+rax], 0
    je .len_done
    inc rax
    jmp .len_loop
.len_done:
    mov rdx, rax        ; len
    pop rdi             ; restore pointer
    mov rax, 1          ; sys_write
    mov rsi, rdi
    mov rdi, 1          ; stdout
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
    sub rdx,  rdi
    mov rax, 1
	mov rdx, rdi
    mov rdi, 1
    syscall
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -------------------------
; pow(base, exp) -> rax
; base in rdi, exp in rsi
; -------------------------
pow:
    push rbp
    mov rbp, rsp

    cmp rsi, 0
    jne .recurse
    mov rax, 1
    jmp .out

.recurse:
    dec rsi
    push rdi
    push rsi
    call pow
    add rsp, 16
    mul rdi

.out:
    mov rsp, rbp
    pop rbp
    ret

; -------------------------
; _start
; -------------------------
_start:
    mov rdi, msg_pow
    call print_str

    mov rdi, 3      ; base
    mov rsi, 5      ; exponent
    call pow        ; rax = 3^5

    mov rdi, rax
    call print_int

    mov rdi, msg_nl
    call print_str

    mov rax, 60
    xor rdi, rdi
    syscall
