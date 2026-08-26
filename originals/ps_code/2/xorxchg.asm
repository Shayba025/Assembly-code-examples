global main

main:
   mov rax, 0x1234
   mov rbx, 0x5678
   xor rax, rbx
   xor rbx, rax
   xor rax, rbx
   nop
