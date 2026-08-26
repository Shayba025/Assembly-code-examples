global main

main:
   mov rax, 0           ;  rax use as accumulator
   mov rbx, 5           ; rbx contains the number we have to sum up every stepjm
   mov rcx, 5          ; rcx use as a counter for five numbers. at each stage it decremented 
   cont: 
      add rax, rbx
      cmp rcx, 0
      jz end
      dec rcx
      add rbx, 5
      jmp cont
  end: 
       nop  

