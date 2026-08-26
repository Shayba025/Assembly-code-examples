global main

main:
  mov rdi, 0x0f0f0f0f0f0f0f0f
   mov rax, 0
  cont:
       test rdi, rdi
      jz done
      shr rdi, 1
      adc eax, 1
      jmp cont
  done:
     nop    
