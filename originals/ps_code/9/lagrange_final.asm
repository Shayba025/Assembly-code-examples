; ===========================================================================
; lagrange_final.asm
; x86-64 + x87 FPU  —  Lagrange Polynomial Interpolation
;
; Data points: (0,1)  (1,3)  (2,2)  (3,5)  (4,2)
; Evaluates  P(x)  at  x = 2.5
;
; Build:
;   nasm -f elf64 lagrange_final.asm -o lagrange_final.o
;   gcc  -no-pie -m64 lagrange_final.o -o lagrange_final
; Run:
;   ./lagrange_final
; ===========================================================================

        global  main
        extern  printf

; ──────────────────────────────────────────────────────────────────────────────
; SECTION .data  — all initialised constants and format strings live here
; ──────────────────────────────────────────────────────────────────────────────
section .data

N       equ  5                       ; number of data points (compile-time)

; x-coordinates of the 5 data points
xs      dq   0.0, 1.0, 2.0, 3.0, 4.0

; y-coordinates (function values at each x)
ys      dq   1.0, 3.0, 2.0, 5.0, 2.0

; query point — we want P(2.5)
x_q_save dq  2.5                     ; permanent backup (never changed)
x_q      dq  2.5                     ; working copy (overwritten in verify step)

; floating-point constants used in arithmetic
c_one   dq   1.0
c_100   dq   100.0

; ── printf format strings ─────────────────────────────────────────────────────
fmt_title  db  10
           db  "╔══════════════════════════════════════════════════╗", 10
           db  "║   LAGRANGE POLYNOMIAL INTERPOLATION  (x87 FPU)  ║", 10
           db  "╚══════════════════════════════════════════════════╝", 10, 0

fmt_points db  "  Data points: (0,1) (1,3) (2,2) (3,5) (4,2)", 10
           db  "  Query x = %.1f", 10
           db  "──────────────────────────────────────────────────", 10, 0

fmt_step1  db  10
           db  "  ─── Step 1: Compute each basis polynomial L_i(x) ───", 10
           db  "  Formula: L_i(x) = prod_{j!=i} (x-x_j) / (x_i-x_j)", 10, 0

fmt_i_hdr  db  10, "  i=%d:", 10, 0

fmt_nd     db  "    numerator   = prod_{j!=i}(x - x_j)   = %12.6f", 10
           db  "    denominator = prod_{j!=i}(x_i - x_j) = %12.6f", 10, 0

fmt_li     db  "    L_%d(%.1f) = num/den = %12.9f", 10, 0

fmt_term   db  "    y_%d * L_%d = %.1f * (%9.6f) = %12.9f   [%6.2f%% of P]", 10, 0

fmt_step2  db  10
           db  "  ─── Step 2: Partition-of-Unity Check ───", 10
           db  "  Theory: sum of ALL L_i(x) = 1 for ANY x.", 10, 0

fmt_unity  db  "  Sum L_i(%.1f) = %.15f  (should be exactly 1.0)", 10, 0

fmt_step3  db  10, "  ─── Step 3: Final Result ───", 10, 0

fmt_res    db  "  P(%.1f) = sum of y_i * L_i = %.15f", 10, 0

fmt_step4  db  10
           db  "  ─── Step 4: Verification at Known Nodes ───", 10
           db  "  Lagrange polynomial is EXACT at each x_i.", 10, 0

fmt_ver    db  "  P(%3.1f) = %12.9f   y_%d = %.1f   |error| = %.2e", 10, 0

fmt_foot   db  "──────────────────────────────────────────────────", 10
           db  "  Polynomial degree = N-1 = %d", 10
           db  "  Exact at %d nodes (errors are floating-point epsilon).", 10
           db  "──────────────────────────────────────────────────", 10, 0

; ──────────────────────────────────────────────────────────────────────────────
; SECTION .bss  — uninitialised working variables (zeroed at program start)
; ──────────────────────────────────────────────────────────────────────────────
section .bss

num      resq  1     ; numerator product for current L_i
den      resq  1     ; denominator product for current L_i
Li_val   resq  1     ; L_i(x_q) = num / den
term     resq  1     ; y_i * L_i  (one contribution to P)
total    resq  1     ; running sum P(x_q) = sum of all terms
unity    resq  1     ; sum of all L_i values (should equal 1.0)
pct      resq  1     ; |term| / |total| * 100  (percentage contribution)
yi_tmp   resq  1     ; temporary copy of y_i for printf
ver_err  resq  1     ; |P(x_i) - y_i| for verification

