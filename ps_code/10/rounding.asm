; ============================================================================
;  rounding.asm  --  Demonstration of the x87 FPU rounding modes (RC field)
;                    and a touch of the precision-control field (PC).
;
;  Build (Linux, x86-64):
;       nasm -f elf64 rounding.asm -o rounding.o
;       gcc  -no-pie  rounding.o   -o rounding
;       ./rounding
;
;  The x87 control word (16 bits) selects how results are rounded:
;
;        bit 15..12  reserved
;        bit 11..10  RC  - Rounding Control      <-- the star of this program
;        bit  9.. 8  PC  - Precision Control
;        bit  5.. 0  exception masks
;
;  RC encodes the four IEEE-754 rounding directions:
;        00b  round to NEAREST, ties to EVEN   (the default)
;        01b  round DOWN   (toward -infinity)
;        10b  round UP     (toward +infinity)
;        11b  round toward ZERO  (truncate / "chop")
;
;  PC encodes the working mantissa width:
;        00b = 24-bit (single), 10b = 53-bit (double), 11b = 64-bit (extended)
; ============================================================================

global  main
extern  printf

; ----------------------------------------------------------------------------
section .rodata
hdr_a   db 10,"=== FRNDINT: round-to-integer under the four x87 rounding modes ===",10
        db    "    (watch how the .5 ties round, and how +/- values differ)",10,0
mode_hd db 10,"-- RC=%d : %s --",10,0
val_ln  db    "      rint( %+5.1f ) = %+5.1f",10,0

hdr_b   db 10,"=== Inexact arithmetic at PC=53 (double): the LAST BIT changes ===",10
        db    "    1.0/3.0 and 2.0/3.0 cannot be stored exactly in binary,",10
        db    "    so the chosen rounding direction decides the final digit.",10,0
div_ln  db    "  RC=%d %-26s 1/3 = %.17g   2/3 = %.17g",10,0

; names indexed by RC value 0..3
n_near  db "round to nearest (even)",0
n_down  db "round down  (-inf)",0
n_up    db "round up    (+inf)",0
n_chop  db "round toward zero",0

section .data
align 8
names   dq n_near, n_down, n_up, n_chop      ; lookup by RC (0..3)

; the values fed to FRNDINT
align 8
tv      dq 0.5, 1.5, 2.5, 3.5, -2.5, 2.3, 2.7, -2.7
TVN     equ 8

one     dq 1.0
two     dq 2.0
three   dq 3.0

section .bss
align 8
cw      resw 1          ; scratch control word
savecw  resw 1          ; original control word (restored at exit)
rtmp    resq 1          ; scratch double
r13d_   resq 1          ; (unused placeholder)
res13   resq 1
res23   resq 1

; ----------------------------------------------------------------------------
section .text

; --- set_round: put RC = (edi & 3) into the live control word, keep PC etc ---
set_round:
        fstcw   [cw]
        mov     ax, [cw]
        and     ax, 0xF3FF          ; clear RC (bits 11..10)
        mov     cx, di
        and     cx, 3
        shl     cx, 10
        or      ax, cx
        mov     [cw], ax
        fldcw   [cw]
        ret

; --- set_prec_double: force PC = 10b (53-bit double precision) ---------------
set_prec_double:
        fstcw   [cw]
        mov     ax, [cw]
        and     ax, 0xFCFF          ; clear PC (bits 9..8)
        or      ax, 0x0200          ; PC = 10b  (double)
        mov     [cw], ax
        fldcw   [cw]
        ret

; ============================================================================
main:
        push    rbp
        mov     rbp, rsp
        push    rbx                 ; mode index   (callee-saved -> survives printf)
        push    r12                 ; value index
        ; 3 pushes (rbp,rbx,r12) from a %16==8 entry -> rsp now 16-aligned

        fstcw   [savecw]            ; remember the caller's control word

; ---------- Part A : FRNDINT under each rounding mode ----------------------
        lea     rdi, [hdr_a]
        xor     eax, eax
        call    printf

        xor     ebx, ebx            ; rc = 0
.modeA:
        mov     edi, ebx
        call    set_round           ; install rounding mode rc=ebx

        ; print the mode header:  "-- RC=%d : %s --"
        lea     rdi, [mode_hd]
        mov     esi, ebx
        mov     rdx, [names + rbx*8]
        xor     eax, eax
        call    printf

        xor     r12d, r12d          ; value index
.valA:
        fld     qword [tv + r12*8]  ; load test value
        frndint                     ; round to integer per current RC
        fstp    qword [rtmp]        ; store rounded result
        movsd   xmm1, [rtmp]        ; arg2 = rounded
        movsd   xmm0, [tv + r12*8]  ; arg1 = original
        lea     rdi, [val_ln]
        mov     al, 2               ; 2 vector (double) args
        call    printf

        inc     r12d
        cmp     r12d, TVN
        jl      .valA

        inc     ebx
        cmp     ebx, 4
        jl      .modeA

; ---------- Part B : inexact division, last-bit rounding -------------------
        lea     rdi, [hdr_b]
        xor     eax, eax
        call    printf

        call    set_prec_double     ; round arithmetic straight to 53-bit double

        xor     ebx, ebx            ; rc = 0
.modeB:
        mov     edi, ebx
        call    set_round           ; keeps PC=53, changes only RC

        fld     qword [one]
        fdiv    qword [three]       ; 1.0/3.0 rounded per current RC, at 53 bits
        fstp    qword [res13]

        fld     qword [two]
        fdiv    qword [three]       ; 2.0/3.0
        fstp    qword [res23]

        lea     rdi, [div_ln]
        mov     esi, ebx                 ; RC value
        mov     rdx, [names + rbx*8]     ; mode name
        movsd   xmm0, [res13]
        movsd   xmm1, [res23]
        mov     al, 2
        call    printf

        inc     ebx
        cmp     ebx, 4
        jl      .modeB

        fldcw   [savecw]            ; restore caller's control word

        xor     eax, eax            ; return 0
        pop     r12
        pop     rbx
        pop     rbp
        ret
