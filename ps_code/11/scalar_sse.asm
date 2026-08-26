; scalar_sse.asm -- scalar SSE/SSE2 floating point, a COMPLETE assembly program.
; ===========================================================================
; The first program that computes with the vector unit. Everything is SCALAR
; (the "ss" suffix): each instruction touches only LANE 0 of an xmm register
; and ignores the other lanes.
;
; WHAT IT DEMONSTRATES
;   * scalar ops:   addss / maxss / sqrtss        (one lane, single-precision)
;   * RIP-relative data:  [rel one_f]
;   * the System V AMD64 FP ABI: float args in xmm0, xmm1, ...; result in xmm0
;   * calling variadic libc (printf) from assembly
;   * cvtss2sd: %f reads a DOUBLE, our values are FLOATs, so we widen ourselves
;     (the conversion a C compiler inserts invisibly).
;
; ---------------------------------------------------------------------------
; DEBUGGING -- watch lane 0 of xmm0 change as each scalar op runs
;
;   nasm -f elf64 -g -F dwarf scalar_sse.asm -o scalar_sse.o
;   gcc -g -o scalar_sse scalar_sse.o
;   gdb -q ./scalar_sse
;     (gdb) break dbg_scalar       # stops inside addone_f, just before addss
;     (gdb) run
;     (gdb) print $xmm0.v4_float   # {41, 0, 0, 0}  -- only lane 0 is live
;     (gdb) display $xmm0.v4_float # sticky: re-print after every step
;     (gdb) stepi                  # execute addss ; lane 0 becomes 42
;     (gdb) print $xmm0.v4_float   # {42, 0, 0, 0}
;     (gdb) break fmax2_f          # next routine: watch maxss pick the larger
;     (gdb) continue
;     (gdb) info registers xmm0 xmm1
;   Or non-interactively:  make inspect PROG=scalar_sse
; ---------------------------------------------------------------------------
; Build:  nasm -f elf64 scalar_sse.asm -o scalar_sse.o && gcc scalar_sse.o -o scalar_sse
; ===========================================================================

            global main
            global dbg_scalar             ; breakpoint target (inside addone_f)
            extern printf

            section .rodata
one_f:      dd 1.0
c41:        dd 41.0
c3:         dd 3.0
c7:         dd 7.0
c2:         dd 2.0
hdr:        db "Scalar SSE/SSE2 (all computation in assembly):", 10, 0
fmt:        db "  %-18s = %f", 10, 0
s_add:      db "addss  41.0 + 1.0", 0
s_max:      db "maxss  max(3,7)", 0
s_sqrt:     db "sqrtss sqrt(2.0)", 0
note:       db 10, "Each value was widened by cvtss2sd before printf's %%f.", 10, 0

            section .text
; --- routines under study: input in xmm0 (and xmm1), result in xmm0 ---------
addone_f:
dbg_scalar:                               ; <-- break here; xmm0 = 41.0 in lane 0
            addss   xmm0, [rel one_f]      ; lane 0 += 1.0f   -> 42.0
            ret
fmax2_f:    maxss   xmm0, xmm1            ; lane 0 = max(a, b)
            ret
fsqrt_f:    sqrtss  xmm0, xmm0           ; lane 0 = sqrt(x)
            ret

; print_f(rdi = label, xmm0 = float result) : "  label = value"
print_f:    push    rbp
            mov     rbp, rsp
            and     rsp, -16
            cvtss2sd xmm0, xmm0           ; float -> double for %f
            mov     rsi, rdi
            lea     rdi, [rel fmt]
            mov     eax, 1                ; AL = 1 : one vector arg
            call    printf wrt ..plt
            mov     rsp, rbp
            pop     rbp
            ret

main:       push    rbp
            mov     rbp, rsp
            and     rsp, -16

            lea     rdi, [rel hdr]
            xor     eax, eax
            call    printf wrt ..plt

            movss   xmm0, [rel c41]       ; 41.0
            call    addone_f              ; -> 42.0
            lea     rdi, [rel s_add]
            call    print_f

            movss   xmm0, [rel c3]        ; a = 3
            movss   xmm1, [rel c7]        ; b = 7
            call    fmax2_f               ; -> 7.0
            lea     rdi, [rel s_max]
            call    print_f

            movss   xmm0, [rel c2]        ; 2.0
            call    fsqrt_f               ; -> 1.414214
            lea     rdi, [rel s_sqrt]
            call    print_f

            lea     rdi, [rel note]
            xor     eax, eax
            call    printf wrt ..plt

            xor     eax, eax
            mov     rsp, rbp
            pop     rbp
            ret

section .note.GNU-stack noalloc noexec nowrite progbits
