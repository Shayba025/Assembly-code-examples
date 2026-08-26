;;; ============================================================================
;;; code-0026.asm -- The arithmetic mean of a sample of doubles, using AVX
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Adds up 148 doubles four at a time and divides by the count, printing the
;;;   sample mean. It is code-0025 with the multiply removed and a division
;;;   added, so read that file first for the SIMD fundamentals -- lanes, packed
;;;   operations, and the horizontal reduction at the end.
;;;
;;;   THE TWO GENUINELY NEW IDEAS ARE ABOUT THE ASSEMBLER AND ABOUT CONVERSION:
;;;
;;;   1. THE ARRAY MEASURES ITSELF.
;;;          N:  dq ($ - sample) >> 3
;;;      `$` is "the address of this point", so `$ - sample` is the number of
;;;      BYTES emitted between the label and here, and `>> 3` divides by 8 to
;;;      turn bytes into doubles. All of it is computed by NASM at assembly time;
;;;      no instruction runs. Add or delete a `dq` line and N corrects itself --
;;;      which is exactly what you want, because a hand-maintained count is a
;;;      bug waiting to happen. (You met `$` in code-0008, measuring a string.)
;;;
;;;   2. CONVERTING AN INTEGER TO A DOUBLE.
;;;          cvtsi2sd xmm1, qword [N]
;;;      CVT-SI-2-SD: ConVerT Signed Integer to Scalar Double. Integers and
;;;      doubles have completely different bit layouts, so you cannot simply move
;;;      the bits -- the CPU has to build the sign, exponent and mantissa. There
;;;      is a whole family: cvtsd2si (back again), cvttsd2si (truncating rather
;;;      than rounding), cvtps2pd, and so on. When a mean comes out absurdly
;;;      wrong, a missing conversion is usually why.
;;;
;;;   Then `divsd xmm0, xmm1` -- SCALAR divide, one lane -- gives the mean.
;;;
;;;   WHY THE LOOP COUNT IS `N >> 2`: four doubles per 256-bit register, so the
;;;   number of iterations is the number of elements divided by four. NOTE THE
;;;   ASSUMPTION: this only works because 148 happens to be a multiple of 4. Real
;;;   vector code needs a scalar "tail loop" for the leftover elements, and
;;;   forgetting it is one of the classic vectorisation bugs. Delete one `dq`
;;;   value from the sample and watch the answer go wrong.
;;;
;;;   `𝑥̄ = %g` in the format string is UTF-8: a mathematical italic x with a
;;;   combining macron -- "x bar", the standard notation for a sample mean.
;;;   printf copies the bytes through without knowing any of that.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0026.asm"
;;;
;;;   Check it independently:
;;;   python3 -c "
;;;   import re
;;;   s=open('originals/lectures code/code-0026.asm').read().split('sample:')[1].split('N:')[0]
;;;   v=[float(x) for l in re.findall(r'dq (.*)',s) for x in l.split(',')]
;;;   print(len(v), sum(v)/len(v))"
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0026.asm"
;;;
;;;   Useful session:
;;;     p (long)N                  148 -- the count the assembler worked out
;;;     break code-0026.asm:NN     put NN on the `vaddpd` line
;;;     c
;;;     p $ymm1.v4_double          the four values just loaded
;;;     p $ymm0.v4_double          the four running partial sums
;;;     si
;;;     p $ymm0.v4_double          each lane grew by its own value
;;;
;;;   Watch the reduction and the division:
;;;     break code-0026.asm:NN     NN on the `cvtsi2sd` line
;;;     c
;;;     p $xmm0.v2_double[0]       the TOTAL of all 148 values
;;;     si
;;;     p $xmm1.v2_double[0]       148, now as a double -- the conversion
;;;     si
;;;     p $xmm0.v2_double[0]       the mean
;;;
;;;   And see why the conversion is needed -- look at the raw bits first:
;;;     x/1gx &N                   0x94 = 148, as an integer
;;;     p *(double*)&N             a denormal near zero: the SAME BITS read as a
;;;                                double are meaningless. That is what you would
;;;                                have divided by without cvtsi2sd.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   The same near-absence as code-0024 and code-0025: two frames, no locals, no
;;;   pushes, rsp fixed after the prologue. All the state is in ymm0 and two
;;;   general registers.
;;;
;;;   THE THING WORTH STUDYING IN THIS FILE IS THE HANDOFF TO printf, because it
;;;   is the one place where a convention could go wrong and the compiler is not
;;;   there to save you:
;;;       break printf
;;;       c
;;;       p $rax                   1 -- "one vector register carries an argument"
;;;       p $xmm0.v2_double[0]     the mean itself, in xmm0 as the ABI requires
;;;       x/s $rdi                 the format string
;;;       p $rsp % 16              8, because `call` pushed 8 onto a 16-aligned
;;;                                stack. Anything else means trouble.
;;;   Three separate promises, all invisible in the source: the value is in xmm0,
;;;   the count is in rax, and the stack was aligned before the call. Break any
;;;   one and printf prints rubbish or crashes -- and nothing in the assembler
;;;   will warn you. Try it: change `mov rax, 1` to `mov rax, 0`, rebuild, and
;;;   see what gets printed.
;;;
;;;   ALSO WORTH INTERNALISING: the count N lives in .data, not on the stack, and
;;;   this is the right choice for a reason that has nothing to do with
;;;   convenience -- it is a compile-time constant computed by `$ - sample`. It
;;;   cannot be a stack local, because there is nothing at run time to compute
;;;   it from. Compare `x/1gd &N` with `p $rcx` after the `shr`: 148 and 37, the
;;;   element count and the iteration count, one static and one derived.
;;; ============================================================================

