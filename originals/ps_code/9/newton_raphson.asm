; ===========================================================================
; newton_raphson_v2.asm   —   CORRECTED FINAL VERSION
; x86-64 + x87 FPU
; Newton-Raphson root finding for  f(x) = x^3 - 2
; Root: x* = cbrt(2) ≈ 1.2599210498948732
;
; KEY FIXES vs v1:
;   1. FPU stack fully balanced at every point (no leftover values)
;   2. Newton step order corrected:  x_new = x - f(x)/f'(x)
;      uses fld / fdiv / fsub in the right sequence
;   3. Proper 16-byte stack alignment before every printf
;   4. Callee-saved registers r12 saved/restored correctly
;   5. All convergence comparisons use fucomip correctly
;   6. .note.GNU-stack section added (suppresses linker warning)
;
; Build:
;   nasm -f elf64 newton_raphson_v2.asm -o newton_raphson_v2.o
;   gcc  -no-pie -m64 newton_raphson_v2.o -o newton_raphson_v2
; Run:
;   ./newton_raphson_v2
; ===========================================================================

        global  main
        extern  printf

; ---------------------------------------------------------------------------
section .data
; ---------------------------------------------------------------------------

x_cur   dq   1.5                ; initial guess  x0 = 1.5
c_two   dq   2.0                ; the constant 2 in f(x)=x^3-2
c_three dq   3.0                ; the constant 3 in f'(x)=3x^2
c_tol   dq   1.0e-12            ; convergence tolerance

fmt_hdr db  "Newton-Raphson: f(x) = x^3 - 2,  x* = cbrt(2)", 10
        db  "---------------------------------------------------", 10, 0

fmt_row db  "  iter %2d:  x = %20.15f    f(x) = %20.15e", 10, 0

fmt_res db  "---------------------------------------------------", 10
        db  "Converged after %d iterations.", 10
        db  "Answer: x = %.15f", 10, 0

; ---------------------------------------------------------------------------
section .bss
; ---------------------------------------------------------------------------

fx      resq  1          ; f(x_cur)
dfx     resq  1          ; f'(x_cur)

; ---------------------------------------------------------------------------
; Mark stack as non-executable (suppresses gcc/ld warning)
; ---------------------------------------------------------------------------
section .note.GNU-stack noalloc noexec nowrite progbits

; ---------------------------------------------------------------------------
section .text
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; eval_f:
;   Computes f(x) = x^3 - 2  using the value in memory x_cur.
;   Stores result in memory fx.
;   FPU stack: EMPTY on entry, EMPTY on exit.
; ---------------------------------------------------------------------------
eval_f:
        fld     qword [x_cur]    ; ST0 = x
        fld     st0              ; ST0 = x,   ST1 = x      (copy x)
        fmul    st0, st0         ; ST0 = x^2, ST1 = x
        fmulp   st1, st0         ; ST0 = x * x^2 = x^3    (st1*=st0, pop)
        fsub    qword [c_two]    ; ST0 = x^3 - 2
        fstp    qword [fx]       ; [fx] = f(x),  pop → stack EMPTY
        ret

; ---------------------------------------------------------------------------
; eval_df:
;   Computes f'(x) = 3*x^2  using the value in memory x_cur.
;   Stores result in memory dfx.
;   FPU stack: EMPTY on entry, EMPTY on exit.
; ---------------------------------------------------------------------------
eval_df:
        fld     qword [x_cur]    ; ST0 = x
        fmul    st0, st0         ; ST0 = x^2
        fmul    qword [c_three]  ; ST0 = 3*x^2
        fstp    qword [dfx]      ; [dfx] = f'(x), pop → stack EMPTY
        ret

