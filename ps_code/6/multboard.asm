section .data
fmt_int:     db '%4ld', 0
fmt_newline: db 10, 0

extern printf
global main

section .text
main:
    push rbp
    mov rbp, rsp

    mov rbx, 1          ; row = 1

row_loop:
    cmp rbx, 10
    jg done

    mov r12, 1          ; col = 1   <<< FIXED

col_loop:
    cmp r12, 10         ;           <<< FIXED
    jg end_row

    mov rax, rbx
    imul rax, r12       ; rax = row * col   <<< FIXED

    mov rdi, fmt_int
    mov rsi, rax
    xor rax, rax
    call printf

    inc r12             ;           <<< FIXED
    jmp col_loop

end_row:
    mov rdi, fmt_newline
    xor rax, rax
    call printf

    inc rbx
    jmp row_loop

done:
    mov rsp, rbp
    pop rbp
    ret
