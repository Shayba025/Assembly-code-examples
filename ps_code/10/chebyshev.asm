; ============================================================================
;  chebyshev.asm -- Build the Chebyshev polynomial T_{2N} by its recurrence,
;                   then find ALL of its (real) roots with MULLER'S METHOD,
;                   deflating after each root.  Every floating-point operation
;                   is done on the x87 FPU.
;
;  Build (Linux, x86-64):
;       nasm -f elf64 chebyshev.asm -o chebyshev.o
;       gcc  -no-pie  chebyshev.o   -o chebyshev
;       ./chebyshev 4            <-- N (defaults to 2 if omitted); degree = 2N
;
;  Recurrence used to build the coefficient vector:
;       T0 = 1 ,  T1 = x ,  T_{k+1} = 2*x*T_k - T_{k-1}
;
;  Müller's method (quadratic interpolation through 3 points, complex-safe):
;       h0 = x1-x0 , h1 = x2-x1
;       d0 = (f1-f0)/h0 , d1 = (f2-f1)/h1
;       A  = (d1-d0)/(h1+h0) ,  B = A*h1 + d1 ,  C = f2
;       x3 = x2 - 2C / ( B +/- sqrt(B^2-4AC) )   [sign chosen for max |denom|]
;
;  All roots of T_m are known exactly:  cos((2k-1)*pi/(2m)), k=1..m.
;  The program prints that exact value next to each computed root so you can
;  see the error.
; ============================================================================

global  main
extern  printf

%define MAXD 64                     ; maximum supported degree (N <= 32)
%define MAXIT 400                   ; Müller iteration cap

; ----------------------------------------------------------------------------
section .rodata
banner  db 10,"Chebyshev T_%d  (degree d = 2N = %d).  Leading coeff = 2^(d-1).",10
        db    "Finding all %d real roots by recurrence + Muller + deflation.",10,10,0
col_hd  db    "  k        computed root        exact cos((2k-1)pi/2d)        error",10
        db    " ---  ----------------------  ----------------------  ------------",10,0
row_fmt db    " %3d   %+.16f   %+.16f   %+.2e",10,0
done_ln db 10,"All %d roots found.  (compare 'computed' vs 'exact').",10,0

section .data
align 8
; --- Müller starting triple (a small imaginary part breaks the symmetry of
;     the even polynomial so the iteration never stalls on the real axis) ---
s0r dq -0.10
s0i dq  0.00
s1r dq  0.00
s1i dq  0.20
s2r dq  0.10
s2i dq  0.00

two   dq 2.0
four  dq 4.0
tol2  dq 1.0e-26          ; convergence: |x3-x2|^2 below this
ftol2 dq 1.0e-28          ; or |f(x3)|^2 below this

section .bss
align 8
Dorig   resd 1            ; original degree d = 2N
deg     resq 1            ; current (deflating) degree
coef    resq MAXD+1       ; working polynomial coefficients c[0..deg]
buf0    resq MAXD+1       ; recurrence scratch (3 rotating buffers)
buf1    resq MAXD+1
buf2    resq MAXD+1
qb      resq MAXD+1       ; deflation quotient
roots   resq MAXD+1       ; collected roots
rootr   resq 1            ; current root (real)
carry   resq 1            ; synthetic-division accumulator
inum    resd 1            ; integer scratch for exact-value formula
iden    resd 1
exactv  resq 1
errv    resq 1

; complex scratch cells (re at +0, im at +8) used by helper routines
ev_acc  resq 2            ; Horner accumulator for ceval
cdiv_den resq 1           ; |denominator|^2 for cdiv
csqrt_m resq 1            ; |.| for csqrt
mret    resq 1            ; muller result (real part of converged root)

; complex working set for Müller
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

; ============================================================================
;  COMPLEX HELPERS   (rdi = dst, rsi = a, rdx = b ; all 16-byte complex)
;  Inputs are fully loaded before any store, so dst may alias a or b.
; ============================================================================
section .text