; ---------------------------------------------------------------------------
; do_newton_step:
;   Computes x_cur = x_cur - f(x_cur) / f'(x_cur)
;   Reads fx and dfx from memory (call eval_f and eval_df first).
;   FPU stack: EMPTY on entry, EMPTY on exit.
;
;   Stack trace:
;       fld  [fx]   → ST0 = f(x)
;       fld  [dfx]  → ST0 = f'(x), ST1 = f(x)
;       fdivp       → ST0 = f(x)/f'(x)          [fdivp: ST1 /= ST0, pop]
;                     WAIT — fdivp does ST1/ST0 then pops.
;                     We want f(x)/f'(x), so load f(x) first, then f'(x):
;                       fld fx   → ST0=f(x)
;                       fld dfx  → ST0=f'(x), ST1=f(x)
;                       fdivr    → ST0 = ST1/ST0 = f(x)/f'(x)  (no pop)
;                       fld x    → ST0=x, ST1=ratio
;                       fsubrp   → ST0 = ST1-ST0 = ratio - x  WRONG
;
;   Cleaner approach: compute step = f/f', then subtract from x:
;       fld  [dfx]   → ST0 = f'(x)
;       fld  [fx]    → ST0 = f(x),   ST1 = f'(x)
;       fdivp        → ST0 = f'(x)/f(x)   NO — fdivp: ST1/=ST0 pop
;                                           ST0 = f'(x)/f(x)  STILL WRONG
;
;   CORRECT sequence (see below):
;       fld  [fx]    → ST0 = f(x)
;       fdiv [dfx]   → ST0 = f(x)/f'(x)      (divide ST0 by memory)
;       fld  [x_cur] → ST0 = x, ST1 = f(x)/f'(x)
;       fsubrp       → ST0 = ST1 - ST0 = (f/f') - x   WRONG sign
;
;   SIMPLEST correct approach:
;       fld  [x_cur] → ST0 = x
;       fld  [fx]    → ST0 = f(x),    ST1 = x
;       fld  [dfx]   → ST0 = f'(x),   ST1 = f(x),  ST2 = x
;       fdivp        → ST0 = f(x)/f'(x),  ST1 = x   [ST1/=ST0, pop]
;       fsubp        → ST0 = x - f(x)/f'(x)           [ST1-=ST0, pop]
;       fstp [x_cur] → store new x, pop → EMPTY  ✓
; ---------------------------------------------------------------------------
do_newton_step:
        fld     qword [x_cur]    ; ST0 = x
        fld     qword [fx]       ; ST0 = f(x),    ST1 = x
        fld     qword [dfx]      ; ST0 = f'(x),   ST1 = f(x),   ST2 = x
        fdivp                    ; ST1 /= ST0, pop  → ST0 = f(x)/f'(x), ST1 = x
        fsubp                    ; ST1 -= ST0, pop  → ST0 = x - f(x)/f'(x)
        fstp    qword [x_cur]    ; store, pop → EMPTY
        ret

; ---------------------------------------------------------------------------
; main
; ---------------------------------------------------------------------------
main:
        push    rbp
        mov     rbp, rsp
        push    r12                      ; r12 = iteration counter (callee-saved)
        sub     rsp, 8                   ; align rsp to 16 bytes
                                         ; (8 from push rbp, 8 from push r12,
                                         ;  8 from sub = total 24 from rbp,
                                         ;  +8 ret addr = 32 → rsp is 16-aligned)

        ; --- print header ---
        mov     rdi,  fmt_hdr
        xor     eax,  eax                ; 0 xmm register args
        call    printf

        ; --- initialise iteration counter ---
        xor     r12d, r12d               ; r12 = 0

; ── Main Newton-Raphson loop ────────────────────────────────────────────────
.loop:
        ; -- evaluate f(x) and f'(x) --
        call    eval_f                   ; [fx]  ← f(x_cur)
        call    eval_df                  ; [dfx] ← f'(x_cur)

        ; -- print this iteration --
        ; printf(fmt_row, iter:int, x_cur:double, fx:double)
        mov     rdi,  fmt_row
        mov     esi,  r12d               ; arg2 = iteration (int in rsi)
        movsd   xmm0, [x_cur]           ; arg3 = x  (double)
        movsd   xmm1, [fx]              ; arg4 = f(x) (double)
        mov     eax,  2                  ; 2 xmm args used
        call    printf

        ; -- convergence test: |f(x)| < tolerance --
        fld     qword [fx]               ; ST0 = f(x)
        fabs                             ; ST0 = |f(x)|
        fld     qword [c_tol]            ; ST0 = tol,  ST1 = |f(x)|
        fucomip st0, st1                 ; compare tol with |f(x)|
        ;   fucomip sets:
        ;     ZF=1,CF=0  if ST0 == ST1   (tol == |f(x)|)
        ;     CF=0       if ST0 > ST1    (tol > |f(x)|)  → CONVERGED
        ;     CF=1       if ST0 < ST1    (tol < |f(x)|)  → not yet
        fstp    st0                      ; pop tol → stack EMPTY
        jnc     .converged               ; CF=0 → tol >= |f(x)| → done

        ; -- guard: stop after 20 iterations --
        inc     r12d
        cmp     r12d, 20
        jge     .converged

        ; -- Newton step: x = x - f(x)/f'(x) --
        call    do_newton_step

        jmp     .loop

; ── Done ────────────────────────────────────────────────────────────────────
.converged:
        mov     rdi,  fmt_res
        mov     esi,  r12d               ; number of iterations
        movsd   xmm0, [x_cur]           ; final x
        mov     eax,  1
        call    printf

        xor     eax, eax                 ; return 0
        add     rsp, 8
        pop     r12
        pop     rbp
        ret
