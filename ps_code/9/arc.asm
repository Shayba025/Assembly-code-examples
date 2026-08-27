;;; ============================================================================
;;; arc.asm -- circle geometry on the x87 FPU, results printed through SSE
;;; Practice session 9                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   For a circle of radius 2.5 it computes the points at 0 and 60 degrees, the
;;;   straight-line CHORD between them, and the curved ARC along the circle, and
;;;   prints all of it. The original header above explains the mathematics.
;;;   (Verified: chord = 2.500000000000000, arc = 2.617993877991494.)
;;;
;;;   THE ANSWER IS A NICE CHECK ON YOUR OWN UNDERSTANDING. At exactly 60
;;;   degrees the chord equals the radius -- the triangle formed by the centre
;;;   and the two points is equilateral. And the arc is R * theta = 2.5 * pi/3 =
;;;   2.6179938779914944, which is longer, as an arc always must be.
;;;
;;;   *** THE REALLY INSTRUCTIVE THING ABOUT THIS FILE IS THAT IT USES TWO
;;;   DIFFERENT FLOATING-POINT UNITS, ONE FOR EACH JOB. ***
;;;
;;;     x87 (fld, fmul, fsin, fcos, fsqrt) does the ARITHMETIC. It is the older
;;;         unit, it is a stack machine, and it has transcendental functions --
;;;         `fsin`, `fcos`, `fpatan`, `f2xm1` -- built into the silicon. SSE has
;;;         no sine instruction at all.
;;;
;;;     SSE (movsd, xmm0-xmm7) does the ARGUMENT PASSING. The System V ABI says
;;;         `double` arguments travel in xmm0, xmm1, ... and that rax holds HOW
;;;         MANY of them there are. printf reads them from there and nowhere else.
;;;
;;;   So the shape of the program is: compute everything in x87, spill each
;;;   result to memory with `fstp`, then reload it into an xmm register with
;;;   `movsd` when it is time to print. Memory is the bridge between the two
;;;   worlds, and there is no instruction that moves a value from st0 to xmm0
;;;   directly -- it always goes via RAM.
;;;
;;;   COMPARE code-0023.asm IN "lectures code ", which solves a quadratic in x87
;;;   and prints with `%Lg`. Because it prints LONG doubles it has to push them
;;;   onto the CALL stack by hand (`sub rsp, 16*2` and two `fstp tword [rsp]`).
;;;   This file prints ordinary `double`s, so the ABI lets them go in registers
;;;   and the whole business disappears. Two files, two conventions, and the
;;;   difference is entirely the type.
;;;
;;;   THE VARIADIC COUNT IS DOING REAL WORK HERE, unlike anywhere else in the
;;;   course. Watch it change: `mov eax, 1` before the header (one double),
;;;   `mov eax, 4` before the coordinates (four), `mov eax, 2` before the results
;;;   (two). Every other file in this course sets it to 0 because it passes no
;;;   floats at all. Get it wrong here and printf reads xmm registers that hold
;;;   nothing, or ignores ones that do.
;;;
;;;   THE x87 INSTRUCTIONS USED, beyond the ones in code-0023.asm:
;;;       fldpi         push the constant pi
;;;       fldz          push 0.0
;;;       fsin / fcos   sine / cosine of st0, IN PLACE (argument in RADIANS)
;;;       fsqrt         square root of st0, in place
;;;       fst  <mem>    store st0 to memory and KEEP it on the stack
;;;       fstp <mem>    store st0 to memory and POP it
;;;   The `fst` versus `fstp` distinction matters on line 81: theta is stored but
;;;   left on the stack so the very next instruction can multiply it by R without
;;;   reloading. One instruction saved, and the sort of thing that only reads
;;;   clearly if you are tracking the stack.
;;;
;;;   NOTE HOW CAREFULLY THE STACK IS BALANCED. The author's comments say
;;;   `EMPTY` after every `fstp`, and they are correct -- the FPU stack returns
;;;   to zero depth after each computation. That is not fussiness: there are only
;;;   eight slots and no way to grow them, so a leak of one per computation would
;;;   break the program on the eighth. Check it with `info float` in gdb.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/9/arc.asm"
;;;
;;;   Check the answers independently:
;;;   python3 -c "
;;;   import math
;;;   R=2.5; th=math.pi/3
;;;   x1,y1 = R*math.cos(0), R*math.sin(0)
;;;   x2,y2 = R*math.cos(th), R*math.sin(th)
;;;   print('chord', math.hypot(x2-x1, y2-y1))
;;;   print('arc  ', R*th)"
;;;
;;;   Change `radius dq 2.5` and re-run. Change `deg_60 dq 3.0` to 2.0 for 90
;;;   degrees, or 6.0 for 30 -- the constant is the DIVISOR of pi, not the angle.
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/9/arc.asm"
;;;
;;;   THE two commands for this file are `info float` and `p $xmm0`:
;;;     break arc.asm:NN          NN on the `fldpi` line
;;;     c
;;;     info float                an empty stack
;;;     si                        fldpi
;;;     p $st0                    3.14159265358979312
;;;     si                        fdiv qword [deg_60]
;;;     p $st0                    1.04719755119659774 = pi/3
;;;     si                        fst -- stores WITHOUT popping
;;;     info float                still one value on the stack
;;;     p (double)theta           and now it is in memory too
;;;
;;;   Watch the two worlds meet -- this is the point of the file:
;;;     break printf
;;;     c   c                     skip to the coordinates printf
;;;     info float                the x87 stack is EMPTY
;;;     p $xmm0.v2_double[0]      x1 = 2.5
;;;     p $xmm1.v2_double[0]      y1 = 0
;;;     p $xmm2.v2_double[0]      x2 = 1.25
;;;     p $xmm3.v2_double[0]      y2 = 2.165...
;;;     p $rax                    4 -- "four vector registers carry arguments"
;;;   Four doubles in xmm registers, nothing in the FPU, and rax saying how many.
;;;   That is the whole floating-point calling convention on one screen.
;;;
;;;   Break the variadic count on purpose, to see why it matters:
;;;     break arc.asm:NN          NN on the `mov eax, 4` line
;;;     c
;;;     si
;;;     set $rax = 1              claim only one double is being passed
;;;     c
;;;   printf now prints rubbish for three of the four numbers. Nothing warned you.
;;;
;;;   And confirm the FPU stack really is balanced:
;;;     break printf
;;;     c
;;;     info float                empty, every time
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THERE ARE THREE PLACES A VALUE CAN LIVE IN THIS PROGRAM, and the file uses
;;;   all three deliberately:
;;;
;;;     the x87 stack   eight 80-bit slots inside the CPU, addressed only
;;;                     relatively (st0, st1, ...). Fast, tiny, and it is where
;;;                     all the arithmetic happens.
;;;     .bss memory     theta, x1, y1, x2, y2, chord_len, arc_len. Unlimited,
;;;                     addressable by name, and the ONLY way to get a value from
;;;                     the x87 unit to the SSE unit.
;;;     xmm registers   where the ABI insists printf's arguments must be.
;;;
;;;   Trace one number through all three:
;;;       break arc.asm:NN          NN on the `fstp qword [chord_len]` line
;;;       c
;;;       p $st0                    the chord, in the FPU
;;;       si
;;;       info float                gone from the FPU
;;;       p (double)chord_len       ...and now in memory
;;;       break printf
;;;       c
;;;       p $xmm0.v2_double[0]      ...and now in a vector register
;;;   Three homes, two `mov`-like instructions, one value. THAT is what "spilling"
;;;   means, and it is the same idea as the integer spills in code-0013.asm --
;;;   only here the reason is not register pressure but the fact that two
;;;   different execution units cannot talk to each other except through RAM.
;;;
;;;   THE CALL STACK ITSELF IS ALMOST IDLE. `bt` shows two frames, `p $rsp` never
;;;   moves after the prologue, and there are no locals at all -- everything that
;;;   needs a name is in .bss. Note there is no `and rsp, -16` either. The
;;;   author's comment says "Stack is 16-byte aligned natively here", and the
;;;   arithmetic works out: `call main` left rsp at 8 mod 16 and `push rbp` made
;;;   it 0, so every `call printf` sees the 8 mod 16 the ABI promises. Verify it,
;;;   rather than trusting it:
;;;       break printf
;;;       c
;;;       p $rsp % 16               must be 8
;;;   That check matters more in a program that passes floats: printf will
;;;   actually execute aligned SSE instructions on its own stack memory here, so
;;;   a misaligned stack is a fault rather than merely a slowdown.
;;; ============================================================================

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
                                        ;   export `main` for the C library start-up

                                        ;   the only external function this program needs