section .data                           ; initialised, writable data
sample:                                 ; 148 doubles, in rows of four
        dq 40.8781, 39.4805, 57.9506, 99.2832
        dq 72.3326, 47.7259, 60.7139, 38.9284
        dq 54.3306, 92.5317, 25.7033, 94.5752
        dq 40.2808, 62.8094, 64.3201, 21.5902
        dq 35.5367, 70.6876, 27.9659, 93.6828
        dq 98.2984, 78.9197, 50.7126, 24.3674
        dq 88.8176, 81.2694, 78.6387, 84.4927
        dq 46.8405, 37.5657, 49.4344, 31.8193
        dq 11.9792, 88.7191, 50.4452, 54.9542
        dq 45.7645, 35.9061, 87.5191, 51.7208
        dq 49.6613, 79.8551, 35.6506, 67.4143
        dq 31.6589, 67.1015, 52.2409, 48.4985
        dq 10.8702, 60.3187, 65.2419, 11.9179
        dq 86.5494, 69.3992, 95.6343, 38.9457
        dq 15.5069, 34.2624, 78.6828, 20.3425
        dq 15.9881, 58.1798, 26.8052, 82.2867
        dq 98.5116, 54.6404, 20.7818, 96.3389
        dq 14.6046, 13.5955, 81.6156, 78.4637
        dq 28.8693, 26.4101, 18.5849, 23.5057
        dq 67.9671, 31.3897, 45.8724, 97.7953
        dq 36.4482, 85.1586, 26.1192, 38.8874
        dq 94.1524, 50.8425, 70.8419, 65.9221
        dq 95.4083, 58.7586, 63.2649, 21.4259
        dq 31.1596, 87.7406, 65.9314, 64.3988
        dq 96.8942, 47.4426, 22.1219, 97.4994
        dq 57.3399, 50.8708, 66.2365, 36.2098
        dq 26.3673, 16.4719, 42.9514, 71.5653
        dq 26.7919, 92.6302, 25.7267, 30.6001
        dq 39.4775, 57.2097, 26.3235, 31.6893
        dq 72.1578, 32.6339, 36.4688, 87.9616
        dq 85.1997, 85.8152, 44.4489, 83.2171
        dq 25.3718, 34.5233, 16.2087, 26.3827
        dq 88.6597, 51.5385, 11.7916, 32.7978
        dq 87.3316, 98.7361, 35.3831, 70.1892
        dq 87.6416, 33.4545, 62.7418, 41.2252
        dq 41.2182, 55.2321, 71.3898, 35.3907
        dq 71.4443, 81.6679, 55.2032, 60.6856
                                        ; `dq` = define QUADWORD: 8 bytes each,
                                        ;   holding IEEE-754 doubles. Four fit in
                                        ;   one 256-bit ymm register.
