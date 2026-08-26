; ===========================================================================
; gauss_chebyshev_v2.asm
; x86-64 + x87 FPU
; Gaussian Quadrature with Chebyshev nodes
;
; Computes:  integral of sin(x) dx  from 0 to 1
; Exact answer: 1 - cos(1) = 0.45969769413186028
;
; MATHEMATICAL BACKGROUND:
; -------------------------
; The Chebyshev-Gauss quadrature rule is designed for integrals of the form:
;
;   integral_{-1}^{1}  f(x) / sqrt(1-x^2)  dx
;
; Using n nodes:  x_i = cos( (2i-1)*pi/(2n) )   i = 1..n
; With weights:   w_i = pi/n  for all i  (uniform!)
;
; To integrate a plain function g(t) on [a,b] we must:
;   1. Transform:  t_i = (b-a)/2 * x_i + (a+b)/2
;   2. Absorb the weight function sqrt(1-x_i^2) into g:
;      set f(x_i) = g(t_i) * sqrt(1 - x_i^2)
;   3. Apply the formula:
;      integral_a^b g(t) dt  ≈  (b-a)/2 * (pi/n) * sum_i  g(t_i)*sqrt(1-x_i^2)
;
; g(t) = sin(t),  [a,b] = [0,1],  n = 8
;
; KEY FIXES vs v1 (which had NASM parse errors and wrong formula):
;   - fildl (AT&T GAS syntax) replaced by fild dword (NASM syntax)
;   - Unicode box characters removed from strings (caused encoding errors)
;   - sqrt(1-x_i^2) factor added correctly (was missing in v1 -> wrong result)
;   - fsqrt used for square root (x87 built-in, no library needed)
;   - Stack alignment corrected: 3 pushes + no extra sub = correct alignment
;   - FPU stack strictly empty at all function boundaries
;
; Build:
;   nasm -f elf64 gauss_chebyshev_v2.asm -o gauss_chebyshev_v2.o
;   gcc  -no-pie -m64 gauss_chebyshev_v2.o -o gauss_chebyshev_v2
; Run:
;   ./gauss_chebyshev_v2
; ===========================================================================

        global  main
        extern  printf

; ---------------------------------------------------------------------------
section .data
; ---------------------------------------------------------------------------

a           dq  0.0                     ; lower integration limit
b           dq  1.0                     ; upper integration limit
N           equ 8                       ; number of Chebyshev nodes

c_half      dq  0.5
c_one       dq  1.0

; exact value: 1 - cos(1)
exact       dq  0.45969769413186028

; --- format strings (pure ASCII - no Unicode) ---
fmt_hdr     db  10
            db  "=========================================", 10
            db  "  Gauss-Chebyshev Quadrature  (n=%d)", 10
            db  "  Integral of sin(x) from 0 to 1", 10
            db  "=========================================", 10
            db  "  Formula: (b-a)/2 * (pi/n) * sum f(t_i)*sqrt(1-x_i^2)", 10
            db  "-----------------------------------------", 10, 0

fmt_node    db  "  i=%2d: x_i=%9.6f  sqrt(1-x^2)=%9.6f"
            db  "  t_i=%8.6f  f(t_i)*w=%10.7f", 10, 0

fmt_sep     db  "-----------------------------------------", 10, 0
fmt_res     db  "  Result = %.15f", 10, 0
fmt_exact   db  "  Exact  = %.15f", 10, 0
fmt_err     db  "  Error  = %.3e", 10, 0
fmt_foot    db  "  (Error decreases as n increases)", 10, 0

; ---------------------------------------------------------------------------
section .bss
; ---------------------------------------------------------------------------

; integer scratch for fild (NASM requires memory operand for fild)
i_int       resd  1         ; current i as 32-bit int
two_n_int   resd  1         ; 2*N as 32-bit int
n_int       resd  1         ; N as 32-bit int

; floating-point working variables
angle       resq  1         ; (2i-1)*pi/(2n)
node_x      resq  1         ; Chebyshev node x_i = cos(angle)
node_t      resq  1         ; transformed node t_i in [a,b]
w_factor    resq  1         ; sqrt(1 - x_i^2)  -- the correction weight
f_weighted  resq  1         ; sin(t_i) * sqrt(1 - x_i^2)
sum_fw      resq  1         ; running sum of f(t_i)*sqrt(1-x_i^2)
half_ba     resq  1         ; (b-a)/2
midpoint    resq  1         ; (a+b)/2
weight      resq  1         ; pi/n
result      resq  1         ; final answer
abserr      resq  1         ; |result - exact|

