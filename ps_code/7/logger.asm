; logger.asm — print "SIGINT received" when Ctrl+C is pressed

section .data
    msg:        db "SIGINT received", 10
    msg_len:    equ $ - msg

section .bss
    ; struct sigaction on x86-64:
    ; sa_handler  (8)
    ; sa_flags    (8)
    ; sa_restorer (8)
    ; sa_mask     (128)  ; sigset_t
    sa:         resb 8 + 8 + 8 + 128    ; 152 bytes

section .text
global main

; --- restorer: used when handler returns ---
; kernel jumps here after your handler's 'ret'
; must call sys_rt_sigreturn (15)
restorer:
    mov     rax, 15            ; sys_rt_sigreturn
    syscall                     ; does not return

; --- signal handler ---
sigint_handler:
    mov     rax, 1             ; sys_write
    mov     rdi, 1             ; stdout
    mov     rsi, msg
    mov     rdx, msg_len
    syscall
    ret                        ; return to kernel's signal frame

main:
    ; sa_handler = sigint_handler
    mov     qword [sa], sigint_handler

    ; sa_flags = SA_RESTORER (0x04000000)
    mov     qword [sa+8], 0x04000000

    ; sa_restorer = restorer
    mov     qword [sa+16], restorer

    ; sa_mask = 0 (128 bytes)
    lea     rdi, [sa+24]
    mov     rcx, 16            ; 16 qwords = 128 bytes
    xor     rax, rax
.zero_mask:
    mov     [rdi], rax
    add     rdi, 8
    loop    .zero_mask

    ; rt_sigaction(SIGINT, &sa, NULL, 8)
    mov     rax, 13            ; sys_rt_sigaction
    mov     rdi, 2             ; SIGINT
    lea     rsi, [sa]      ; &sa
    xor     rdx, rdx           ; oldact = NULL
    mov     r10, 8             ; sigsetsize = 8 on your system
    syscall

.loop:
    jmp     .loop              ; infinite loop, waiting for signals
