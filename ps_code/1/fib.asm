global main 

main: 
   mov r8, 0           ;  0 is the first number of fibonaci series
   mov  r9, 1           ; 1 is the second number 
   mov rax, 1  
   mov rcx, 10          ; rcx use as a counter for 10  numbers. at each stage it decremented 
   cont: 
      mov r8, r9
      mov r9, rax
      add r8, r9
      mov  rax, r8
      loop cont
  end: 
       nop 