; ---------------------------------------------------------------------------
section .data
; ---------------------------------------------------------------------------

radius      dq  2.5                     ; Radius of the circle (R)
deg_60      dq  3.0                     ; Divisor to get pi/3 (60 degrees)
                                        ;   `dq` emits an 8-byte IEEE-754 double. Change it and
                                        ;   re-run -- every result scales with it.

                                        ;   NOT the angle: this is the DIVISOR of pi. 3.0 gives
                                        ;   pi/3 = 60 degrees; use 2.0 for 90, 6.0 for 30.
; --- format strings (pure ASCII) ---
fmt_hdr     db  10
            db  "=========================================", 10
                                        ;   a multi-line C string built from several `db`s, only
                                        ;   the last of which is terminated. %.2f prints a double
                                        ;   to two decimals -- so this printf needs one xmm register.
            db  "  Parametric Circle Geometry (R = %.2f)", 10
            db  "=========================================", 10, 0

fmt_pts     db  "  Start Point (0 deg):  x = %8.5f, y = %8.5f", 10
            db  "  End Point   (60 deg): x = %8.5f, y = %8.5f", 10, 0
                                        ;   %8.5f: five decimals, right-aligned in a field of 8.
                                        ;   FOUR conversions, so four xmm registers.

fmt_res     db  "-----------------------------------------", 10
            db  "  Straight Chord Line = %.15f", 10
            db  "  True Curved Arc     = %.15f", 10, 0
                                        ;   %.15f: fifteen decimals, which is about the limit of a
                                        ;   double's precision. TWO conversions.

