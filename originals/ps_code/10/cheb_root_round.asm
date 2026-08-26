; ============================================================================
;  cheb_root_round.asm -- Round a ROOT of a Chebyshev polynomial under each of
;                         the four x87 rounding modes, at double precision.
;
;  Build:
;       nasm -f elf64 cheb_root_round.asm -o cheb_root_round.o
;       gcc  -no-pie  cheb_root_round.o   -o cheb_root_round
;       ./cheb_root_round 4          (N; degree d = 2N; default N=2)
;
;  Two roots are examined, both irrational:
;    (A) the positive root of T_2 = 2x^2 - 1 :  r = sqrt(1/2)  (= cos(pi/4))
;    (B) the largest root of T_{2N}          :  r = cos(pi/(2d))
;
;  For each rounding mode we recompute r with PC = 53 (double) and print
;  17 significant digits AND the raw 64-bit IEEE-754 bit pattern, so the
;  one-ULP differences between the modes are unmistakable.
; ============================================================================

global  main
extern  printf

section .rodata
hdrA   db 10,"(A) r = sqrt(1/2) = positive root of T_2 = 2x^2 - 1",10
       db    "    exact value is irrational; the last bit depends on rounding mode",10,0
hdrB   db 10,"(B) r = cos(pi/2d) = largest root of T_%d (d = %d)",10,0
line   db    "  RC=%d %-24s r = %.17g   bits = 0x%016llx",10,0

n_near db "nearest (ties to even)",0
n_down db "down  (toward -inf)",0
n_up   db "up    (toward +inf)",0
n_chop db "toward zero (chop)",0

section .data
align 8
names  dq n_near, n_down, n_up, n_chop
half   dq 0.5

section .bss
align 8
cw     resw 1
savecw resw 1
res    resq 1
Dval   resd 1
iden   resd 1

section .text

; RC = (edi & 3), keep other fields
set_round:
        fstcw   [cw]
        mov     ax, [cw]
        and     ax, 0xF3FF
        mov     cx, di
        and     cx, 3
        shl     cx, 10
        or      ax, cx
        mov     [cw], ax
        fldcw   [cw]
        ret

; PC = 53-bit double
set_prec_double:
        fstcw   [cw]
        mov     ax, [cw]
        and     ax, 0xFCFF
        or      ax, 0x0200
        mov     [cw], ax
        fldcw   [cw]
        ret

main:
        push    rbp
        mov     rbp, rsp
        push    rbx
        push    r12             ; 3 pushes -> 16-aligned
        fstcw   [savecw]

        ; ---- N from argv[1] (default 2) ----
        mov     r12d, 2
        cmp     edi, 2
        jl      .haveN
        mov     rdi, [rsi + 8]
        xor     ecx, ecx
.atoi:
        movzx   edx, byte [rdi]
        sub     dl, '0'
        cmp     dl, 9
        ja      .atoi_done
        imul    ecx, ecx, 10
        movzx   edx, dl
        add     ecx, edx
        inc     rdi
        jmp     .atoi
.atoi_done:
        test    ecx, ecx
        jz      .haveN
        mov     r12d, ecx
.haveN:
        mov     eax, r12d
        add     eax, eax
        mov     [Dval], eax     ; d = 2N

        call    set_prec_double ; all results land directly in 53-bit double

        ; =================== (A) sqrt(1/2) ===================
        lea     rdi, [hdrA]
        xor     eax, eax
        call    printf

        xor     ebx, ebx
.loopA:
        mov     edi, ebx
        call    set_round
        fld     qword [half]
        fsqrt                   ; sqrt(0.5), rounded per current mode
        fstp    qword [res]
        lea     rdi, [line]
        mov     esi, ebx
        mov     rdx, [names + rbx*8]
        movsd   xmm0, [res]
        mov     rcx, [res]      ; raw bits for the %llx field
        mov     al, 1           ; one xmm (double) arg
        call    printf
        inc     ebx
        cmp     ebx, 4
        jl      .loopA

        ; =================== (B) cos(pi/2d) ===================
        lea     rdi, [hdrB]
        mov     esi, r12d
        mov     edx, [Dval]
        xor     eax, eax
        call    printf

        xor     ebx, ebx
.loopB:
        mov     edi, ebx
        call    set_round
        fldpi
        mov     eax, [Dval]
        add     eax, eax        ; 2d
        mov     [iden], eax
        fild    dword [iden]
        fdivp   st1, st0        ; pi/(2d)
        fcos                    ; cos(pi/2d), rounded per current mode
        fstp    qword [res]
        lea     rdi, [line]
        mov     esi, ebx
        mov     rdx, [names + rbx*8]
        movsd   xmm0, [res]
        mov     rcx, [res]
        mov     al, 1
        call    printf
        inc     ebx
        cmp     ebx, 4
        jl      .loopB

        fldcw   [savecw]
        xor     eax, eax
        pop     r12
        pop     rbx
        pop     rbp
        ret