; ---------------------------------------------------------------------------
section .note.GNU-stack noalloc noexec nowrite progbits
; ---------------------------------------------------------------------------
section .text
; ---------------------------------------------------------------------------

; ===========================================================================
; main
; ===========================================================================
main:
        push    rbp
        mov     rbp, rsp
        push    r12             ; loop counter i   (callee-saved)
        push    r13             ; (reserved/pad)   (callee-saved)
        ; Stack state after 3 pushes (push rbp, push r12, push r13):
        ;   rsp = entry_rsp - 24
        ;   entry_rsp was 16-aligned, so rsp ≡ -24 ≡ 8 (mod 16)
        ;   call pushes 8 more -> inside callee: rsp ≡ 0 (mod 16) CORRECT
        ; No extra sub rsp needed.

        ; ── precompute half_ba = (b-a)/2 ────────────────────────────────────
        ; WHY: this factor appears in both the node transform and the final
        ;      scaling.  Computing it once avoids repeated subtraction.
        fld     qword [b]
        fsub    qword [a]           ; ST0 = b - a = 1.0
        fmul    qword [c_half]      ; ST0 = (b-a)/2 = 0.5
        fstp    qword [half_ba]     ; store, pop -> EMPTY

        ; ── precompute midpoint = (a+b)/2 ───────────────────────────────────
        fld     qword [a]
        fadd    qword [b]           ; ST0 = a + b = 1.0
        fmul    qword [c_half]      ; ST0 = (a+b)/2 = 0.5
        fstp    qword [midpoint]

        ; ── precompute weight = pi/n ─────────────────────────────────────────
        ; WHY: fild requires a MEMORY operand (not an immediate).
        ;      We store N to [n_int] then use fild dword [n_int].
        ;      fild converts the 32-bit integer to 80-bit extended float.
        mov     dword [n_int],    N
        mov     dword [two_n_int], 2*N
        fldpi                       ; ST0 = pi
        fild    dword [n_int]       ; ST0 = (float)N,  ST1 = pi
        fdivp                       ; ST0 = pi/N  (fdivp: ST1/ST0, pop)
        fstp    qword [weight]

        ; ── initialise sum to 0 ─────────────────────────────────────────────
        fldz
        fstp    qword [sum_fw]

        ; ── print header ─────────────────────────────────────────────────────
        mov     rdi, fmt_hdr
        mov     esi, N
        xor     eax, eax
        call    printf

        ; ── node loop: i = 1 .. N ────────────────────────────────────────────
        mov     r12d, 1             ; i = 1