; dst = a + b
cadd:
        fld     qword [rsi]
        fadd    qword [rdx]
        fld     qword [rsi+8]
        fadd    qword [rdx+8]
        fstp    qword [rdi+8]
        fstp    qword [rdi]
        ret

; dst = a - b
csub:
        fld     qword [rsi]
        fsub    qword [rdx]
        fld     qword [rsi+8]
        fsub    qword [rdx+8]
        fstp    qword [rdi+8]
        fstp    qword [rdi]
        ret

; dst = a * b
cmul:
        fld     qword [rsi]         ; ar
        fmul    qword [rdx]         ; ar*br
        fld     qword [rsi+8]       ; ai
        fmul    qword [rdx+8]       ; ai*bi
        fsubp   st1, st0            ; re = ar*br - ai*bi
        fld     qword [rsi]         ; ar
        fmul    qword [rdx+8]       ; ar*bi
        fld     qword [rsi+8]       ; ai
        fmul    qword [rdx]         ; ai*br
        faddp   st1, st0            ; im = ar*bi + ai*br   (st0=im, st1=re)
        fstp    qword [rdi+8]
        fstp    qword [rdi]
        ret

; dst = a / b
cdiv:
        ; denom = br^2 + bi^2  -> [cdiv_den]
        fld     qword [rdx]
        fmul    st0, st0
        fld     qword [rdx+8]
        fmul    st0, st0
        faddp   st1, st0
        fstp    qword [cdiv_den]
        ; re = (ar*br + ai*bi)/denom
        fld     qword [rsi]
        fmul    qword [rdx]
        fld     qword [rsi+8]
        fmul    qword [rdx+8]
        faddp   st1, st0
        fdiv    qword [cdiv_den]
        ; im = (ai*br - ar*bi)/denom
        fld     qword [rsi+8]
        fmul    qword [rdx]
        fld     qword [rsi]
        fmul    qword [rdx+8]
        fsubp   st1, st0
        fdiv    qword [cdiv_den]    ; st0=im, st1=re
        fstp    qword [rdi+8]
        fstp    qword [rdi]
        ret

; dst = sqrt(a)     principal branch
csqrt:
        ; m = |a| = sqrt(u^2+v^2)
        fld     qword [rsi]
        fmul    st0, st0
        fld     qword [rsi+8]
        fmul    st0, st0
        faddp   st1, st0
        fsqrt
        fst     qword [csqrt_m]     ; keep m
        ; re = sqrt((m+u)/2)
        fadd    qword [rsi]         ; m+u
        fld1
        fld1
        faddp   st1, st0            ; 2.0
        fdivp   st1, st0            ; (m+u)/2
        fsqrt
        fstp    qword [rdi]         ; store re
        ; |im| = sqrt((m-u)/2)
        fld     qword [csqrt_m]
        fsub    qword [rsi]         ; m-u
        fld1
        fld1
        faddp   st1, st0
        fdivp   st1, st0
        fsqrt                       ; |im|
        ; apply sign of v
        fld     qword [rsi+8]       ; v   (st0=v, st1=|im|)
        ftst
        fnstsw  ax
        fstp    st0                 ; drop v -> st0=|im|
        sahf
        jnc     .pos                ; CF=0 -> v>=0
        fchs
.pos:
        fstp    qword [rdi+8]
        ret

; |a|^2 in st0   (rsi = a)
cmag2:
        fld     qword [rsi]
        fmul    st0, st0
        fld     qword [rsi+8]
        fmul    st0, st0
        faddp   st1, st0
        ret

; ----------------------------------------------------------------------------
; ceval: dst(rdi) = P(z),  z = (rsi).  Horner over global coef[0..deg].
;        preserves rbx,r14,r15 (callee-saved) which it uses.
; ----------------------------------------------------------------------------
ceval:
        push    rbx
        push    r14
        push    r15
        mov     rbx, rdi            ; dst
        mov     r14, rsi            ; z
        mov     rax, [deg]
        fld     qword [coef + rax*8]
        fstp    qword [ev_acc]      ; acc.re = coef[deg]
        fldz
        fstp    qword [ev_acc+8]    ; acc.im = 0
        mov     r15, rax
        dec     r15                 ; i = deg-1
