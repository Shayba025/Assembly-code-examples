global main

section .text
; ------Macros
%macro PUSH64 1 
  sub  rsp, 8
  mov [rsp], %1
%endmacro

%macro POP64 1 
   mov %1 , [rsp]
   add rsp, 8
%endmacro

main:
  mov rax, 42
  PUSH64 rax
  mov rax, 0
  POP64 rax
  nop
