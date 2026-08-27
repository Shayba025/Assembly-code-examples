;;; ============================================================================
;;; scalar_sse.asm -- computing with the vector unit, one lane at a time
;;; Practice session 11                      (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Adds 1 to 41, takes the larger of 3 and 7, and finds the square root of 2 --
;;;   all on the SSE unit, and all in assembly.
;;;   (Verified: prints 42.000000, 7.000000, 1.414214.)
;;;
;;;   THE AUTHOR'S HEADER ABOVE IS EXCELLENT AND WORTH READING FIRST. The notes
;;;   added below explain the individual instructions and put this file in the
;;;   context of the rest of the course.
;;;
;;;   THE SUFFIX IS THE WHOLE VOCABULARY. Every SSE instruction ends in two
;;;   letters that tell you the width and the type:
;;;       ss   Scalar Single    lane 0 only, 32-bit float
;;;       sd   Scalar Double    lane 0 only, 64-bit double
;;;       ps   Packed Single    ALL lanes, 32-bit floats   (4 in xmm, 8 in ymm)
;;;       pd   Packed Double    ALL lanes, 64-bit doubles  (2 in xmm, 4 in ymm)
;;;   So `addss` adds one number and `addps` adds four, from the same register
;;;   file, in the same number of cycles. THIS FILE USES ONLY THE SCALAR FORMS,
;;;   so you can watch a single value move without the other lanes distracting
;;;   you; packed.asm in this folder is the same idea with all four lanes live.
;;;   Read the two in that order.
;;;
;;;   WHY THE UPPER LANES ARE ZERO AND STAY ZERO: `movss xmm0, [mem]` loads 32
;;;   bits and ZEROES the rest of the register, and `addss` leaves lanes 1-3
;;;   untouched. So `p $xmm0.v4_float` shows {41, 0, 0, 0} throughout. That is
;;;   worth seeing once, because it is the visual difference between scalar and
;;;   packed code.
;;;
;;;   `cvtss2sd` IS THE LINE MOST PEOPLE FORGET. printf's `%f` conversion reads a
;;;   DOUBLE, always -- there is no `%f` for a 32-bit float, because C's default
;;;   argument promotion widens every float to double before passing it. A C
;;;   compiler inserts that conversion invisibly. In assembly you must do it
;;;   yourself, and omitting it prints rubbish rather than crashing.
;;;
;;;   `[rel one_f]` IS RIP-RELATIVE ADDRESSING: "the address of one_f, as an
;;;   offset from the current instruction". It produces position-independent
;;;   code, which is the modern default. Likewise `call printf wrt ..plt` routes
;;;   the call through the Procedure Linkage Table, so the linker can resolve it
;;;   in a shared library at load time. Compare the lecture files, which use
;;;   absolute addresses and rely on `-no-pie`.
;;;
;;;   `section .rodata` is READ-ONLY data. Everything in this file is constants
;;;   and format strings, so nothing needs to be writable -- and marking it so
;;;   means the loader can map those pages read-only and share them between
;;;   processes. Compare `.data` (initialised and writable) and `.bss` (zeroed
;;;   and writable).
;;;
;;;   THE FOUR ROUTINES ARE DELIBERATELY TINY -- `addone_f` is two instructions,
;;;   one of which is `ret`. They exist as breakpoint targets, which is why
;;;   `dbg_scalar` is exported with `global`: it gives you a name to break on
;;;   that sits exactly one instruction before the interesting one.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/11/scalar_sse.asm"
;;;
;;;   Check the square root:
;;;   python3 -c "import math; print('%f' % math.sqrt(2))"
;;;
;;;   Note the printed sqrt(2) is 1.414214 and not 1.414214 to more places --
;;;   `%f` shows six decimals by default, and a 32-bit float only carries about
;;;   seven significant digits anyway. Change `dd` to `dq` and the `ss` suffixes
;;;   to `sd` throughout and you would have the double-precision version.
;;;
;;; DEBUG IT   -- the author's own session, adapted to this course's scripts
;;;   ./debug "ps_code/11/scalar_sse.asm"
;;;
;;;   THE session for this file:
;;;     break dbg_scalar          stops inside addone_f, just before the addss
;;;     c
;;;     p $xmm0.v4_float          {41, 0, 0, 0} -- ONLY LANE 0 IS LIVE
;;;     display $xmm0.v4_float    sticky: re-printed after every step
;;;     si                        execute the addss
;;;     p $xmm0.v4_float          {42, 0, 0, 0} -- and the other lanes never moved
;;;
;;;     break fmax2_f
;;;     c
;;;     p $xmm0.v4_float[0]       3
;;;     p $xmm1.v4_float[0]       7
;;;     si
;;;     p $xmm0.v4_float[0]       7 -- maxss, with no branch anywhere
;;;
;;;   Watch the conversion that everyone forgets:
;;;     break print_f
;;;     c
;;;     p $xmm0.v4_float[0]       42 -- as a 32-bit float
;;;     si si si                  through the cvtss2sd
;;;     p $xmm0.v2_double[0]      42 -- as a 64-bit double, which is what %f wants
;;;     p/x $xmm0.v2_int64[0]     the bit pattern has changed COMPLETELY
;;;
;;;   And break the convention on purpose:
;;;     break printf
;;;     c   c                     get to one of the value printfs
;;;     p $rax                    1 -- "one vector register carries an argument"
;;;     set $rax = 0              claim there are none
;;;     c
;;;   printf now prints garbage for the number. Nothing warned you.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE INTERESTING THING IS WHAT THE ABI SAYS ABOUT VECTOR REGISTERS, because
;;;   it is stricter than you might expect: ALL SIXTEEN of xmm0-xmm15 are
;;;   CALLER-SAVED. There is no such thing as a callee-saved vector register on
;;;   this platform. Watch it:
;;;       break printf
;;;       c
;;;       p $xmm0.v2_double[0]    your value, about to be printed
;;;       finish
;;;       p $xmm0.v2_double[0]    whatever printf left behind
;;;
;;;   That has a real consequence for how you structure floating-point code:
;;;   THERE IS NO REGISTER YOU CAN PARK A FLOAT IN ACROSS A CALL. With integers
;;;   you have rbx and r12-r15 to fall back on; with floats you have nothing, and
;;;   the only options are
;;;       * do not call anything in the middle of the computation (which is why
;;;         the vectorised loops in dotprod.asm and code-0024.asm contain no
;;;         calls at all), or
;;;       * spill to memory by hand -- and note you cannot even `push xmm0`,
;;;         because `push` does not take a vector register. It has to be
;;;         `sub rsp, 16` and `movaps [rsp], xmm0`.
;;;   Look at how this file arranges things: every value is computed, then
;;;   immediately printed, and nothing is expected to survive a call.
;;;
;;;   THE OTHER THING TO NOTICE is `and rsp, -16` in BOTH `main` and `print_f`.
;;;   It matters more in floating-point code than anywhere else, because the C
;;;   library's own routines use ALIGNED vector loads (`movaps`) on stack memory,
;;;   and those FAULT on a misaligned address rather than merely running slowly.
;;;   Check it:
;;;       break printf
;;;       c
;;;       p $rsp % 16             8, which is what the ABI promises
;;;   `print_f` builds a full frame purely so that it can align the stack and
;;;   then undo the alignment on the way out -- three instructions of overhead
;;;   for a function whose real work is one `call`.
;;; ============================================================================

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
                                        ;   export `main` for the C library start-up
            global dbg_scalar           ; breakpoint target (inside addone_f)
                                        ;   exported ONLY so gdb has a name to break on -- it marks
                                        ;   the instruction just before the interesting one
            extern printf
                                        ;   the only external function needed

            section .rodata
                                        ;   READ-ONLY data: constants and strings that never change,
                                        ;   so the loader can map these pages read-only. Compare
                                        ;   `.data` (writable) and `.bss` (zeroed and writable).
one_f:      dd 1.0
                                        ;   `dd` = define DOUBLEWORD: a 32-bit IEEE-754 float. The
                                        ;   `ss` instructions below all operate on this width.
c41:        dd 41.0
c3:         dd 3.0
c7:         dd 7.0
c2:         dd 2.0
hdr:        db "Scalar SSE/SSE2 (all computation in assembly):", 10, 0
                                        ;   the header line, terminated by a 0 as C requires
fmt:        db "  %-18s = %f", 10, 0
                                        ;   %-18s left-aligns a string in 18 columns; %f prints a
                                        ;   DOUBLE -- which is why cvtss2sd exists below
s_add:      db "addss  41.0 + 1.0", 0
s_max:      db "maxss  max(3,7)", 0
s_sqrt:     db "sqrtss sqrt(2.0)", 0
note:       db 10, "Each value was widened by cvtss2sd before printf's %%f.", 10, 0
                                        ;   %%%% prints a literal percent sign

            section .text
                                        ;   the executable-code section
; --- routines under study: input in xmm0 (and xmm1), result in xmm0 ---------
addone_f:
                                        ;   float addone_f(float x) -- argument and result both in
                                        ;   xmm0, exactly as the ABI specifies
dbg_scalar:                             ; <-- break here; xmm0 = 41.0 in lane 0
                                        ;   a second label at the SAME address, exported for gdb.
                                        ;   Labels cost nothing; they are just names for addresses.
            addss   xmm0, [rel one_f]   ; lane 0 += 1.0f   -> 42.0
                                        ;   Scalar Single ADD: lane 0 += 1.0f. LANES 1-3 ARE NOT
                                        ;   TOUCHED -- that is the whole meaning of the `ss` suffix.
                                        ;   `[rel one_f]` is RIP-relative: the address computed as an
                                        ;   offset from this instruction.
            ret
                                        ;   pop the return address into rip. The result is already in
                                        ;   xmm0, where the ABI wants it.
fmax2_f:    maxss   xmm0, xmm1          ; lane 0 = max(a, b)
                                        ;   float fmax2_f(float a, float b) -- a in xmm0, b in xmm1.
                                        ;   Scalar MAX of lane 0. BRANCHLESS: no cmp, no jump, no
                                        ;   mispredicted branch. That is one of the biggest practical
                                        ;   wins of the vector unit.
            ret
fsqrt_f:    sqrtss  xmm0, xmm0          ; lane 0 = sqrt(x)
                                        ;   Scalar SQuare RooT of lane 0, in place. A single
                                        ;   instruction -- no library call, no Newton iteration.
            ret

; print_f(rdi = label, xmm0 = float result) : "  label = value"
                                        ;   void print_f(const char *label, float value)
                                        ;   label in rdi, value in xmm0 -- integer and float
                                        ;   arguments are counted in SEPARATE sequences.
print_f:    push    rbp
                                        ;   prologue: save the caller's frame pointer
            mov     rbp, rsp
                                        ;   anchor the frame
            and     rsp, -16
                                        ;   round rsp DOWN to a multiple of 16. Essential before
                                        ;   calling printf: the C library uses ALIGNED vector loads
                                        ;   on its own stack memory, so a misaligned stack faults.
            cvtss2sd xmm0, xmm0         ; float -> double for %f
                                        ;   ConVerT Scalar Single to Scalar Double. %f reads a
                                        ;   DOUBLE, always -- C promotes every float argument to
                                        ;   double, and a C compiler inserts this conversion
                                        ;   invisibly. In assembly you must write it yourself.
            mov     rsi, rdi
                                        ;   printf argument 2: the label. Moved out of rdi FIRST,
                                        ;   because rdi is about to become argument 1.
            lea     rdi, [rel fmt]
                                        ;   printf argument 1: the format string, RIP-relatively
            mov     eax, 1              ; AL = 1 : one vector arg
                                        ;   THE VARIADIC RULE: AL = the number of VECTOR registers
                                        ;   carrying arguments. One double, in xmm0, so 1.
            call    printf wrt ..plt
                                        ;   `wrt ..plt` routes the call through the Procedure Linkage
                                        ;   Table, so the linker can bind it to a shared library at
                                        ;   load time. This is what position-independent code needs.
            mov     rsp, rbp
                                        ;   epilogue: restore rsp from the anchor, undoing the
                                        ;   alignment
            pop     rbp
                                        ;   restore the caller's frame pointer
            ret
                                        ;   pop the return address into rip

main:       push    rbp
                                        ;   int main(void). Prologue and alignment as above.
            mov     rbp, rsp
            and     rsp, -16

            lea     rdi, [rel hdr]
                                        ;   printf argument 1: the header string
            xor     eax, eax
                                        ;   0 vector registers: the header has no conversions
            call    printf wrt ..plt

            movss   xmm0, [rel c41]     ; 41.0
                                        ;   MOVe Scalar Single: load 32 bits into lane 0 AND ZERO
                                        ;   THE OTHER 96 BITS. That zeroing is why gdb shows
                                        ;   {41, 0, 0, 0} rather than leftover junk.
            call    addone_f            ; -> 42.0
                                        ;   the argument is already in xmm0, as the ABI requires
            lea     rdi, [rel s_add]
                                        ;   print_f's first argument: the label
            call    print_f
                                        ;   ...and its second is still in xmm0, untouched by the lea

            movss   xmm0, [rel c3]      ; a = 3
                                        ;   a = 3, in xmm0 -- the first float argument
            movss   xmm1, [rel c7]      ; b = 7
                                        ;   b = 7, in xmm1 -- the second
            call    fmax2_f             ; -> 7.0
                                        ;   -> 7.0, in xmm0
            lea     rdi, [rel s_max]
            call    print_f

            movss   xmm0, [rel c2]      ; 2.0
                                        ;   2.0
            call    fsqrt_f             ; -> 1.414214
                                        ;   -> 1.414214
            lea     rdi, [rel s_sqrt]
            call    print_f

            lea     rdi, [rel note]
                                        ;   the closing note
            xor     eax, eax
                                        ;   0 vector registers
            call    printf wrt ..plt

            xor     eax, eax
                                        ;   main's return value: 0 = success
            mov     rsp, rbp
                                        ;   epilogue: restore rsp, then the frame pointer
            pop     rbp
            ret
                                        ;   pop the return address into rip

section .note.GNU-stack noalloc noexec nowrite progbits
                                        ;   the "no executable stack" marker, with the full set of
                                        ;   attributes

