; ===========================================================================
; arc_geometry.asm
; x86-64 + x87 FPU
; Parametric Circle Geometry and Chord Length Calculation
;
; Computes: Coordinates at 0 and 60 degrees, the straight chord length,
;           and the exact curved arc length for a circle of radius R.
;
; MATHEMATICAL BACKGROUND:
; -------------------------
; For a circle of radius R and angle Theta (in radians):
;   Point 1 (0 rad):   x1 = R * cos(0),      y1 = R * sin(0)
;   Point 2 (pi/3 rad): x2 = R * cos(pi/3),   y2 = R * sin(pi/3)
;
;   Straight Chord Distance = sqrt( (x2 - x1)^2 + (y2 - y1)^2 )
;   True Curved Arc Length  = R * Theta
;
; Build:
;   nasm -f elf64 arc_geometry.asm -o arc_geometry.o
;   gcc  -no-pie -m64 arc_geometry.o -o arc_geometry
; Run:
;   ./arc_geometry
; ===========================================================================

        global  main
        extern  printf

; ---------------------------------------------------------------------------
section .data
; ---------------------------------------------------------------------------

radius      dq  2.5                     ; Radius of the circle (R)
deg_60      dq  3.0                     ; Divisor to get pi/3 (60 degrees)

; --- format strings (pure ASCII) ---
fmt_hdr     db  10
            db  "=========================================", 10
            db  "  Parametric Circle Geometry (R = %.2f)", 10
            db  "=========================================", 10, 0

fmt_pts     db  "  Start Point (0 deg):  x = %8.5f, y = %8.5f", 10
            db  "  End Point   (60 deg): x = %8.5f, y = %8.5f", 10, 0

fmt_res     db  "-----------------------------------------", 10
            db  "  Straight Chord Line = %.15f", 10
            db  "  True Curved Arc     = %.15f", 10, 0

; ---------------------------------------------------------------------------
section .bss
; ---------------------------------------------------------------------------

theta       resq  1         ; Angle in radians (pi / 3)
x1          resq  1         ; Starting x
y1          resq  1         ; Starting y
x2          resq  1         ; Ending x
y2          resq  1         ; Ending y

chord_len   resq  1         ; Linear distance between points
arc_len     resq  1         ; Actual wrapped arc length

; ---------------------------------------------------------------------------
section .note.GNU-stack noalloc noexec nowrite progbits
; ---------------------------------------------------------------------------
section .text
; ---------------------------------------------------------------------------

main:
        push    rbp
        mov     rbp, rsp
        ; Stack is 16-byte aligned natively here

        ; ── print header ─────────────────────────────────────────────────────
        mov     rdi, fmt_hdr
        movsd   xmm0, [radius]
        mov     eax, 1
        call    printf

        ; ── Compute Theta = pi / 3 ───────────────────────────────────────────
        fldpi                       ; ST0 = pi
        fdiv    qword [deg_60]      ; ST0 = pi / 3
        fst     qword [theta]       ; Store to memory, keep on stack top

        ; ── Compute True Arc Length = R * Theta ──────────────────────────────
        fmul    qword [radius]      ; ST0 = (pi / 3) * R
        fstp    qword [arc_len]     ; Store, pop -> EMPTY

        ; ── Compute Point 1: x1 = R*cos(0), y1 = R*sin(0) ────────────────────
        fldz                        ; ST0 = 0.0
        fcos                        ; ST0 = cos(0) = 1.0
        fmul    qword [radius]      ; ST0 = 1.0 * R
        fstp    qword [x1]          ; EMPTY

        fldz                        ; ST0 = 0.0
        fsin                        ; ST0 = sin(0) = 0.0
        fmul    qword [radius]      ; ST0 = 0.0 * R
        fstp    qword [y1]          ; EMPTY

        ; ── Compute Point 2: x2 = R*cos(theta), y2 = R*sin(theta) ────────────
        fld     qword [theta]       ; ST0 = theta
        fcos                        ; ST0 = cos(theta)
        fmul    qword [radius]      ; ST0 = R * cos(theta)
        fstp    qword [x2]          ; EMPTY

        fld     qword [theta]       ; ST0 = theta
        fsin                        ; ST0 = sin(theta)
        fmul    qword [radius]      ; ST0 = R * sin(theta)
        fstp    qword [y2]          ; EMPTY

        ; ── Compute Chord Length = sqrt( (x2-x1)^2 + (y2-y1)^2 ) ─────────────
        ; Step A: (x2 - x1)^2
        fld     qword [x2]
        fsub    qword [x1]          ; ST0 = x2 - x1
        fmul    st0, st0            ; ST0 = (x2 - x1)^2

        ; Step B: (y2 - y1)^2
        fld     qword [y2]
        fsub    qword [y1]          ; ST0 = y2 - y1
        fmul    st0, st0            ; ST0 = (y2 - y1)^2, ST1 = (x2 - x1)^2

        ; Step C: Add them and square root
        faddp                       ; ST0 = (x2-x1)^2 + (y2-y1)^2
        fsqrt                       ; ST0 = sqrt(...)
        fstp    qword [chord_len]   ; EMPTY

        ; ── Print Coordinates ────────────────────────────────────────────────
        mov     rdi, fmt_pts
        movsd   xmm0, [x1]
        movsd   xmm1, [y1]
        movsd   xmm2, [x2]
        movsd   xmm3, [y2]
        mov     eax, 4
        call    printf

        ; ── Print Final Geometric Results ────────────────────────────────────
        mov     rdi, fmt_res
        movsd   xmm0, [chord_len]
        movsd   xmm1, [arc_len]
        mov     eax, 2
        call    printf

        ; ── Epilogue ─────────────────────────────────────────────────────────
        xor     eax, eax
        pop     rbp
        ret