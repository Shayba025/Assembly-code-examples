global main

section .data
   start dw 4
   array dw 6 dup (0aaaah)
section .text

main:
     lea rdi, [array]
     mov rcx, 5
     xor eax, eax 
     mov ax, [start]
loop1:
      mov word [rdi], ax
      shl ax, 1
      inc ax
      add rdi, 2
      loop loop1
      xor eax, eax
      ret    
