section .text
global add3

add3:
    mov rax, rdi
    add rax, rsi
    add rax, rdx
   ret
