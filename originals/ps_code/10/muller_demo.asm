; ============================================================================
;  muller_demo.asm -- Trace Muller's method, iteration by iteration, on the
;                     Chebyshev polynomial T3(x) = 4x^3 - 3x.
;                     Real roots: 0 and +/- cos(pi/6) = +/- 0.8660254...
;
;  Starting from the three real points 0.5, 0.7, 0.9 the iteration converges
;  to cos(pi/6).  Each line prints the new approximation x and the residual
;  |f(x)|, so you can watch the quadratic (~1.84-order) convergence.
;
;  Build:  nasm -f elf64 muller_demo.asm -o muller_demo.o
;          gcc  -no-pie  muller_demo.o   -o muller_demo  &&  ./muller_demo
; ============================================================================
global  main
extern  printf

%define MAXIT 40

section .rodata
hdr  db "Muller on T3(x) = 4x^3 - 3x   (root sought: cos(pi/6) = 0.8660254038)",10
     db "------------------------------------------------------------------------",10
     db " iter         x (real part)        x (imag part)        | f(x) |",10,0
row  db "  %2d   %+.15f   %+.2e   %.3e",10,0
fin  db "------------------------------------------------------------------------",10
     db "converged to x = %.16f   (exact cos(pi/6) = 0.8660254037844386)",10,0

section .data
align 8
coef  dq 0.0, -3.0, 0.0, 4.0        ; T3 : c0=0, c1=-3, c2=0, c3=4
deg   dq 3
s0r dq 0.5
s1r dq 0.7
s2r dq 0.9
four dq 4.0
tol2 dq 1.0e-32

section .bss
align 8
itc  resd 1
mret resq 1
ev_acc resq 2
cdiv_den resq 1
csqrt_m resq 1
mx0 resq 2
mx1 resq 2
mx2 resq 2
mx3 resq 2
mf0 resq 2
mf1 resq 2
mf2 resq 2
mf3 resq 2
mh0 resq 2
mh1 resq 2
md0 resq 2
md1 resq 2
mA  resq 2
mB  resq 2
mC  resq 2
mdsc resq 2
mden resq 2
mt1 resq 2
mt2 resq 2
mbp resq 2
mbm resq 2
mnum resq 2
mq  resq 2
mdel resq 2

section .text
; ---- complex helpers (rdi=dst, rsi=a, rdx=b) ----
cadd:
        fld qword [rsi]
        fadd qword [rdx]
        fld qword [rsi+8]
        fadd qword [rdx+8]
        fstp qword [rdi+8]
        fstp qword [rdi]
        ret
csub:
        fld qword [rsi]
        fsub qword [rdx]
        fld qword [rsi+8]
        fsub qword [rdx+8]
        fstp qword [rdi+8]
        fstp qword [rdi]
        ret
cmul:
        fld qword [rsi]
        fmul qword [rdx]
        fld qword [rsi+8]
        fmul qword [rdx+8]
        fsubp st1, st0
        fld qword [rsi]
        fmul qword [rdx+8]
        fld qword [rsi+8]
        fmul qword [rdx]
        faddp st1, st0
        fstp qword [rdi+8]
        fstp qword [rdi]
        ret
cdiv:
        fld qword [rdx]
        fmul st0, st0
        fld qword [rdx+8]
        fmul st0, st0
        faddp st1, st0
        fstp qword [cdiv_den]
        fld qword [rsi]
        fmul qword [rdx]
        fld qword [rsi+8]
        fmul qword [rdx+8]
        faddp st1, st0
        fdiv qword [cdiv_den]
        fld qword [rsi+8]
        fmul qword [rdx]
        fld qword [rsi]
        fmul qword [rdx+8]
        fsubp st1, st0
        fdiv qword [cdiv_den]
        fstp qword [rdi+8]
        fstp qword [rdi]
        ret
csqrt:
        fld qword [rsi]
        fmul st0, st0
        fld qword [rsi+8]
        fmul st0, st0
        faddp st1, st0
        fsqrt
        fst qword [csqrt_m]
        fadd qword [rsi]
        fld1
        fld1
        faddp st1, st0
        fdivp st1, st0
        fsqrt
        fstp qword [rdi]
        fld qword [csqrt_m]
        fsub qword [rsi]
        fld1
        fld1
        faddp st1, st0
        fdivp st1, st0
        fsqrt
        fld qword [rsi+8]
        ftst
        fnstsw ax
        fstp st0
        sahf
        jnc .pos
        fchs
.pos:
        fstp qword [rdi+8]
        ret
cmag2:
        fld qword [rsi]
        fmul st0, st0
        fld qword [rsi+8]
        fmul st0, st0
        faddp st1, st0
        ret

ceval:                                  ; rdi=dst, rsi=z  (P over coef[0..deg])
        push rbx
        push r14
        push r15
        mov rbx, rdi
        mov r14, rsi
        mov rax, [deg]
        fld qword [coef + rax*8]
        fstp qword [ev_acc]
        fldz
        fstp qword [ev_acc+8]
        mov r15, rax
        dec r15
.l:
        test r15, r15
        js .d
        lea rdi, [ev_acc]
        lea rsi, [ev_acc]
        mov rdx, r14
        call cmul
        fld qword [ev_acc]
        fadd qword [coef + r15*8]
        fstp qword [ev_acc]
        dec r15
        jmp .l
.d:
        mov rax, [ev_acc]
        mov [rbx], rax
        mov rax, [ev_acc+8]
        mov [rbx+8], rax
        pop r15
        pop r14
        pop rbx
        ret