.loop:
        test    r15, r15
        js      .done               ; i < 0
        lea     rdi, [ev_acc]       ; acc = acc * z
        lea     rsi, [ev_acc]
        mov     rdx, r14
        call    cmul
        fld     qword [ev_acc]      ; acc.re += coef[i]
        fadd    qword [coef + r15*8]
        fstp    qword [ev_acc]
        dec     r15
        jmp     .loop
.done:
        mov     rax, [ev_acc]       ; *dst = acc
        mov     [rbx], rax
        mov     rax, [ev_acc+8]
        mov     [rbx+8], rax
        pop     r15
        pop     r14
        pop     rbx
        ret

; ============================================================================
;  muller: find one root of the current coef[0..deg]; real part -> [mret]
; ============================================================================
muller:
        push    rbx
        push    r12
        ; load starting triple
        mov     rax,[s0r]
        mov     [mx0],rax
        mov     rax,[s0i]
        mov     [mx0+8],rax
        mov     rax,[s1r]
        mov     [mx1],rax
        mov     rax,[s1i]
        mov     [mx1+8],rax
        mov     rax,[s2r]
        mov     [mx2],rax
        mov     rax,[s2i]
        mov     [mx2+8],rax
        lea     rdi,[mf0]
        lea     rsi,[mx0]
        call    ceval
        lea     rdi,[mf1]
        lea     rsi,[mx1]
        call    ceval
        lea     rdi,[mf2]
        lea     rsi,[mx2]
        call    ceval
        mov     r12d, MAXIT
.iter:
        ; h0 = x1-x0 ; h1 = x2-x1
        lea     rdi,[mh0]
        lea     rsi,[mx1]
        lea     rdx,[mx0]
        call    csub
        lea     rdi,[mh1]
        lea     rsi,[mx2]
        lea     rdx,[mx1]
        call    csub
        ; d0 = (f1-f0)/h0
        lea     rdi,[mt1]
        lea     rsi,[mf1]
        lea     rdx,[mf0]
        call    csub
        lea     rdi,[md0]
        lea     rsi,[mt1]
        lea     rdx,[mh0]
        call    cdiv
        ; d1 = (f2-f1)/h1
        lea     rdi,[mt1]
        lea     rsi,[mf2]
        lea     rdx,[mf1]
        call    csub
        lea     rdi,[md1]
        lea     rsi,[mt1]
        lea     rdx,[mh1]
        call    cdiv
        ; A = (d1-d0)/(h1+h0)
        lea     rdi,[mt1]
        lea     rsi,[md1]
        lea     rdx,[md0]
        call    csub
        lea     rdi,[mt2]
        lea     rsi,[mh1]
        lea     rdx,[mh0]
        call    cadd
        lea     rdi,[mA]
        lea     rsi,[mt1]
        lea     rdx,[mt2]
        call    cdiv
        ; B = A*h1 + d1
        lea     rdi,[mt1]
        lea     rsi,[mA]
        lea     rdx,[mh1]
        call    cmul
        lea     rdi,[mB]
        lea     rsi,[mt1]
        lea     rdx,[md1]
        call    cadd
        ; C = f2
        mov     rax,[mf2]
        mov     [mC],rax
        mov     rax,[mf2+8]
        mov     [mC+8],rax
        ; disc = sqrt(B*B - 4*A*C)
        lea     rdi,[mt1]
        lea     rsi,[mB]
        lea     rdx,[mB]
        call    cmul                ; B^2
        lea     rdi,[mt2]
        lea     rsi,[mA]
        lea     rdx,[mC]
        call    cmul                ; A*C
        fld     qword [mt2]         ; *4
        fmul    qword [four]
        fstp    qword [mt2]
        fld     qword [mt2+8]
        fmul    qword [four]
        fstp    qword [mt2+8]
        lea     rdi,[mt1]
        lea     rsi,[mt1]
        lea     rdx,[mt2]
        call    csub                ; B^2 - 4AC
        lea     rdi,[mdsc]
        lea     rsi,[mt1]
        call    csqrt
        ; bp = B+disc ; bm = B-disc
        lea     rdi,[mbp]
        lea     rsi,[mB]
        lea     rdx,[mdsc]
        call    cadd
        lea     rdi,[mbm]
        lea     rsi,[mB]
        lea     rdx,[mdsc]
        call    csub
        ; choose den = whichever of bp,bm has larger magnitude
        lea     rsi,[mbp]
        call    cmag2               ; st0=|bp|^2
        fstp    qword [cdiv_den]    ; (reuse scratch) save |bp|^2
        lea     rsi,[mbm]
        call    cmag2               ; st0=|bm|^2
        fld     qword [cdiv_den]    ; st0=|bp|^2, st1=|bm|^2
        fcomip  st0, st1            ; CF=1 if |bp|^2 < |bm|^2 ; pops |bp|^2
        fstp    st0                 ; drop |bm|^2
        jb      .use_bm
        mov     rax,[mbp]
        mov     [mden],rax
        mov     rax,[mbp+8]
        mov     [mden+8],rax
        jmp     .den_done
