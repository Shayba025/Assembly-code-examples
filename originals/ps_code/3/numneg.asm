global main



n equ 10              ; number of numbers in vec

section .data
   vec dw 9865h, 0ab54h,  12a6h, 6875h, 8abdh, 0dfdfh, 0eacfh, 4fddh, 5eeeh, 0cbd4h
 
section .bss
  count  resb 1 

section .text

main:
   lea rdi, [vec]
   mov  rcx, n
    xor eax, eax
    xor rbx, rbx
  loop1:
      mov ax, [rdi]
     and ax, 8000h
     jz cont
     inc rbx
cont:
     add rdi, 2
     loop loop1
     ;lea rdi, [num]
     lea rdi, [count]
     mov byte [rdi], bl
     ret
      

   
  
