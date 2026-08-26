global main

section .data
   start db 17h
   array db 12 dup (55h)
section .text

main:
     lea rdi, [array]
     mov rcx, 12
     xor eax, eax 
     mov al, [start]
loop1:
      mov byte[rdi], al
      inc al
      inc rdi
      loop loop1
      xor eax, eax
      ret    
