global main

main:
    mov rax, 0x1122334455667788
    mov rbx, 0x0000ffffffffffff
    and rax, rbx
    nop
