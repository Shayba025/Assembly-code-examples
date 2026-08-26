
global main

main: 
    mov rbx, 0x5566
    bsf rax, rbx
    bsr rcx, rbx
   nop