.node_loop:
        cmp     r12d, N
        jg      .node_done

        ; ── Step A: compute angle = (2i-1) * pi / (2N) ──────────────────────
        ;
        ; In NASM x87, to load an integer as a float we use:
        ;   fild dword [memory]    (NOT fildl which is AT&T/GAS syntax)
        ;
        ; FPU stack trace for angle computation:
        ;   fild [i_int]   -> ST0 = (float)i
        ;   fadd st0,st0   -> ST0 = 2i
        ;   fsub [c_one]   -> ST0 = 2i - 1
        ;   fldpi          -> ST0 = pi,    ST1 = 2i-1
        ;   fmulp          -> ST0 = (2i-1)*pi       [ST1*=ST0, pop]
        ;   fild [two_n]   -> ST0 = 2N,   ST1 = (2i-1)*pi
        ;   fdivp          -> ST0 = (2i-1)*pi/(2N)  [ST1/=ST0, pop]
        ;   fstp [angle]   -> store, pop -> EMPTY
        ;
        mov     dword [i_int], r12d
        fild    dword [i_int]       ; ST0 = (float)i
        fadd    st0, st0            ; ST0 = 2i
        fsub    qword [c_one]       ; ST0 = 2i - 1
        fldpi                       ; ST0 = pi,       ST1 = 2i-1
        fmulp                       ; ST0 = (2i-1)*pi
        fild    dword [two_n_int]   ; ST0 = 2N,       ST1 = (2i-1)*pi
        fdivp                       ; ST0 = (2i-1)*pi/(2N)
        fstp    qword [angle]       ; EMPTY

        ; ── Step B: x_i = cos(angle) ─────────────────────────────────────────
        ; This is the i-th Chebyshev node on [-1, 1].
        fld     qword [angle]
        fcos                        ; ST0 = cos(angle) = x_i
        fstp    qword [node_x]

        ; ── Step C: sqrt_factor = sqrt(1 - x_i^2) ────────────────────────────
        ; WHY THIS FACTOR?
        ;   The Chebyshev-Gauss rule integrates f(x)/sqrt(1-x^2) exactly.
        ;   For a plain integral of g(x), we set f(x) = g(x)*sqrt(1-x^2).
        ;   This cancels the 1/sqrt(1-x^2) weight, giving us integral of g.
        ;
        ; FPU computation:
        ;   fld  [c_one]  -> ST0 = 1
        ;   fld  [node_x] -> ST0 = x_i,  ST1 = 1
        ;   fmul st0,st0  -> ST0 = x_i^2
        ;   fsubp         -> ST0 = 1 - x_i^2  [ST1-=ST0, pop]
        ;   fsqrt         -> ST0 = sqrt(1 - x_i^2)
        fld     qword [c_one]       ; ST0 = 1
        fld     qword [node_x]      ; ST0 = x_i,    ST1 = 1
        fmul    st0, st0            ; ST0 = x_i^2
        fsubp                       ; ST0 = 1 - x_i^2
        fsqrt                       ; ST0 = sqrt(1 - x_i^2)
        fstp    qword [w_factor]    ; EMPTY

        ; ── Step D: t_i = (b-a)/2 * x_i + (a+b)/2 ───────────────────────────
        ; Transform the node from [-1,1] to [a,b] = [0,1]
        fld     qword [node_x]
        fmul    qword [half_ba]     ; ST0 = 0.5 * x_i
        fadd    qword [midpoint]    ; ST0 = 0.5*x_i + 0.5 = t_i
        fstp    qword [node_t]

        ; ── Step E: f_weighted = sin(t_i) * sqrt(1 - x_i^2) ─────────────────
        fld     qword [node_t]
        fsin			            ; ST0 = sin(t_i)
        fmul    qword [w_factor]    ; ST0 = sin(t_i) * sqrt(1-x_i^2)
        fstp    qword [f_weighted]

        ; ── Step F: sum_fw += f_weighted ─────────────────────────────────────
        fld     qword [sum_fw]
        fadd    qword [f_weighted]
        fstp    qword [sum_fw]

        ; ── print this node ───────────────────────────────────────────────────
        mov     rdi, fmt_node
        mov     esi, r12d           ; i
        movsd   xmm0, [node_x]     ; x_i
        movsd   xmm1, [w_factor]   ; sqrt(1-x_i^2)
        movsd   xmm2, [node_t]     ; t_i
        movsd   xmm3, [f_weighted] ; sin(t_i)*sqrt(1-x_i^2)
        mov     eax, 4
        call    printf

        inc     r12d
        jmp     .node_loop

.node_done:
        ; ── Final result: integral ≈ (b-a)/2 * (pi/N) * sum_fw ──────────────
        ; The (pi/N) is [weight], and (b-a)/2 is [half_ba].
        fld     qword [sum_fw]
        fmul    qword [weight]      ; sum * (pi/N)
        fmul    qword [half_ba]     ; * (b-a)/2
        fstp    qword [result]

        ; ── error = |result - exact| ─────────────────────────────────────────
        fld     qword [result]
        fsub    qword [exact]
        fabs
        fstp    qword [abserr]

        ; ── print results ────────────────────────────────────────────────────
        mov     rdi, fmt_sep
        xor     eax, eax
        call    printf

        mov     rdi, fmt_res
        movsd   xmm0, [result]
        mov     eax, 1
        call    printf

        mov     rdi, fmt_exact
        movsd   xmm0, [exact]
        mov     eax, 1
        call    printf

        mov     rdi, fmt_err
        movsd   xmm0, [abserr]
        mov     eax, 1
        call    printf

        mov     rdi, fmt_foot
        xor     eax, eax
        call    printf

        ; ── epilogue ─────────────────────────────────────────────────────────
        xor     eax, eax
        pop     r13
        pop     r12
        pop     rbp
        ret
