global main

section .data
start_value dq 7           ; the series begins at 7

section .bss
seq resq 100            ; uninitialized array for series values
count resq 1            ; how many values are stored

section .text

 main:
    mov rax, [start_value]   ; current value
    lea rdi, [seq]            ;pointer to array
    xor rcx, rcx              ; counter = 0
	xor rbx, rbx 
Collatz_loop:
     mov qword [rdi], rax             ; store the current value in array 
     inc rcx
     add rdi, 8
     cmp rax, 1 
     je done
     test rax, 1           ; check if the number is odd
     jnz odd_case
even_case:
     shr rax, 1 
     jmp Collatz_loop
odd_case:
     mov rbx, rax
     shl rax, 1
     add rax , rbx
     inc rax
     jmp Collatz_loop
done:
    mov qword [count], rcx
    nop  
 
