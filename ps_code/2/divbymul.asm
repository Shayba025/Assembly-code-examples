global main

; calculating 64/7 by mul with inverse number of 7 64*1/7

main: 
    mov rdi, 64
    mov rsi, 7 
    mov rax, 1
     shl rax, 63     ;now rax = 2^63
   xor rdx, rdx      ; rdx is the high  64 bits of the result or residue. 
    div rsi          ; rax = 2^63/7 still not the inverse, rdx = residue
    shl rax, 1      ; rax = 2^64 , a necessary step to get the inverse
    mov rcx, rax
    mov rax, rdi
   mul rcx         ; rdx:rax = a*1/b
   mov rax, rdx    ; the highest 64 bits are the result
   nop
