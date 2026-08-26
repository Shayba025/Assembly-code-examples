section .text
global asm_demo

asm_demo:
   push rbp
   mov rbp, rsp
   
   ;--------------------;
   ;  write to stdout (fd=1)
   ;-----------------------

    mov rax, 1      ; sys_write
    mov rdi, 1     ; stdout
    mov rsi, msg_out 
    mov rdx, msg_out_len 
    syscall

   ;--------------------;
   ;  write to stdout (fd=2)
   ;-----------------------

    mov rax, 1      ; sys_write
    mov rdi, 2     ; stderr
    mov rsi, msg_err 
    mov rdx, msg_err_len 
    syscall
   
  ;--------------------;
   ;  read from stdin  (fd=0)
   ;-----------------------

    mov rax, 0      ; sys_read
    mov rdi, 0     ; stdin
    mov rsi, buffer
    mov rdx, 50 
    syscall          ; rax = number of read bytes 

   ;--------------------;
   ;  echo input  to  stdout
   ;-----------------------

    mov rdi, 1     ; stdout
    mov rsi, buffer
    mov rdx, rax     ; print exactly what was read 
    mov rax, 1       ; sys write 
    syscall          
   
   leave
   ret

section .data
   msg_out: db "ASM:writing to stdout", 10
   msg_out_len  equ $ - msg_out
   msg_err : db "ASM:writing to stderr", 10
   msg_err_len  equ $ - msg_err
  
  section .bss
 buffer: resb 50

