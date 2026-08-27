;;; ============================================================================
;;; cheb_root_round.asm -- one-ULP differences, made unmistakable
;;; Practice session 10                      (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Computes an irrational number twice over -- sqrt(1/2), and cos(pi/2d) --
;;;   once under each of the four x87 rounding modes, and prints each result to
;;;   seventeen significant digits AND as its raw 64-bit pattern.
;;;   (Verified, for part A:
;;;      RC=0 nearest  r = 0.70710678118654757  bits = 0x3fe6a09e667f3bcd
;;;      RC=1 down     r = 0.70710678118654746  bits = 0x3fe6a09e667f3bcc
;;;      RC=2 up       r = 0.70710678118654758  bits = 0x3fe6a09e667f3bcd )
;;;
;;;   *** LOOK AT THE LAST HEX DIGIT. *** ...bcd, ...bcc, ...bcd. The three
;;;   answers differ in the LOWEST BIT OF THE MANTISSA -- one ULP, or Unit in the
;;;   Last Place, the smallest difference two doubles can have. That is the whole
;;;   point of the file: printing seventeen decimal digits shows you the modes
;;;   disagree, but printing the BITS shows you exactly by how much.
;;;
;;;   READ rounding.asm IN THIS FOLDER FIRST. It explains the control word, the
;;;   RC and PC fields, and the clear-shift-or idiom that `set_round` uses. This
;;;   file is the same machinery applied to a harder question.
;;;
;;;   WHY THIS MATTERS BEYOND CURIOSITY. Every irrational result your program
;;;   computes is wrong in the last bit, and WHICH WAY it is wrong is a global
;;;   mode you may not have set. Two consequences worth carrying:
;;;     * `if (x == y)` on computed floating-point values is almost always a bug.
;;;       Use a tolerance -- exactly what code-0023.asm's `epsilon` and
;;;       newton_raphson.asm's `c_tol` are for.
;;;     * A program can produce different output on two machines, or in two
;;;       library versions, purely because of the rounding mode in force. That is
;;;       why "reproducible builds" people care about this.
;;;
;;;   THE `%016llx` CONVERSION prints an unsigned 64-bit integer in hex, padded
;;;   with zeros to sixteen digits. The value is fetched with a plain
;;;   `mov rcx, [res]` -- THE SAME EIGHT BYTES the `%.17g` reads as a double,
;;;   handed to printf twice through two different registers. That is regview.asm
;;;   in ps_code/11 all over again: THE BITS HAVE NO TYPE, only the conversion
;;;   does.
;;;
;;;   NOTE HOW THE ARGUMENTS ARE COUNTED. The format is
;;;       "  RC=%d %-24s r = %.17g   bits = 0x%016llx"
;;;   which is int, string, DOUBLE, int. Integer and floating-point arguments are
;;;   counted in SEPARATE sequences, so the doubles go in xmm0 onward and the
;;;   integers in rsi, rdx, rcx, ... -- the %.17g in the middle does not consume
;;;   an integer slot. Hence esi=RC, rdx=name, rcx=bits, xmm0=value, al=1.
;;;
;;;   THERE IS A HAND-WRITTEN atoi IN HERE, at `.atoi`. It parses argv[1] without
;;;   calling the C library, using the same Horner recurrence as code-0016.asm:
;;;   multiply the accumulator by 10 and add the next digit. The termination test
;;;   is neat -- `sub dl, '0'` then `cmp dl, 9 / ja` catches both "below '0'" and
;;;   "above '9'" in one UNSIGNED comparison, because a character below '0'
;;;   wraps around to a huge value. Worth understanding: it is a standard trick.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/10/cheb_root_round.asm"
;;;   ./asm "ps_code/10/cheb_root_round.asm" 4
;;;   ./asm "ps_code/10/cheb_root_round.asm" 8
;;;
;;;   Check part A against Python, which rounds to nearest:
;;;   python3 -c "
;;;   import math, struct
;;;   r = math.sqrt(0.5)
;;;   print('%.17g  0x%016x' % (r, struct.unpack('<Q', struct.pack('<d', r))[0]))"
;;;
;;;   And see what one ULP is worth here:
;;;   python3 -c "
;;;   import math
;;;   print(math.ulp(math.sqrt(0.5)))"
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/10/cheb_root_round.asm" 4
;;;
;;;   Watch the same computation give different bits:
;;;     break cheb_root_round.asm:NN     NN on the `fstp qword [res]` in .loopA
;;;     c
;;;     p $st0                    sqrt(0.5) under RC=0
;;;     si
;;;     x/1gx &res                the raw bits
;;;     c
;;;     si
;;;     x/1gx &res                under RC=1 -- and the last digit has moved
;;;
;;;   See the two views of one value being handed to printf:
;;;     break printf
;;;     c
;;;     p $xmm0.v2_double[0]      the value, as a double
;;;     p/x $rcx                  THE SAME EIGHT BYTES, as an integer
;;;     p $rcx == *(long*)&res    1 -- they really are the same memory
;;;
;;;   And watch the hand-written atoi:
;;;     ./debug "ps_code/10/cheb_root_round.asm" 12
;;;     break cheb_root_round.asm:NN    NN on the `imul ecx, ecx, 10` line
;;;     c
;;;     p $ecx                    the accumulator so far
;;;     p/c $dl                   the digit just decoded
;;;     c                         and again: 0, then 1, then 12
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE STACK ITSELF IS UNEVENTFUL: two loops, one frame, two callee-saved
;;;   registers pushed and popped. rbx holds the mode index and r12 holds N, and
;;;   both are CALLEE-SAVED, which is exactly why they survive the printf inside
;;;   each loop. The author's note "3 pushes -> 16-aligned" is correct: main
;;;   starts at 8 mod 16 and three pushes take it to 0, which is what the ABI
;;;   requires at a `call`. Confirm with `break printf` then `p $rsp % 16`.
;;;
;;;   THE INTERESTING STATE IS THE CONTROL WORD, and this file makes the same
;;;   point rounding.asm does but more sharply: IT IS A MODE, not a value. Two
;;;   consequences you can watch:
;;;
;;;   1. `set_round` and `set_prec_double` are ordinary functions that CHANGE HOW
;;;      LATER INSTRUCTIONS BEHAVE. Nothing in `fsqrt` or `fcos` names a rounding
;;;      direction; the answer comes from a register set several calls earlier.
;;;      That is genuinely different from every other function in this course,
;;;      which communicates through arguments and return values.
;;;
;;;   2. It is GLOBAL STATE SHARED WITH THE C LIBRARY. printf's own decimal
;;;      conversion rounds, so leaving RC in an odd mode changes printf's output
;;;      too. This program is careful:
;;;          fstcw [savecw]     at the top of main
;;;          fldcw [savecw]     at the very bottom
;;;      exactly as it would push and pop a callee-saved register. Try deleting
;;;      the restore and calling something afterwards.
;;;
;;;   THE GENERAL LESSON, and it is worth stating plainly: the ABI's promises are
;;;   not only about registers. rsp alignment, the direction flag, the x87
;;;   control word and SSE's MXCSR are all shared state that a well-behaved
;;;   function leaves as it found. A "callee-saved register" is just the most
;;;   familiar member of that family.
;;; ============================================================================

; ============================================================================
;  cheb_root_round.asm -- Round a ROOT of a Chebyshev polynomial under each of
;                         the four x87 rounding modes, at double precision.
;
;  Build:
;       nasm -f elf64 cheb_root_round.asm -o cheb_root_round.o
;       gcc  -no-pie  cheb_root_round.o   -o cheb_root_round
;       ./cheb_root_round 4          (N; degree d = 2N; default N=2)
;
;  Two roots are examined, both irrational:
;    (A) the positive root of T_2 = 2x^2 - 1 :  r = sqrt(1/2)  (= cos(pi/4))
;    (B) the largest root of T_{2N}          :  r = cos(pi/(2d))
;
;  For each rounding mode we recompute r with PC = 53 (double) and print
;  17 significant digits AND the raw 64-bit IEEE-754 bit pattern, so the
;  one-ULP differences between the modes are unmistakable.
; ============================================================================

global  main
                                        ;   export `main` for the C library start-up
extern  printf
                                        ;   the only external function needed

section .rodata
                                        ;   READ-ONLY data: strings that are never written
hdrA   db 10,"(A) r = sqrt(1/2) = positive root of T_2 = 2x^2 - 1",10
                                        ;   part A's header, only the last `db` terminated
       db    "    exact value is irrational; the last bit depends on rounding mode",10,0
hdrB   db 10,"(B) r = cos(pi/2d) = largest root of T_%d (d = %d)",10,0
                                        ;   part B's header: two ints, so 0 vector registers
line   db    "  RC=%d %-24s r = %.17g   bits = 0x%016llx",10,0
                                        ;   int, string, DOUBLE, int. %016llx prints an unsigned
                                        ;   64-bit value in hex, zero-padded to sixteen digits.
                                        ;   Integer and float arguments are counted SEPARATELY, so
                                        ;   the %.17g in the middle does not consume an integer slot.

n_near db "nearest (ties to even)",0
                                        ;   the four mode names, indexed by RC below
n_down db "down  (toward -inf)",0
n_up   db "up    (toward +inf)",0
n_chop db "toward zero (chop)",0

section .data
                                        ;   initialised, writable data
align 8
names  dq n_near, n_down, n_up, n_chop
                                        ;   A TABLE OF POINTERS, indexed by RC. `[names + rbx*8]`
                                        ;   picks one -- base + 8*index, 8 because these are addresses.
half   dq 0.5
                                        ;   x87 cannot take an immediate, so 0.5 lives in memory

section .bss
                                        ;   zero-filled at load time
align 8
cw     resw 1
                                        ;   scratch for reading and writing the 16-bit control word
savecw resw 1
                                        ;   the caller's original control word, restored at exit
res    resq 1
                                        ;   the computed root -- read TWICE, once as a double and once
                                        ;   as raw bits
Dval   resd 1
                                        ;   d = 2N, as a 32-bit int for `fild`
iden   resd 1
                                        ;   2d, likewise

section .text
                                        ;   the executable-code section

; RC = (edi & 3), keep other fields
set_round:
                                        ;   void set_round(int rc) -- identical to rounding.asm's.
                                        ;   CLEAR the field, SHIFT the new value into place, OR it in.
        fstcw   [cw]
                                        ;   STore Control Word: read the current settings
        mov     ax, [cw]
        and     ax, 0xF3FF
                                        ;   clear RC (bits 11-10): 0xF3FF has zeros exactly there
        mov     cx, di
                                        ;   the requested mode...
        and     cx, 3
                                        ;   ...masked to two bits
        shl     cx, 10
                                        ;   ...shifted into position
        or      ax, cx
                                        ;   ...and dropped in
        mov     [cw], ax
        fldcw   [cw]
                                        ;   LoaD Control Word makes it LIVE. Every FPU instruction
                                        ;   after this rounds differently.
        ret
                                        ;   pop the return address into rip. No frame: a LEAF function.

; PC = 53-bit double
set_prec_double:
                                        ;   void set_prec_double(void) -- force 53-bit working precision,
                                        ;   so results land directly in double rather than being
                                        ;   computed at 64 bits and rounded again later
        fstcw   [cw]
        mov     ax, [cw]
        and     ax, 0xFCFF
                                        ;   clear PC (bits 9-8)
        or      ax, 0x0200
                                        ;   ...and set it to 10b = double
        mov     [cw], ax
        fldcw   [cw]
        ret

main:
                                        ;   int main(int argc, char *argv[])
        push    rbp
                                        ;   prologue: save the caller's frame pointer
        mov     rbp, rsp
        push    rbx
                                        ;   rbx and r12 are CALLEE-SAVED, which is why the mode index
                                        ;   and N survive the printf calls. Three pushes take rsp from
                                        ;   8 mod 16 to 0 -- correct at a `call`.
        push    r12                     ; 3 pushes -> 16-aligned
        fstcw   [savecw]
                                        ;   remember the caller's control word, to restore at the end

                                        ; ---- N from argv[1] (default 2) ----
        mov     r12d, 2
                                        ;   the default N, if no argument is given
        cmp     edi, 2
                                        ;   argc < 2? then there is no argv[1]
        jl      .haveN
        mov     rdi, [rsi + 8]
                                        ;   argv[1] -- rsi is argv, +8 is element 1
        xor     ecx, ecx
                                        ;   the accumulator for the hand-written atoi
.atoi:
                                        ;   A HAND-WRITTEN atoi, using the same Horner recurrence as
                                        ;   code-0016.asm
        movzx   edx, byte [rdi]
                                        ;   load one character, zero-extended
        sub     dl, '0'
                                        ;   convert ASCII to a digit VALUE by subtracting 48
        cmp     dl, 9
                                        ;   THE NEAT TERMINATION TEST: `ja` is an UNSIGNED comparison,
                                        ;   so a character BELOW '0' has wrapped around to a huge
                                        ;   value and fails too. One test catches both ends.
        ja      .atoi_done
        imul    ecx, ecx, 10
                                        ;   acc *= 10 -- the three-operand `imul`, which needs no
                                        ;   hidden registers
        movzx   edx, dl
        add     ecx, edx
                                        ;   ...plus the new digit
        inc     rdi
                                        ;   advance one BYTE: characters are one byte each
        jmp     .atoi
.atoi_done:
                                        ;   end of the number
        test    ecx, ecx
                                        ;   a leading non-digit gives 0, so fall back to the default
        jz      .haveN
        mov     r12d, ecx
.haveN:
                                        ;   the shared continuation, whichever route got here
        mov     eax, r12d
                                        ;   d = 2N, computed by doubling
        add     eax, eax
        mov     [Dval], eax             ; d = 2N
                                        ;   parked in memory, because `fild` needs a MEMORY operand

        call    set_prec_double         ; all results land directly in 53-bit double
                                        ;   install 53-bit precision ONCE, for the whole program

                                        ; =================== (A) sqrt(1/2) ===================
        lea     rdi, [hdrA]
                                        ;   part A's header
        xor     eax, eax
                                        ;   0 vector registers
        call    printf

        xor     ebx, ebx
                                        ;   rc = 0
.loopA:
                                        ;   one pass per rounding mode. `.loopA` is LOCAL to main.
        mov     edi, ebx
        call    set_round
                                        ;   install this mode -- and it stays in force for the fsqrt
                                        ;   below AND for the printf
        fld     qword [half]
                                        ;   push 0.5
        fsqrt                           ; sqrt(0.5), rounded per current mode
                                        ;   square root, IN PLACE, rounded per the current RC.
                                        ;   Nothing in this instruction names the mode.
        fstp    qword [res]
                                        ;   store and pop -- the FPU stack is empty again
        lea     rdi, [line]
                                        ;   printf argument 1: the format string
        mov     esi, ebx
                                        ;   argument 2: the RC value
        mov     rdx, [names + rbx*8]
                                        ;   argument 3: the mode name, from the pointer table
        movsd   xmm0, [res]
                                        ;   the DOUBLE, in xmm0
        mov     rcx, [res]              ; raw bits for the %llx field
                                        ;   THE SAME EIGHT BYTES, read as an integer, for %016llx.
                                        ;   The bits have no type -- only the conversion does. See
                                        ;   regview.asm in ps_code/11.
        mov     al, 1                   ; one xmm (double) arg
                                        ;   ONE vector register carries an argument
        call    printf
        inc     ebx
                                        ;   next mode
        cmp     ebx, 4
        jl      .loopA

                                        ; =================== (B) cos(pi/2d) ===================
                                        ;   part B's header, with N and d as two ints
        lea     rdi, [hdrB]
        mov     esi, r12d
        mov     edx, [Dval]
        xor     eax, eax
                                        ;   0 vector registers
        call    printf

        xor     ebx, ebx
                                        ;   rc = 0
.loopB:
                                        ;   one pass per rounding mode
        mov     edi, ebx
        call    set_round
                                        ;   install this mode
        fldpi
                                        ;   push pi
        mov     eax, [Dval]
                                        ;   2d...
        add     eax, eax                ; 2d
        mov     [iden], eax
                                        ;   ...parked in memory for `fild`
        fild    dword [iden]
                                        ;   push it, CONVERTED from integer to float
        fdivp   st1, st0                ; pi/(2d)
                                        ;   st1 := st1/st0, then pop: pi/(2d). The value pushed FIRST
                                        ;   is the numerator.
        fcos                            ; cos(pi/2d), rounded per current mode
                                        ;   cosine, in place, argument in RADIANS -- and again rounded
                                        ;   per whatever RC currently says
        fstp    qword [res]
                                        ;   store and pop
        lea     rdi, [line]
                                        ;   the same output line as part A
        mov     esi, ebx
        mov     rdx, [names + rbx*8]
        movsd   xmm0, [res]
        mov     rcx, [res]
        mov     al, 1
                                        ;   one vector register
        call    printf
        inc     ebx
                                        ;   next mode
        cmp     ebx, 4
        jl      .loopB

        fldcw   [savecw]
                                        ;   RESTORE the caller's control word. It is global state
                                        ;   shared with the C library -- see the call-stack notes.
        xor     eax, eax
                                        ;   main's return value: 0 = success
        pop     r12
                                        ;   restore the callee-saved registers IN REVERSE ORDER
        pop     rbx
        pop     rbp
        ret
                                        ;   pop the return address into rip