; ──────────────────────────────────────────────────────────────────────────────
; Tell the linker this object does NOT need an executable stack
; (suppresses the linker warning you saw on screen)
; ──────────────────────────────────────────────────────────────────────────────
section .note.GNU-stack noalloc noexec nowrite progbits

; ──────────────────────────────────────────────────────────────────────────────
section .text
; ──────────────────────────────────────────────────────────────────────────────

; ===========================================================================
; SUBROUTINE: compute_P
;
; PURPOSE:
;   Evaluates the Lagrange interpolating polynomial P at the current value
;   stored in [x_q].  Stores the result in [total].
;   Also accumulates the sum of all L_i in [unity] (should = 1.0).
;
; CALLING CONVENTION:
;   No arguments.  No return value in registers.
;   Result is in memory: [total] = P(x_q),  [unity] = sum of L_i.
;
; REGISTERS USED (all saved and restored):
;   rbx = outer loop index i  (0 .. N-1)
;   r15 = inner loop index j  (0 .. N-1)
;   r14 = scratch address register
;   rax = used for effective address computation
;
; FPU STACK DISCIPLINE:
;   Stack is EMPTY on entry.
;   Stack is EMPTY on exit.
;   Every fld is matched by exactly one fstp or fdivp/fmulp/fsubp.
; ===========================================================================
compute_P:
        ; ── save registers we use (System V ABI: callee must preserve rbx, r12-r15) ──
        push    rbx
        push    r15
        push    r14

        ; ── initialise accumulators to 0.0 ───────────────────────────────
        fldz
        fstp    qword [total]     ; total = 0.0
        fldz
        fstp    qword [unity]     ; unity = 0.0

        xor     rbx, rbx          ; i = 0  (outer loop counter)

.cp_outer:                        ; for i = 0 to N-1:
        cmp     rbx, N
        jge     .cp_done

        ; ── reset num and den to 1.0 for this new i ──────────────────────
        ; WHY: each L_i starts as a product of (N-1) factors;
        ;      multiplying into 1.0 is the identity for multiplication.
        fld1
        fstp    qword [num]       ; num = 1.0
        fld1
        fstp    qword [den]       ; den = 1.0

        xor     r15, r15          ; j = 0  (inner loop counter)

.cp_inner:                        ; for j = 0 to N-1:
        cmp     r15, N
        jge     .cp_inner_done
        cmp     r15, rbx          ; skip j == i  (the formula excludes it)
        je      .cp_skip

        ; ── rax = &xs[j],  r14 = &xs[i] ─────────────────────────────────
        ; WHY use lea then [rax]: x87 memory operands cannot use
        ; scaled-index addressing like [xs+r15*8] directly in some forms.
        ; Loading the address into rax first is always safe.
        lea     rax, [xs + r15*8]
        lea     r14, [xs + rbx*8]

        ; ── num  *=  (x_q - xs[j]) ───────────────────────────────────────
        ; This is the numerator factor for position j
        fld     qword [x_q]       ; ST0 = x_q
        fsub    qword [rax]       ; ST0 = x_q - xs[j]
        fmul    qword [num]       ; ST0 = num * (x_q - xs[j])
        fstp    qword [num]       ; num = ST0,  pop → stack EMPTY

        ; ── den  *=  (xs[i] - xs[j]) ─────────────────────────────────────
        ; This is the denominator factor for position j
        fld     qword [r14]       ; ST0 = xs[i]
        fsub    qword [rax]       ; ST0 = xs[i] - xs[j]
        fmul    qword [den]       ; ST0 = den * (xs[i] - xs[j])
        fstp    qword [den]       ; den = ST0,  pop → stack EMPTY

.cp_skip:
        inc     r15
        jmp     .cp_inner

