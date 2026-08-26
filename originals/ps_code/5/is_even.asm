section .text
global is_even
global is_odd

;long is_even (long n)
; rdi = n
; return rax=1 if even and rax = 0 if odd

is_even:
   push rbp
   mov rbp,rsp
   cmp rdi, 0
   je .even_base
   ;recursive case : is_odd (n-1)
   dec rdi  
   call is_odd
   jmp .even_done
   
.even_base: 
   mov rax, 1
.even_done: 
   leave
   ret
;long is_odd (long n)
; rdi = n
; return rax=1 if odd  and rax = 0 if even

is_odd:
   push rbp
   mov rbp,rsp
   cmp rdi, 0
   je .odd_base 
   ;recursive case : is_even(n-1)
   dec rdi 
   call is_even
   jmp .done
   
.odd_base: 
   mov rax, 0 
.done: 
   leave
   ret
  
