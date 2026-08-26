%macro PUSH 1 
   sub rsp, 8
   mov qword [rsp], %1 
%endmacro

%macro POP 1
   mov %1, qword [rsp]
   add rsp, 8
%endmacro

%macro CALL 1
   mov r12, %%L
   PUSH r12
   jmp %1
   %%L:
%endmacro

%macro RETURN 0
   POP rax 
   jmp rax
%endmacro

section .data
message: db "Hello world!",10,0
hebrew: db  "hakol oved heytev!",10,0
extern printf 
global main
section .text
main:
     enter 0,0
     mov rdi, message
     xor rax, rax  
     CALL printf 
     mov rdi, hebrew
     xor rax, rax 
     CALL printf 
     xor rax, rax 
     leave
     ret

section .note.GNU-stack 

    