; ============================================================================
main:
        push rbp
        mov rbp, rsp
        push rbx
        push r12                         ; 3 pushes -> 16-aligned
        and rsp, -16

        lea rdi, [hdr]
        xor eax, eax
        call printf

        ; seed triple (real)
        mov rax, [s0r]
        mov [mx0], rax
        xor rax, rax
        mov [mx0+8], rax
        mov rax, [s1r]
        mov [mx1], rax
        mov qword [mx1+8], 0
        mov rax, [s2r]
        mov [mx2], rax
        mov qword [mx2+8], 0
        lea rdi,[mf0]
        lea rsi,[mx0]
        call ceval
        lea rdi,[mf1]
        lea rsi,[mx1]
        call ceval
        lea rdi,[mf2]
        lea rsi,[mx2]
        call ceval
        mov dword [itc], 0
        mov r12d, MAXIT
.iter:
        lea rdi,[mh0]
        lea rsi,[mx1]
        lea rdx,[mx0]
        call csub
        lea rdi,[mh1]
        lea rsi,[mx2]
        lea rdx,[mx1]
        call csub
        lea rdi,[mt1]
        lea rsi,[mf1]
        lea rdx,[mf0]
        call csub
        lea rdi,[md0]
        lea rsi,[mt1]
        lea rdx,[mh0]
        call cdiv
        lea rdi,[mt1]
        lea rsi,[mf2]
        lea rdx,[mf1]
        call csub
        lea rdi,[md1]
        lea rsi,[mt1]
        lea rdx,[mh1]
        call cdiv
        lea rdi,[mt1]
        lea rsi,[md1]
        lea rdx,[md0]
        call csub
        lea rdi,[mt2]
        lea rsi,[mh1]
        lea rdx,[mh0]
        call cadd
        lea rdi,[mA]
        lea rsi,[mt1]
        lea rdx,[mt2]
        call cdiv
        lea rdi,[mt1]
        lea rsi,[mA]
        lea rdx,[mh1]
        call cmul
        lea rdi,[mB]
        lea rsi,[mt1]
        lea rdx,[md1]
        call cadd
        mov rax,[mf2]
        mov [mC],rax
        mov rax,[mf2+8]
        mov [mC+8],rax
        lea rdi,[mt1]
        lea rsi,[mB]
        lea rdx,[mB]
        call cmul
        lea rdi,[mt2]
        lea rsi,[mA]
        lea rdx,[mC]
        call cmul
        fld qword [mt2]
        fmul qword [four]
        fstp qword [mt2]
        fld qword [mt2+8]
        fmul qword [four]
        fstp qword [mt2+8]
        lea rdi,[mt1]
        lea rsi,[mt1]
        lea rdx,[mt2]
        call csub
        lea rdi,[mdsc]
        lea rsi,[mt1]
        call csqrt
        lea rdi,[mbp]
        lea rsi,[mB]
        lea rdx,[mdsc]
        call cadd
        lea rdi,[mbm]
        lea rsi,[mB]
        lea rdx,[mdsc]
        call csub
        lea rsi,[mbp]
        call cmag2
        fstp qword [cdiv_den]
        lea rsi,[mbm]
        call cmag2
        fld qword [cdiv_den]
        fcomip st0, st1
        fstp st0
        jb .use_bm
        mov rax,[mbp]
        mov [mden],rax
        mov rax,[mbp+8]
        mov [mden+8],rax
        jmp .den_done
.use_bm:
        mov rax,[mbm]
        mov [mden],rax
        mov rax,[mbm+8]
        mov [mden+8],rax
.den_done:
        fld qword [mC]
        fadd st0, st0
        fstp qword [mnum]
        fld qword [mC+8]
        fadd st0, st0
        fstp qword [mnum+8]
        lea rdi,[mq]
        lea rsi,[mnum]
        lea rdx,[mden]
        call cdiv
        lea rdi,[mx3]
        lea rsi,[mx2]
        lea rdx,[mq]
        call csub
        lea rdi,[mf3]
        lea rsi,[mx3]
        call ceval
        lea rdi,[mdel]
        lea rsi,[mx3]
        lea rdx,[mx2]
        call csub

        ; ---- print this iteration ----
        inc dword [itc]
        lea rsi,[mf3]
        call cmag2
        fsqrt
        fstp qword [cdiv_den]               ; |f3|
        mov esi, [itc]
        movsd xmm0, [mx3]                   ; Re
        movsd xmm1, [mx3+8]                 ; Im
        movsd xmm2, [cdiv_den]              ; |f|
        lea rdi,[row]
        mov al, 3
        call printf

        ; ---- shift window ----
        mov rax,[mx1]
        mov [mx0],rax
        mov rax,[mx1+8]
        mov [mx0+8],rax
        mov rax,[mf1]
        mov [mf0],rax
        mov rax,[mf1+8]
        mov [mf0+8],rax
        mov rax,[mx2]
        mov [mx1],rax
        mov rax,[mx2+8]
        mov [mx1+8],rax
        mov rax,[mf2]
        mov [mf1],rax
        mov rax,[mf2+8]
        mov [mf1+8],rax
        mov rax,[mx3]
        mov [mx2],rax
        mov rax,[mx3+8]
        mov [mx2+8],rax
        mov rax,[mf3]
        mov [mf2],rax
        mov rax,[mf3+8]
        mov [mf2+8],rax

        ; ---- converged?  |delta|^2 < tol2 ----
        lea rsi,[mdel]
        call cmag2
        fld qword [tol2]
        fcomip st0, st1
        fstp st0
        jb .cont                           ; tol2 < |delta|^2 -> keep going
        jmp .done
.cont:
        dec r12d
        jnz .iter
.done:
        lea rdi,[fin]
        movsd xmm0,[mx2]
        mov al, 1
        call printf

        xor eax, eax
        lea rsp,[rbp-16]
        pop r12
        pop rbx
        pop rbp
        ret