; ---------------------------------------------------------------------------
section .bss
; ---------------------------------------------------------------------------

theta       resq  1                     ; Angle in radians (pi / 3)
x1          resq  1                     ; Starting x
                                        ;   zero-filled at load time. These seven slots are the
                                        ;   BRIDGE between the x87 unit and the SSE registers --
                                        ;   there is no instruction that moves st0 to xmm0 directly.
y1          resq  1                     ; Starting y
x2          resq  1                     ; Ending x
y2          resq  1                     ; Ending y

chord_len   resq  1                     ; Linear distance between points
arc_len     resq  1                     ; Actual wrapped arc length

; ---------------------------------------------------------------------------
section .note.GNU-stack noalloc noexec nowrite progbits
                                        ;   the "no executable stack" marker, with the full set of
                                        ;   attributes. Most ps_code files omit it entirely.
; ---------------------------------------------------------------------------
section .text
; ---------------------------------------------------------------------------

main:
                                        ;   int main(void)
        push    rbp
                                        ;   prologue: save the caller's frame pointer. This also
                                        ;   takes rsp from 8 mod 16 to 0 mod 16, which is what makes
                                        ;   the printf calls legal without an `and rsp, -16`.
        mov     rbp, rsp
                                        ;   anchor the frame. No locals -- everything is in .bss.
                                        ; Stack is 16-byte aligned natively here

                                        ; ── print header ─────────────────────────────────────────────────────
        mov     rdi, fmt_hdr
                                        ;   printf argument 1: the format string, in an INTEGER
                                        ;   register as always
        movsd   xmm0, [radius]
                                        ;   MOVe Scalar Double: load one 8-byte double into the low
                                        ;   half of xmm0. The ABI says the first double argument
                                        ;   goes here.
        mov     eax, 1
                                        ;   THE VARIADIC RULE, doing real work for once: rax = the
                                        ;   number of VECTOR registers carrying arguments. ONE here.
                                        ;   (`mov eax, 1` also zeroes the upper half of rax.)
        call    printf

                                        ; ── Compute Theta = pi / 3 ───────────────────────────────────────────
        fldpi                           ; ST0 = pi
                                        ;   push the constant pi.  FPU stack:  pi
        fdiv    qword [deg_60]          ; ST0 = pi / 3
                                        ;   st0 := st0 / [deg_60] = pi/3.  stack:  theta
                                        ;   Note the memory operand: x87 arithmetic can take one.
        fst     qword [theta]           ; Store to memory, keep on stack top
                                        ;   `fst` stores WITHOUT popping -- theta is written to
                                        ;   memory AND left on the stack, so the next instruction
                                        ;   can use it without reloading. Contrast `fstp`.

                                        ; ── Compute True Arc Length = R * Theta ──────────────────────────────
        fmul    qword [radius]          ; ST0 = (pi / 3) * R
                                        ;   st0 := theta * R.  The arc length of a circular sector
                                        ;   is exactly R * theta, with theta in radians.
        fstp    qword [arc_len]         ; Store, pop -> EMPTY
                                        ;   store and POP.  stack: EMPTY

                                        ; ── Compute Point 1: x1 = R*cos(0), y1 = R*sin(0) ────────────────────
        fldz                            ; ST0 = 0.0
                                        ;   push 0.0.  stack:  0
        fcos                            ; ST0 = cos(0) = 1.0
                                        ;   cosine of st0, IN PLACE, argument in RADIANS.
                                        ;   stack:  cos(0) = 1.0
        fmul    qword [radius]          ; ST0 = 1.0 * R
                                        ;   st0 := 1.0 * R
        fstp    qword [x1]              ; EMPTY
                                        ;   store and pop.  stack: EMPTY

        fldz                            ; ST0 = 0.0
                                        ;   push 0.0 again
        fsin                            ; ST0 = sin(0) = 0.0
                                        ;   sine of st0, in place.  stack:  sin(0) = 0.0
        fmul    qword [radius]          ; ST0 = 0.0 * R
                                        ;   st0 := 0.0 * R
        fstp    qword [y1]              ; EMPTY
                                        ;   store and pop.  stack: EMPTY

                                        ; ── Compute Point 2: x2 = R*cos(theta), y2 = R*sin(theta) ────────────
        fld     qword [theta]           ; ST0 = theta
                                        ;   push theta, reloaded from memory
        fcos                            ; ST0 = cos(theta)
                                        ;   stack:  cos(theta) = 0.5
        fmul    qword [radius]          ; ST0 = R * cos(theta)
                                        ;   st0 := R * cos(theta) = 1.25
        fstp    qword [x2]              ; EMPTY
                                        ;   store and pop.  stack: EMPTY

        fld     qword [theta]           ; ST0 = theta
                                        ;   push theta again
        fsin                            ; ST0 = sin(theta)
                                        ;   stack:  sin(theta) = 0.866...
        fmul    qword [radius]          ; ST0 = R * sin(theta)
                                        ;   st0 := R * sin(theta) = 2.165...
        fstp    qword [y2]              ; EMPTY
                                        ;   store and pop.  stack: EMPTY

                                        ; ── Compute Chord Length = sqrt( (x2-x1)^2 + (y2-y1)^2 ) ─────────────
                                        ; Step A: (x2 - x1)^2
        fld     qword [x2]
                                        ;   push x2.  stack:  x2
        fsub    qword [x1]              ; ST0 = x2 - x1
                                        ;   st0 := st0 - [x1].  stack:  x2 - x1
        fmul    st0, st0                ; ST0 = (x2 - x1)^2
                                        ;   st0 := st0 * st0 -- squaring by multiplying by itself,
                                        ;   with no second value needed

                                        ; Step B: (y2 - y1)^2
        fld     qword [y2]
                                        ;   push y2.  stack:  (x2-x1)^2   y2
        fsub    qword [y1]              ; ST0 = y2 - y1
                                        ;   st0 := y2 - y1
        fmul    st0, st0                ; ST0 = (y2 - y1)^2, ST1 = (x2 - x1)^2
                                        ;   st0 := (y2-y1)^2.  stack:  (x2-x1)^2   (y2-y1)^2

                                        ; Step C: Add them and square root
        faddp                           ; ST0 = (x2-x1)^2 + (y2-y1)^2
                                        ;   st1 := st1 + st0, then POP -- two slots become one.
                                        ;   stack:  the sum of the squares
        fsqrt                           ; ST0 = sqrt(...)
                                        ;   square root of st0, in place. Pythagoras, finished.
        fstp    qword [chord_len]       ; EMPTY
                                        ;   store and pop.  stack: EMPTY

                                        ; ── Print Coordinates ────────────────────────────────────────────────
        mov     rdi, fmt_pts
                                        ;   printf argument 1: the format string
        movsd   xmm0, [x1]
                                        ;   the four doubles go in xmm0..xmm3, IN ORDER -- loaded
                                        ;   from the .bss slots the x87 unit wrote them to
        movsd   xmm1, [y1]
        movsd   xmm2, [x2]
        movsd   xmm3, [y2]
        mov     eax, 4
                                        ;   FOUR vector registers carry arguments this time. The
                                        ;   count changes per call, and getting it wrong prints
                                        ;   rubbish -- try it in gdb.
        call    printf

                                        ; ── Print Final Geometric Results ────────────────────────────────────
        mov     rdi, fmt_res
                                        ;   printf argument 1
        movsd   xmm0, [chord_len]
                                        ;   the chord...
        movsd   xmm1, [arc_len]
                                        ;   ...and the arc
        mov     eax, 2
                                        ;   TWO vector registers this time
        call    printf

                                        ; ── Epilogue ─────────────────────────────────────────────────────────
        xor     eax, eax
                                        ;   main's return value: 0 = success. The 32-bit name zeroes
                                        ;   the whole of rax.
        pop     rbp
                                        ;   epilogue. No `mov rsp, rbp` is needed, because rsp was
                                        ;   never moved after the prologue.
        ret