.use_bm:
        mov     rax,[mbm]
        mov     [mden],rax
        mov     rax,[mbm+8]
        mov     [mden+8],rax
.den_done:
        ; num = 2*C
        fld     qword [mC]
        fadd    st0, st0
        fstp    qword [mnum]
        fld     qword [mC+8]
        fadd    st0, st0
        fstp    qword [mnum+8]
        ; q = num/den
        lea     rdi,[mq]
        lea     rsi,[mnum]
        lea     rdx,[mden]
        call    cdiv
        ; x3 = x2 - q
        lea     rdi,[mx3]
        lea     rsi,[mx2]
        lea     rdx,[mq]
        call    csub
        ; f3 = f(x3)
        lea     rdi,[mf3]
        lea     rsi,[mx3]
        call    ceval
        ; delta = x3 - x2
        lea     rdi,[mdel]
        lea     rsi,[mx3]
        lea     rdx,[mx2]
        call    csub

        ; ---- convergence test ----
        xor     ebx, ebx            ; conv flag = 0
        ; |f3|^2 < ftol2 ?
        lea     rsi,[mf3]
        call    cmag2
        fld     qword [ftol2]
        fcomip  st0, st1            ; CF=1 if ftol2 < |f3|^2
        fstp    st0
        jb      .chk_delta
        mov     bl, 1
        jmp     .conv_done
.chk_delta:
        lea     rsi,[mdel]
        call    cmag2
        fld     qword [tol2]
        fcomip  st0, st1            ; CF=1 if tol2 < |delta|^2  (not converged)
        fstp    st0
        jb      .conv_done          ; not converged -> bl stays 0
        mov     bl, 1
.conv_done:
        ; ---- shift x0<-x1<-x2<-x3 and f's ----
        mov     rax,[mx1]
        mov     [mx0],rax
        mov     rax,[mx1+8]
        mov     [mx0+8],rax
        mov     rax,[mf1]
        mov     [mf0],rax
        mov     rax,[mf1+8]
        mov     [mf0+8],rax
        mov     rax,[mx2]
        mov     [mx1],rax
        mov     rax,[mx2+8]
        mov     [mx1+8],rax
        mov     rax,[mf2]
        mov     [mf1],rax
        mov     rax,[mf2+8]
        mov     [mf1+8],rax
        mov     rax,[mx3]
        mov     [mx2],rax
        mov     rax,[mx3+8]
        mov     [mx2+8],rax
        mov     rax,[mf3]
        mov     [mf2],rax
        mov     rax,[mf3+8]
        mov     [mf2+8],rax

        test    bl, bl
        jnz     .done
        dec     r12d
        jnz     .iter
