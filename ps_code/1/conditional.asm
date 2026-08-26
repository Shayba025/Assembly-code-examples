section .text
global  main

main:
    mov rax, 10
    mov rbx, 20
    cmp rax, rbx
    jl less_than
    jg greater_than
    je  equal

less_than: 
             nop 
             nop 
            jmp exit
greater_than: 
             nop 
             nop 
            jmp exit
equal: 
             nop 
             nop 
            jmp exit
exit: 
            
           nop




