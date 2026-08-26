%macro PUSH 1 
   sub rsp, 8
   mov qword [rsp], %1 
%endmacro

%macro POP 1
   mov %1, qword [rsp]
   add rsp, 8
%endmacro

%macro CALL 1
   lea  r11, [rel %%L]
   PUSH r11
   jmp %1
   %%L:
%endmacro

%macro RETURN 0
   POP r11 
   jmp  r11
%endmacro

section .data
fmt:    db "fact (%d)=%d" , 10, 0

section .text
global main
extern printf

fact:
   enter 0,0
   cmp rdi, 1
   jg .recursive
   mov rax, 1
   leave
   RETURN 
.recursive:
   PUSH rdi
   dec rdi
   CALL fact
   POP rdi 
   imul rax, rdi
   leave
   RETURN 
main:
    enter 0,0
    mov rdi, 5
    mov  r12, rdi
    CALL fact
    mov rsi, r12
    mov rdx, rax
    mov rdi, fmt
    xor rax, rax 
    CALL printf
    leave 
    ret 

section .note.GNU-stack 