N:
        dq ($ - sample) >> 3            ; THE ARRAY MEASURES ITSELF. `$` is the
                                        ;   address of this point, so `$ - sample`
                                        ;   is the byte count above; `>> 3` divides
                                        ;   by 8 to give the number of doubles. All
                                        ;   of it computed by NASM at assembly time.
fmt_output:
        db `𝑥̄̄ = %g\n\0`
                                        ; UTF-8: a mathematical italic x with a
                                        ;   combining macron -- "x bar", the sample
                                        ;   mean. %g prints a double compactly.

section .bss                            ; declared but empty: no uninitialised storage

extern printf                           ; supplied by the C library
global main                             ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- compute and print the arithmetic mean of `sample`.
;;;   C equivalent : double s = 0;
;;;                  for (i = 0; i < N; i++) s += sample[i];
;;;                  printf("x = %g\n", s / N);
;;;   Receives     : nothing
;;;   Returns      : rax = 0
;;;   Registers    : ymm0 = four running partial sums, one per lane
;;;                  ymm1 = the current block of four values
;;;                  rcx  = the iteration count, N/4 (`loopnz` insists on rcx)
;;;                  rdx  = the byte offset into the array
;;;   How it works : accumulate four lanes at a time, reduce the four lanes to one
;;;                  number, convert N to a double, divide. Assumes N is a
;;;                  multiple of 4 -- see the header.
;;; ----------------------------------------------------------------------------
main:
        push rbp                        ; save the old frame-pointer (callee-saved)
        mov rbp, rsp                    ; anchor this frame
        and rsp, -16                    ; align the stack for the printf at the end

        mov rcx, qword [N]              ; the element count the assembler computed
        shr rcx, 2                      ; divide by 4: shifting right k bits divides
                                        ;   by 2^k. Four doubles per iteration, so
                                        ;   this is the loop count. (Exact only
                                        ;   because N is a multiple of 4.)
        mov rdx, 0                      ; the byte offset into the array
        vxorpd ymm0, ymm0, ymm0         ; zero the accumulator in all four lanes. The
                                        ;   `pd` form because the data is
                                        ;   floating-point.

.Loop:
        vmovupd ymm1, [sample + rdx]    ; four doubles. `u` = Unaligned load.
        vaddpd ymm0, ymm0, ymm1         ; four independent adds: lane k of the
                                        ;   accumulator gets lane k of the block.
                                        ;   Lanes never mix -- hence the reduction.
        add rdx, 8*4                    ; 8 bytes per double * 4 lanes = 32 bytes
        loopnz .Loop                    ; decrement rcx and repeat while non-zero

;;; --- the HORIZONTAL REDUCTION: four partial sums -> one number ---
        vextractf128 xmm1, ymm0, 1      ; the UPPER 128 bits (lanes 2 and 3); xmm0
                                        ;   already is the lower half
        vaddpd xmm0, xmm0, xmm1         ; four lanes folded into two
        movapd xmm1, xmm0               ; copy the pair...
        unpckhpd xmm1, xmm1             ; ...and broadcast the HIGH lane into both,
                                        ;   so a scalar add can reach it
        addsd xmm0, xmm1                ; SCALAR add (`sd`): lane 0 now holds the
                                        ;   total of all N values

        cvtsi2sd xmm1, qword [N]        ; ConVerT Signed Integer to Scalar Double.
                                        ;   The bit layouts are completely different,
                                        ;   so this is real work, not a move. Skip it
                                        ;   and you divide by a denormal near zero --
                                        ;   check `p *(double*)&N` in gdb.
        divsd xmm0, xmm1                ; SCALAR divide: the mean, in xmm0 lane 0

        mov rdi, fmt_output             ; printf argument 1: the format string
        mov rax, 1                      ; |{xmm0}| = 1: exactly one vector register
                                        ;   carries an argument. THE VARIADIC RULE.
        call printf                     ; the mean is already in xmm0, where the ABI
                                        ;   says the first %g argument must be

        mov rax, 0                      ; status OK for the OS
        mov rsp, rbp                    ; restore the stack pointer from the anchor
        pop rbp                         ; restore the caller's frame-pointer
        ret                             ; pop the return address into rip

section .note.GNU-stack noalloc noexec  ; required Linux marker: stack is not exec
