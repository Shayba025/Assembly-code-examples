default rel
section .bss
    buf: resb 256

section .text
global _start

_start:
    mov rax, 0
    mov rdi, 0
    mov rsi, buf
    mov rdx, 256
    syscall
    mov rdx, rax
	
	dec rdx
	xor rcx, rcx
	
	mov r12, rax
	
.rev_loop:
    cmp rcx, rdx
    jge .rev_done

    mov al, [buf+rcx]
    mov bl, [buf+rdx]
    mov [buf+rcx], bl
    mov [buf+rdx], al

    inc rcx
    dec rdx
    jmp .rev_loop

.rev_done:

    mov rax, 1
    mov rdi, 1
    mov rsi, buf
    mov rdx, r12
    syscall

    mov rax, 60
    xor rdi, rdi
    syscall
