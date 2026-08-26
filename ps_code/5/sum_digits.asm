section .text
global sum_digits

;long sum_digits (long n)
; argument : rdi
; return : rax = sum of digits

sum_digits:
   push rbp
   mov rbp, rsp
   
  ;base case : n< 10 so return n
  cmp rdi, 10
  jl .base_case
  
  ;recursive case : sum_digits(n/10) + n%10
  
  ;save n
  push rdi
  
  ;compute n/10
  mov rax, rdi
  xor rdx, rdx       ; clean rdx since later rdx stores the digit 
  mov rcx, 10
  div rcx           ; rax = n/10  rdx = n%10
  
  push rdx          ; [rsp]=last digit
  
  mov rdi, rax
   call sum_digits   ; rax = sum_digits(n/10)
  ;restore n
  pop rdx            ; rdx=last digit
  pop rdi           ; restore original n  in order to clean stack 

  ;add last_digit n%10
add rax, rdx 
  
  jmp .done
.base_case:
    mov rax, rdi     ; return n
.done:
   leave 
    ret 



