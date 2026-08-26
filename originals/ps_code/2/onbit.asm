global main

main:
   mov rax, 0x1234
   bt rax, 3
   jc bit_is_on
   mov rbx, 5
   add rax, rbx
bit_is_on: 
        nop