.done:
        mov     rax,[mx2]           ; real part of converged root
        mov     [mret],rax
        pop     r12
        pop     rbx
        ret

; ============================================================================
;  deflate: divide coef[0..deg] by (x - rootr); quotient -> coef; deg--
;  (uses only caller-saved registers, so the find-loop's r13 is safe)
; ============================================================================
deflate:
        mov     r8, [deg]
        fld     qword [coef + r8*8]
        fstp    qword [carry]       ; carry = coef[deg] = q[deg-1]
        mov     rax, r8
        dec     rax                 ; deg-1
        mov     rdx, [carry]
        mov     [qb + rax*8], rdx
        mov     rcx, rax            ; i = deg-1
.dl:
        test    rcx, rcx
        jz      .dd
        fld     qword [carry]
        fmul    qword [rootr]
        fadd    qword [coef + rcx*8]
        fstp    qword [carry]       ; carry = coef[i] + r*carry
        mov     rax, rcx
        dec     rax
        mov     rdx, [carry]
        mov     [qb + rax*8], rdx   ; q[i-1] = carry
        dec     rcx
        jmp     .dl
.dd:
        dec     qword [deg]         ; degree drops by one
        mov     rcx, [deg]          ; new degree
.cp:
        mov     rdx, [qb + rcx*8]
        mov     [coef + rcx*8], rdx
        dec     rcx
        jns     .cp                 ; copy indices new_deg..0
        ret

; ============================================================================
;  main(argc=edi, argv=rsi)
; ============================================================================
main:
        push    rbp
        mov     rbp, rsp
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 8              ; 6 pushes -> realign to 16

        ; ---- parse N from argv[1] (default 2) ----
        mov     r14, rsi            ; argv
        mov     r15d, 2             ; default N
        cmp     edi, 2
        jl      .haveN
        mov     rdi, [r14 + 8]      ; argv[1]
        xor     eax, eax
        xor     ecx, ecx            ; accumulator
.atoi:
        movzx   edx, byte [rdi]
        test    dl, dl
        jz      .atoi_done
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
        jz      .haveN              ; ignore garbage / zero -> default
        mov     r15d, ecx
.haveN:
        ; clamp 2N <= MAXD
        mov     eax, r15d
        add     eax, eax            ; d = 2N
        cmp     eax, MAXD
        jle     .dok
        mov     eax, MAXD
        shr     eax, 1
        mov     r15d, eax           ; N = MAXD/2
        add     eax, eax
.dok:
        mov     [Dorig], eax        ; d
        movsxd  rax, eax
        mov     [deg], rax

        ; ---- zero the three recurrence buffers ----
        lea     rdi, [buf0]
        mov     ecx, (MAXD+1)*3     ; buf0,buf1,buf2 are contiguous
        xor     eax, eax
        rep     stosq

        ; ---- seed T0 (buf0) and T1 (buf1) ----
        fld1
        fstp    qword [buf0]        ; T0 = 1
        fld1
        fstp    qword [buf1 + 8]    ; T1 = x

        ; pointers: r12=prev(T_{k-2}), r13=cur(T_{k-1}), r14=next
        lea     r12, [buf0]
        lea     r13, [buf1]
        lea     r14, [buf2]

        movsxd  r15, dword [Dorig]  ; d  (loop target)
        mov     ebx, 2              ; k = 2
.bk:
        cmp     ebx, r15d
        jg      .bdone
        ; next[0] = -prev[0]
        fld     qword [r12]
        fchs
        fstp    qword [r14]
        ; next[i] = 2*cur[i-1] - prev[i] ,  i = 1..k
        mov     eax, 1
.ik:
        cmp     eax, ebx
        jg      .ikd
        fld     qword [r13 + rax*8 - 8]   ; cur[i-1]
        fadd    st0, st0                  ; 2*cur[i-1]
        fsub    qword [r12 + rax*8]       ; - prev[i]
        fstp    qword [r14 + rax*8]
        inc     eax
        jmp     .ik
.ikd:
        ; rotate prev<-cur, cur<-next, next<-old prev
        mov     rax, r12
        mov     r12, r13
        mov     r13, r14
        mov     r14, rax
        inc     ebx
        jmp     .bk
.bdone:
        ; final T_d is in cur (r13); copy to coef[0..d]
        movsxd  rcx, dword [Dorig]
.cpc:
        mov     rax, [r13 + rcx*8]
        mov     [coef + rcx*8], rax
        dec     rcx
        jns     .cpc

        ; ---- banner ----
        lea     rdi, [banner]
        mov     esi, [Dorig]
        mov     edx, [Dorig]
        mov     ecx, [Dorig]
        xor     eax, eax
        call    printf

        ; ---- find all d roots ----
        xor     r13d, r13d          ; root count
.findloop:
        mov     eax, [deg]
        cmp     eax, 1
        jg      .use_muller
        ; deg == 1: root = -coef[0]/coef[1]
        fld     qword [coef]
        fchs
        fdiv    qword [coef + 8]
        fstp    qword [rootr]
        jmp     .store
.use_muller:
        call    muller
        mov     rax, [mret]
        mov     [rootr], rax
.store:
        mov     rax, [rootr]
        mov     [roots + r13*8], rax
        inc     r13d
        mov     eax, [deg]
        cmp     eax, 1
        jle     .findone
        call    deflate
        jmp     .findloop
.findone:

        ; ---- sort roots descending (bubble) so k=1 matches largest cos ----
        movsxd  r12, dword [Dorig]  ; n
.sort_o:
        dec     r12
        jle     .sorted
        xor     esi, esi            ; i
.sort_i:
        cmp     rsi, r12
        jge     .sort_o
        fld     qword [roots + rsi*8 + 8]   ; b = roots[i+1]
        fld     qword [roots + rsi*8]       ; a = roots[i]  (st0=a, st1=b)
        fcomip  st0, st1                    ; CF=1 if a<b ; pops a
        fstp    st0                         ; drop b
        jnc     .nosw                       ; a>=b: ok
        mov     rax, [roots + rsi*8]        ; swap
        mov     rdx, [roots + rsi*8 + 8]
        mov     [roots + rsi*8], rdx
        mov     [roots + rsi*8 + 8], rax
.nosw:
        inc     esi
        jmp     .sort_i
.sorted:

        ; ---- print table ----
        lea     rdi, [col_hd]
        xor     eax, eax
        call    printf

        mov     ebx, 1              ; k = 1..d
.ploop:
        cmp     ebx, [Dorig]
        jg      .pdone
        ; exact = cos((2k-1)*pi/(2d))
        fldpi
        mov     eax, ebx
        add     eax, eax
        dec     eax                 ; 2k-1
        mov     [inum], eax
        fild    dword [inum]
        fmulp   st1, st0            ; pi*(2k-1)
        mov     eax, [Dorig]
        add     eax, eax            ; 2d
        mov     [iden], eax
        fild    dword [iden]
        fdivp   st1, st0            ; angle
        fcos                        ; cos(angle)
        fstp    qword [exactv]
        ; err = computed - exact
        mov     eax, ebx
        dec     eax                 ; index k-1
        fld     qword [roots + rax*8]
        fsub    qword [exactv]
        fstp    qword [errv]
        ; printf(row_fmt, k, computed, exact, err)
        mov     eax, ebx
        dec     eax
        movsd   xmm0, [roots + rax*8]
        movsd   xmm1, [exactv]
        movsd   xmm2, [errv]
        mov     esi, ebx
        lea     rdi, [row_fmt]
        mov     al, 3
        call    printf
        inc     ebx
        jmp     .ploop
.pdone:
        lea     rdi, [done_ln]
        mov     esi, [Dorig]
        xor     eax, eax
        call    printf

        xor     eax, eax
        add     rsp, 8
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        pop     rbp
        ret
