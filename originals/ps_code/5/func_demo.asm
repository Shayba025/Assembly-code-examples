section .data
  fmt db "add3(%d,%d,%d)=%d", 10, 0

section .text
global main
extern printf

;------------------------------
; long add3(long a, long b, long c) 
; arguments: rdi=a, rsi=b , rdx=d   
; returned value: rax  
;----------------------------------
add3:
   mov rax, rdi
   add rax, rsi
   add rax, rdx  ;rax = rdi+rsi+rdx
   ret           ; return the value of rax 

;-------------------------------------
; int main () demoonstrates calling to  add3
; from assembly 
;------------------------------------------
main:
  push rbp
  mov  rbp, rsp
  ;  prepare the arguments for add3  10, 20, 30 
  mov rdi, 10
  mov rsi, 20
  mov rdx, 30
  call add3       ; rax = 10+20+30

 ; prepare printf argumenrs
  mov rdi, fmt              ;format string
  mov esi, 10               ; first %d
  mov edx, 20               ;second %d
  mov ecx, 30               ; third %d
  mov r8d , eax             ; result
  xor eax, eax             ;demand for printf
  call printf

  mov rsp, rbp
  pop rbp
  ret 