.cp_inner_done:
        ; ── L_i = num / den ──────────────────────────────────────────────
        fld     qword [num]       ; ST0 = num
        fdiv    qword [den]       ; ST0 = num / den  =  L_i(x_q)
        fstp    qword [Li_val]    ; Li_val = L_i,  pop → EMPTY

        ; ── unity  +=  L_i ───────────────────────────────────────────────
        fld     qword [unity]
        fadd    qword [Li_val]
        fstp    qword [unity]

        ; ── total  +=  y_i * L_i ─────────────────────────────────────────
        lea     rax, [ys + rbx*8]
        fld     qword [rax]       ; ST0 = y_i
        fmul    qword [Li_val]    ; ST0 = y_i * L_i
        fstp    qword [term]      ; term = y_i * L_i

        fld     qword [total]
        fadd    qword [term]
        fstp    qword [total]     ; total += term

        inc     rbx
        jmp     .cp_outer

.cp_done:
        ; ── restore saved registers ──────────────────────────────────────
        pop     r14
        pop     r15
        pop     rbx
        ret

; ===========================================================================
; main — orchestrates the output in four clearly labelled steps
; ===========================================================================
main:
        ; ── standard prologue ────────────────────────────────────────────
        push    rbp
        mov     rbp, rsp
        push    r12           ; outer loop index (callee-saved)
        push    r13           ; inner loop index (callee-saved)
        push    r14           ; address scratch  (callee-saved)
        ; After 3 pushes + original push rbp = 4 × 8 = 32 bytes below
        ; the 16-aligned entry rsp.  32 is divisible by 16 → already aligned.
        ; BUT: call pushes 8 more → rsp becomes 16k+8 inside printf → WRONG.
        ; Fix: subtract 8 now so that call makes it 16-aligned inside callee.
        sub     rsp, 8        ; alignment pad

        ; ── TITLE ────────────────────────────────────────────────────────
        mov     rdi, fmt_title
        xor     eax, eax      ; eax = 0: no floating-point args to printf here
        call    printf

        mov     rdi, fmt_points
        movsd   xmm0, [x_q]  ; pass x_q as the %.1f argument
        mov     eax, 1        ; 1 floating-point argument in xmm0
        call    printf

        ; ── STEP 1 header ────────────────────────────────────────────────
        mov     rdi, fmt_step1
        xor     eax, eax
        call    printf

        ; ── Initialise total and unity to 0.0 for the main display loop ──
        fldz
        fstp    qword [total]
        fldz
        fstp    qword [unity]

        ; ── OUTER LOOP: i = 0 .. N-1 ─────────────────────────────────────
        ; For each i we build L_i(x_q) and print the intermediate values.
        xor     r12, r12      ; r12 = i = 0

.outer:
        cmp     r12, N
        jge     .outer_done

        ; -- reset products --
        fld1
        fstp    qword [num]
        fld1
        fstp    qword [den]

        ; ── INNER LOOP: j = 0 .. N-1,  j ≠ i ────────────────────────────
        xor     r13, r13      ; r13 = j = 0

.inner:
        cmp     r13, N
        jge     .inner_done
        cmp     r13, r12      ; skip j == i
        je      .inner_next

        lea     rax, [xs + r13*8]   ; &xs[j]
        lea     r14, [xs + r12*8]   ; &xs[i]

        ; num *= (x_q - xs[j])
        fld     qword [x_q]
        fsub    qword [rax]
        fmul    qword [num]
        fstp    qword [num]

        ; den *= (xs[i] - xs[j])
        fld     qword [r14]
        fsub    qword [rax]
        fmul    qword [den]
        fstp    qword [den]

.inner_next:
        inc     r13
        jmp     .inner

