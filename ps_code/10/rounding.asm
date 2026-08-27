;;; ============================================================================
;;; rounding.asm -- the x87 rounding modes, and the last bit of a division
;;; Practice session 10                      (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Part A rounds eight test values to integers under each of the four IEEE-754
;;;   rounding directions, so you can see the .5 ties resolve differently.
;;;   Part B divides 1/3 and 2/3 under the same four modes at 53-bit precision
;;;   and prints seventeen significant digits, so you can watch the LAST DIGIT
;;;   change.
;;;   (Verified: it runs and prints both parts.)
;;;
;;;   THE AUTHOR'S HEADER LAYS OUT THE CONTROL WORD PROPERLY. The short version:
;;;   the x87 has a 16-bit CONTROL WORD, a register that changes how every
;;;   subsequent instruction behaves, and two of its fields matter here:
;;;       RC (bits 11-10)   the rounding direction
;;;           00  to NEAREST, ties to EVEN      <- the default everywhere
;;;           01  DOWN, toward -infinity
;;;           10  UP, toward +infinity
;;;           11  toward ZERO (truncate)
;;;       PC (bits 9-8)     the working mantissa width: 24, 53 or 64 bits
;;;
;;;   "TIES TO EVEN" IS THE ONE PEOPLE GET WRONG. Under the default mode 0.5
;;;   rounds to 0 and 2.5 rounds to 2 -- NOT to 1 and 3. The rule breaks ties
;;;   towards the even neighbour, which is why it is sometimes called BANKER'S
;;;   ROUNDING. Always rounding halves up would bias a long sum upward; ties to
;;;   even does not. Part A's output makes this concrete, and it is worth reading
;;;   the eight lines carefully rather than skimming them.
;;;
;;;   NOTE ALSO how the negative values behave. Under RC=01 (down, toward
;;;   -infinity) -2.5 becomes -3, while under RC=11 (toward zero) it becomes -2.
;;;   "Down" and "truncate" are the same thing for positive numbers and opposite
;;;   for negative ones -- which is exactly the trap in every integer-division
;;;   language specification you will ever read.
;;;
;;;   PART B IS THE MORE IMPORTANT HALF. 1/3 has no exact binary representation,
;;;   so the answer must be rounded, and the rounding direction decides the final
;;;   bit. Printed to seventeen digits -- which is the number needed to
;;;   round-trip a double -- you can see the modes disagree. THAT is why
;;;   floating-point comparisons need a tolerance, and why code-0023.asm has an
;;;   `epsilon` and newton_raphson.asm in ps_code/9 has a `c_tol`.
;;;
;;;   THE INSTRUCTIONS THAT DO IT:
;;;       fstcw [mem]     STore Control Word  -- read the current settings
;;;       fldcw [mem]     LoaD Control Word   -- install new ones
;;;   There is no way to modify the control word in place; you must read it into
;;;   an integer register, edit the bits, and write it back. `set_round` does
;;;   exactly that, and its three-line bit-field edit is the idiom worth
;;;   memorising:
;;;       and ax, 0xF3FF     ; clear the field    (mask with zeros where it is)
;;;       shl cx, 10         ; move the new value into position
;;;       or  ax, cx         ; drop it in
;;;   CLEAR, SHIFT, OR. You met the same pattern in andrax.asm and orax.asm in
;;;   ps_code/2, described abstractly; here it is doing real work on a real
;;;   hardware register.
;;;
;;;   `frndint` rounds st0 to an integer VALUE (still a float) using whatever RC
;;;   currently says. It is the instruction C's `rint()` compiles to.
;;;
;;;   NOTE THAT THE ORIGINAL CONTROL WORD IS SAVED AND RESTORED, at the start and
;;;   end of main. That is politeness of the same kind as pushing a callee-saved
;;;   register: the control word is global state shared with the C library, and
;;;   leaving it in a strange mode would make printf itself misbehave.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/10/rounding.asm"
;;;
;;;   Read Part A's four blocks side by side -- the same eight inputs, four
;;;   different sets of answers. Then compare with Python, which uses ties-to-even
;;;   for round() and truncation for int():
;;;   python3 -c "
;;;   for v in (0.5,1.5,2.5,3.5,-2.5,2.3,2.7,-2.7):
;;;       print('%+5.1f  round=%+5.1f  int=%+5.1f' % (v, round(v), int(v)))"
;;;
;;;   And check Part B:
;;;   python3 -c "print('%.17g %.17g' % (1/3, 2/3))"
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/10/rounding.asm"
;;;
;;;   Watch the control word being edited, bit by bit:
;;;     break set_round
;;;     c
;;;     si                        fstcw
;;;     p/x (short)cw             the current control word
;;;     p/t (short)cw             ...in binary. Bits 11-10 are RC.
;;;     si si si si si            through the and/shl/or
;;;     p/t $ax                   the new value, with RC changed
;;;     si si                     store and fldcw -- now it is LIVE
;;;
;;;   Watch one rounding happen:
;;;     break rounding.asm:NN     NN on the `frndint` line
;;;     c
;;;     p $st0                    the value about to be rounded
;;;     p ((short)cw >> 10) & 3   which RC is in force
;;;     si
;;;     p $st0                    the rounded result
;;;     c                         next value, or next mode
;;;
;;;   And see the last bit change in Part B:
;;;     break rounding.asm:NN     NN on the `fstp qword [res13]` line
;;;     c
;;;     p $st0                    1/3 under RC=0
;;;     c c c                     the same division under the other three modes
;;;     x/1gx &res13              the raw bits -- and watch the low bit move
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE CONTROL WORD IS A FOURTH KIND OF STATE, and this file is the only place
;;;   in the course you meet it. Line them up:
;;;       registers        per-instruction, and the ABI says which survive a call
;;;       the call stack   per-activation: frames, locals, return addresses
;;;       memory (.data/.bss)  per-program, outliving every frame
;;;       the CONTROL WORD  a MODE that changes what other instructions MEAN
;;;   That last one is different in kind. Nothing in `frndint` says how it
;;;   rounds; the answer lives in a register you set earlier and may have
;;;   forgotten about. The same is true of the direction flag for string
;;;   instructions, and of SSE's own MXCSR register.
;;;
;;;   WHICH MAKES SAVING AND RESTORING IT AN ABI QUESTION, exactly like a
;;;   callee-saved register. The control word is shared with the C library, and
;;;   printf's own conversions round. Leave RC set to "toward zero" and printf
;;;   starts truncating where it should round. This file is careful:
;;;       fstcw [savecw]       ...at the top of main
;;;       fldcw [savecw]       ...at the very bottom
;;;   Prove it matters:
;;;       break printf
;;;       c
;;;       p/t (short)cw         the mode printf is running under
;;;   and note that Part A deliberately leaves an unusual mode installed while
;;;   calling printf -- which is fine for `%+5.1f` but would not be for
;;;   everything.
;;;
;;;   ON THE ORDINARY STACK, meanwhile, the discipline is the familiar one. rbx
;;;   and r12 hold the two loop counters and are pushed and popped because they
;;;   are CALLEE-SAVED -- which is precisely why they survive the printf inside
;;;   the loop. The author's comment says "3 pushes (rbp, rbx, r12) from a %16==8
;;;   entry -> rsp now 16-aligned", AND THAT IS EXACTLY RIGHT: main starts at
;;;   8 mod 16, three pushes take it to 0, and every `call` then delivers 8 mod
;;;   16 to the callee as the ABI promises. Unlike several other files in this
;;;   course, this author got the premise right. Verify it anyway:
;;;       break printf
;;;       c
;;;       p $rsp % 16           8
;;; ============================================================================

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
                                         ;   export `main` for the C library start-up
extern  printf
                                         ;   the only external function needed

; ----------------------------------------------------------------------------
section .rodata
                                         ;   READ-ONLY data: strings that are never written
hdr_a   db 10,"=== FRNDINT: round-to-integer under the four x87 rounding modes ===",10
                                         ;   a two-line header, only the last `db` terminated
        db    "    (watch how the .5 ties round, and how +/- values differ)",10,0
mode_hd db 10,"-- RC=%d : %s --",10,0
                                         ;   an int and a string -- so 0 vector registers
val_ln  db    "      rint( %+5.1f ) = %+5.1f",10,0
                                         ;   TWO doubles: the original and the rounded value

hdr_b   db 10,"=== Inexact arithmetic at PC=53 (double): the LAST BIT changes ===",10
                                         ;   a three-line explanation of Part B
        db    "    1.0/3.0 and 2.0/3.0 cannot be stored exactly in binary,",10
        db    "    so the chosen rounding direction decides the final digit.",10,0
div_ln  db    "  RC=%d %-26s 1/3 = %.17g   2/3 = %.17g",10,0
                                         ;   %.17g prints SEVENTEEN significant digits, which is what
                                         ;   it takes to round-trip a double exactly. Fewer and you
                                         ;   would not see the modes disagree.

; names indexed by RC value 0..3
n_near  db "round to nearest (even)",0
                                         ;   the four mode names, indexed by RC below
n_down  db "round down  (-inf)",0
n_up    db "round up    (+inf)",0
n_chop  db "round toward zero",0

section .data
                                         ;   initialised, writable data
align 8
                                         ;   pad to an 8-byte boundary
names   dq n_near, n_down, n_up, n_chop  ; lookup by RC (0..3)
                                         ;   A JUMP TABLE OF POINTERS, indexed by RC. `[names + rbx*8]`
                                         ;   picks one -- base + 8*index, with 8 because these are
                                         ;   64-bit addresses. The same array idiom as everywhere else
                                         ;   in the course, holding code-adjacent data this time.

; the values fed to FRNDINT
align 8
                                         ;   pad to an 8-byte boundary, the natural alignment of a double
tv      dq 0.5, 1.5, 2.5, 3.5, -2.5, 2.3, 2.7, -2.7
                                         ;   the eight test values. The .5 ties and the negatives are
                                         ;   the interesting ones -- see the header.
TVN     equ 8
                                         ;   ...and how many

one     dq 1.0
                                         ;   x87 cannot take an immediate, so even 1.0 has to live in
                                         ;   memory
two     dq 2.0
three   dq 3.0

section .bss
                                         ;   zero-filled at load time
align 8
cw      resw 1                           ; scratch control word
                                         ;   scratch for reading and writing the control word. It is
                                         ;   16 bits, hence `resw`.
savecw  resw 1                           ; original control word (restored at exit)
                                         ;   the caller's original control word, restored at exit --
                                         ;   politeness of the same kind as pushing a callee-saved
                                         ;   register. See the call-stack notes.
rtmp    resq 1                           ; scratch double
                                         ;   scratch for moving a double between the FPU and SSE
r13d_   resq 1                           ; (unused placeholder)
                                         ;   declared and never used
res13   resq 1
res23   resq 1

; ----------------------------------------------------------------------------
section .text
                                         ;   the executable-code section

; --- set_round: put RC = (edi & 3) into the live control word, keep PC etc ---
set_round:
                                         ;   void set_round(int rc) -- install rounding mode rc,
                                         ;   leaving every other field of the control word alone
        fstcw   [cw]
                                         ;   STore Control Word: read the current settings into memory.
                                         ;   There is no way to edit it in place.
        mov     ax, [cw]
                                         ;   ...and into an integer register, where the bits can be
                                         ;   manipulated
        and     ax, 0xF3FF               ; clear RC (bits 11..10)
                                         ;   CLEAR the field: 0xF3FF has zeros exactly at bits 11-10,
                                         ;   so ANDing wipes RC and keeps everything else
        mov     cx, di
                                         ;   the requested mode...
        and     cx, 3
                                         ;   ...masked to two bits, in case the caller passed rubbish
        shl     cx, 10
                                         ;   SHIFT it into position: bits 11-10
        or      ax, cx
                                         ;   OR it in. CLEAR, SHIFT, OR -- the universal recipe for
                                         ;   editing a bit-field without disturbing its neighbours.
        mov     [cw], ax
                                         ;   write the new word back to memory...
        fldcw   [cw]
                                         ;   ...and LoaD Control Word makes it LIVE. From this
                                         ;   instruction onward, every FPU operation rounds differently.
        ret
                                         ;   pop the return address into rip. No frame at all: a LEAF
                                         ;   function with no locals and no calls.

; --- set_prec_double: force PC = 10b (53-bit double precision) ---------------
set_prec_double:
                                         ;   void set_prec_double(void) -- force the working mantissa to
                                         ;   53 bits, so results round straight to double precision
                                         ;   rather than being computed at 64 and rounded later
        fstcw   [cw]
                                         ;   read the control word
        mov     ax, [cw]
        and     ax, 0xFCFF               ; clear PC (bits 9..8)
                                         ;   CLEAR the PC field: 0xFCFF has zeros at bits 9-8
        or      ax, 0x0200               ; PC = 10b  (double)
                                         ;   ...and set it to 10b = 53-bit double. Same clear-shift-or
                                         ;   idiom, with the shift already folded into the constant.
        mov     [cw], ax
        fldcw   [cw]
                                         ;   make it live
        ret

; ============================================================================
main:
                                         ;   int main(void)
        push    rbp
                                         ;   prologue: save the caller's frame pointer
        mov     rbp, rsp
        push    rbx                      ; mode index   (callee-saved -> survives printf)
                                         ;   rbx and r12 are CALLEE-SAVED, which is exactly why the two
                                         ;   loop counters survive the printf calls. Three pushes take
                                         ;   rsp from 8 mod 16 to 0 -- correct at a `call`, and the
                                         ;   author's comment says so accurately.
        push    r12                      ; value index
                                         ; 3 pushes (rbp,rbx,r12) from a %16==8 entry -> rsp now 16-aligned

        fstcw   [savecw]                 ; remember the caller's control word
                                         ;   remember the caller's control word, to restore at the end

; ---------- Part A : FRNDINT under each rounding mode ----------------------
        lea     rdi, [hdr_a]
                                         ;   Part A's header
        xor     eax, eax
                                         ;   0 vector registers
        call    printf

        xor     ebx, ebx                 ; rc = 0
                                         ;   rc = 0
.modeA:
                                         ;   one pass per rounding mode. `.modeA` is LOCAL to main.
        mov     edi, ebx
                                         ;   set_round's one argument
        call    set_round                ; install rounding mode rc=ebx
                                         ;   install this mode -- and it stays in force for everything
                                         ;   that follows, including the printf below

                                         ; print the mode header:  "-- RC=%d : %s --"
        lea     rdi, [mode_hd]
                                         ;   the mode header
        mov     esi, ebx
                                         ;   argument 2: the RC value, an int
        mov     rdx, [names + rbx*8]
                                         ;   argument 3: the mode NAME, fetched from the pointer table.
                                         ;   base + 8*index.
        xor     eax, eax
                                         ;   0 vector registers: both arguments are integers
        call    printf

        xor     r12d, r12d               ; value index
                                         ;   value index = 0
.valA:
                                         ;   one pass per test value
        fld     qword [tv + r12*8]       ; load test value
                                         ;   push the test value. base + 8*index, with 8 because these
                                         ;   are doubles.
        frndint                          ; round to integer per current RC
                                         ;   ROUND TO AN INTEGER VALUE (still a float), using whatever
                                         ;   RC currently says. Nothing in the instruction names the
                                         ;   mode -- that is the point of the file. This is what C's
                                         ;   rint() compiles to.
        fstp    qword [rtmp]             ; store rounded result
                                         ;   store and pop -- the FPU stack is empty again
        movsd   xmm1, [rtmp]             ; arg2 = rounded
                                         ;   printf argument 2 (second double): the rounded value
        movsd   xmm0, [tv + r12*8]       ; arg1 = original
                                         ;   argument 1 (first double): the original. Loaded SECOND
                                         ;   because xmm0 must end up holding it.
        lea     rdi, [val_ln]
                                         ;   the format string
        mov     al, 2                    ; 2 vector (double) args
                                         ;   TWO vector registers carry arguments. Note `mov al, 2`
                                         ;   rather than `mov eax, 2` -- only AL is consulted, and the
                                         ;   upper bits of rax happen not to matter here.
        call    printf

        inc     r12d
                                         ;   next value
        cmp     r12d, TVN
        jl      .valA

        inc     ebx
                                         ;   next mode
        cmp     ebx, 4
        jl      .modeA

; ---------- Part B : inexact division, last-bit rounding -------------------
        lea     rdi, [hdr_b]
                                         ;   Part B's header
        xor     eax, eax
        call    printf

        call    set_prec_double          ; round arithmetic straight to 53-bit double
                                         ;   force 53-bit working precision, so the divisions round
                                         ;   straight to double rather than to 64 bits and then again

        xor     ebx, ebx                 ; rc = 0
                                         ;   rc = 0
.modeB:
                                         ;   one pass per rounding mode
        mov     edi, ebx
        call    set_round                ; keeps PC=53, changes only RC
                                         ;   change only RC; PC stays at 53

        fld     qword [one]
                                         ;   push 1.0
        fdiv    qword [three]            ; 1.0/3.0 rounded per current RC, at 53 bits
                                         ;   st0 := 1.0/3.0, ROUNDED PER THE CURRENT RC. 1/3 has no
                                         ;   exact binary form, so the direction decides the last bit.
        fstp    qword [res13]
                                         ;   store and pop

        fld     qword [two]
                                         ;   ...and the same for 2/3
        fdiv    qword [three]            ; 2.0/3.0
        fstp    qword [res23]

        lea     rdi, [div_ln]
                                         ;   the results line
        mov     esi, ebx                 ; RC value
                                         ;   argument 2: the RC value
        mov     rdx, [names + rbx*8]     ; mode name
                                         ;   argument 3: the mode name, from the pointer table
        movsd   xmm0, [res13]
                                         ;   the two doubles...
        movsd   xmm1, [res23]
        mov     al, 2
                                         ;   ...so TWO vector registers
        call    printf

        inc     ebx
                                         ;   next mode
        cmp     ebx, 4
        jl      .modeB

        fldcw   [savecw]                 ; restore caller's control word
                                         ;   RESTORE the caller's control word. Global state shared
                                         ;   with the C library -- leaving it in a strange mode would
                                         ;   make printf itself misbehave.

        xor     eax, eax                 ; return 0
                                         ;   main's return value: 0 = success
        pop     r12
                                         ;   restore the callee-saved registers IN REVERSE ORDER to
                                         ;   the pushes
        pop     rbx
        pop     rbp
        ret
                                         ;   pop the return address into rip

