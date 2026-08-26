; factorial using MUL for calculating 10!

global main 

main:
    mov rcx, 10             ; rcx contains 10 in order to get 10!
    mov rax, 1              ; rax is the accuulator
    cqo                    ; "clean" rdx before multiplying
cont:
     cmp rcx, 1
     jz done
     mul rcx
     loop cont

done: 
     nop
    
     