.inner_done:
        ; ── HIGHLIGHT 1: print i header ──────────────────────────────────
        mov     rdi, fmt_i_hdr
        mov     rsi, r12      ; i as integer argument
        xor     eax, eax
        call    printf

        ; ── HIGHLIGHT 2: print numerator and denominator ─────────────────
        ; Students see the raw products BEFORE the division.
        ; This makes the formula concrete: L_i is literally num/den.
        mov     rdi, fmt_nd
        movsd   xmm0, [num]
        movsd   xmm1, [den]
        mov     eax, 2        ; 2 floating-point args
        call    printf

        ; -- L_i = num / den --
        fld     qword [num]
        fdiv    qword [den]
        fstp    qword [Li_val]

        ; ── HIGHLIGHT 3: print L_i value ─────────────────────────────────
        mov     rdi, fmt_li
        mov     rsi, r12      ; i  (for L_%d)
        movsd   xmm0, [x_q]  ; x_q  (for %.1f)
        movsd   xmm1, [Li_val]
        mov     eax, 2
        call    printf

        ; -- term = y_i * L_i --
        lea     rax, [ys + r12*8]
        fld     qword [rax]
        fst     qword [yi_tmp]   ; save y_i for printf (fst = store without pop)
        fmul    qword [Li_val]
        fstp    qword [term]

        ; -- accumulate --
        fld     qword [total]
        fadd    qword [term]
        fstp    qword [total]

        fld     qword [unity]
        fadd    qword [Li_val]
        fstp    qword [unity]

        ; ── HIGHLIGHT 4: percentage contribution of this term ────────────
        ; pct = |term| / |total| * 100
        ; Shows students which nodes contribute most to P(x).
        fld     qword [term]
        fabs
        fmul    qword [c_100]
        fld     qword [total]
        fabs
        fdivp                 ; ST0 = |term|*100 / |total|
        fstp    qword [pct]

        mov     rdi, fmt_term
        mov     rsi, r12      ; y_%d
        mov     rdx, r12      ; L_%d
        movsd   xmm0, [yi_tmp]
        movsd   xmm1, [Li_val]
        movsd   xmm2, [term]
        movsd   xmm3, [pct]
        mov     eax, 4        ; 4 floating-point args
        call    printf

        inc     r12
        jmp     .outer

.outer_done:

        ; ── STEP 2: partition-of-unity check ─────────────────────────────
        ; KEY PROPERTY: for any x,  sum_{i=0}^{N-1} L_i(x) = 1.
        ; This is because the Lagrange basis reproduces the constant
        ; polynomial f(x)=1 exactly.
        ; We verify it numerically — the result should be 1.000000000000000.
        mov     rdi, fmt_step2
        xor     eax, eax
        call    printf

        mov     rdi, fmt_unity
        movsd   xmm0, [x_q]
        movsd   xmm1, [unity]
        mov     eax, 2
        call    printf

        ; ── STEP 3: final result ─────────────────────────────────────────
        mov     rdi, fmt_step3
        xor     eax, eax
        call    printf

        mov     rdi, fmt_res
        movsd   xmm0, [x_q]
        movsd   xmm1, [total]
        mov     eax, 2
        call    printf

        ; ── STEP 4: verification — P(x_i) must equal y_i exactly ─────────
        ; The Lagrange polynomial passes through ALL data points by
        ; construction.  Numerically the error should be ~machine epsilon
        ; (~1e-16), not exactly 0.0, due to floating-point rounding.
        ; We use the helper subroutine compute_P which temporarily
        ; overwrites [x_q] then we restore it from [x_q_save].
        mov     rdi, fmt_step4
        xor     eax, eax
        call    printf

        xor     r12, r12      ; i = 0

.verify:
        cmp     r12, N
        jge     .verify_done

        ; overwrite x_q with xs[i] so compute_P evaluates at a known node
        lea     rax, [xs + r12*8]
        fld     qword [rax]
        fstp    qword [x_q]

        call    compute_P     ; [total] = P(xs[i])

        ; error = |P(xs[i]) - ys[i]|
        fld     qword [total]
        lea     rax, [ys + r12*8]
        fsub    qword [rax]
        fabs
        fstp    qword [ver_err]

        ; printf(fmt_ver, xs[i], total, i, ys[i], ver_err)
        mov     rdi, fmt_ver
        lea     rax, [xs + r12*8]
        movsd   xmm0, [rax]
        movsd   xmm1, [total]
        mov     rsi, r12
        lea     rax, [ys + r12*8]
        movsd   xmm2, [rax]
        movsd   xmm3, [ver_err]
        mov     eax, 4
        call    printf

        inc     r12
        jmp     .verify

.verify_done:
        ; ── restore original query point ─────────────────────────────────
        fld     qword [x_q_save]
        fstp    qword [x_q]

        ; ── FOOTER ───────────────────────────────────────────────────────
        mov     rdi, fmt_foot
        mov     esi, N-1      ; degree = N-1
        mov     edx, N        ; number of nodes
        xor     eax, eax
        call    printf

        ; ── epilogue ─────────────────────────────────────────────────────
        xor     eax, eax      ; return 0
        add     rsp, 8        ; remove alignment pad
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        ret
