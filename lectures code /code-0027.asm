;;; ============================================================================
;;; code-0027.asm -- Minimum and maximum of a sample of doubles, using AVX
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Finds both the smallest and the largest of 172 doubles in a single pass,
;;;   four elements at a time. It is the last of the four SIMD examples; read
;;;   code-0024 for the fundamentals and code-0025 for the floating-point ones.
;;;
;;;   WHAT MAKES THIS ONE DIFFERENT AND WORTH STUDYING:
;;;
;;;   1. MIN AND MAX ARE BRANCHLESS. `vminpd` and `vmaxpd` compare four pairs and
;;;      keep the smaller (or larger) of each -- no `cmp`, no `jl`, no
;;;      mispredicted branch. On a scalar CPU a min/max loop costs an
;;;      unpredictable branch per element; here it costs nothing at all. This is
;;;      one of the biggest practical wins of SIMD, and it applies just as much
;;;      to the scalar `minsd`/`maxsd` instructions.
;;;
;;;   2. TWO ACCUMULATORS AT ONCE, IN ONE PASS. ymm0 carries four running minima
;;;      and ymm1 four running maxima, and each iteration updates both from the
;;;      same loaded block. Doing min and max in separate loops would read the
;;;      array twice; this reads it once. On large data the memory traffic, not
;;;      the arithmetic, is what costs you.
;;;
;;;   3. THE ACCUMULATORS ARE SEEDED FROM THE DATA, NOT FROM A CONSTANT:
;;;          vmovupd ymm0, [sample]     ; first four values
;;;          vmovapd ymm1, ymm0         ; same starting point for the max
;;;          mov rcx, N/4 ; dec rcx     ; ...so one fewer iteration
;;;          mov rdx, 32                ; ...starting from the SECOND block
;;;      You could instead start ymm0 at +infinity and ymm1 at -infinity, but
;;;      seeding from element 0 avoids needing those constants and handles the
;;;      degenerate cases correctly. Note the three coordinated adjustments --
;;;      the seed, the decremented counter and the offset of 32 -- and how a
;;;      mistake in any one of them would silently produce a wrong answer.
;;;
;;;   4. TWO REDUCTIONS, NOT ONE. Each accumulator has to be folded from four
;;;      lanes to a single value, and each fold uses the MATCHING operation --
;;;      `vminpd`/`vminsd` for one, `vmaxpd`/`vmaxsd` for the other. The pattern
;;;      is the same fold-in-half as in code-0025, done twice:
;;;          [ a b | c d ]
;;;            vextractf128 -> the high pair          [ c d ]
;;;            vminpd       -> [ min(a,c)  min(b,d) ]        (2 lanes)
;;;            unpckhpd     -> broadcast the high lane
;;;            vminsd       -> scalar: the overall minimum    (1 lane)
;;;
;;;   5. TWO DOUBLES TO printf. The ABI puts the first in xmm0 and the second in
;;;      xmm1 -- which is exactly where they already are -- and rax must say how
;;;      many vector registers are in use. Hence `mov rax, 2`, and the
;;;      professor's comment `|{xmm0, xmm1}| = 2`. The format string names min
;;;      first and max second, matching the register order.
;;;
;;;   THE SAME CAVEAT AS code-0026: the loop assumes N is a multiple of 4. Delete
;;;   one value from the sample and the last few elements are simply never
;;;   examined. Production vector code always needs a scalar tail.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0027.asm"
;;;
;;;   Check it independently:
;;;   python3 -c "
;;;   import re
;;;   s=open('originals/lectures code/code-0027.asm').read().split('sample:')[1].split('N:')[0]
;;;   v=[float(x) for l in re.findall(r'dq (.*)',s) for x in l.split(',')]
;;;   print(len(v), min(v), max(v))"
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0027.asm"
;;;
;;;   Useful session -- watch both accumulators at once:
;;;     break code-0027.asm:NN     put NN on the `vminpd ymm0, ymm0, ymm2` line
;;;     c
;;;     display $ymm0.v4_double    the four running minima
;;;     display $ymm1.v4_double    the four running maxima
;;;     display $ymm2.v4_double    the block just loaded
;;;     c   c   c                  and watch them converge from both directions
;;;
;;;   Watch the two reductions:
;;;     break code-0027.asm:NN     NN on the first `vextractf128`
;;;     c
;;;     p $ymm0.v4_double          four candidate minima
;;;     si si si si                the two extract/fold pairs
;;;     p $xmm0.v2_double          two
;;;     p $xmm1.v2_double          two
;;;     si si si si si si          the scalar tails
;;;     p $xmm0.v2_double[0]       the minimum
;;;     p $xmm1.v2_double[0]       the maximum
;;;
;;;   And confirm the calling convention at the hand-off:
;;;     break printf
;;;     c
;;;     p $rax                     2
;;;     p $xmm0.v2_double[0]       min -- argument 1
;;;     p $xmm1.v2_double[0]       max -- argument 2
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   As with the other three SIMD files, the stack is idle: `bt` shows two
;;;   frames, `p $rsp` never moves after the prologue, and there are no locals at
;;;   all. Everything lives in vector registers -- and this program keeps TWO
;;;   full accumulators plus a working block, which is 96 bytes of live state
;;;   held entirely in the register file. Compare code-0018, where three
;;;   ordinary integers had to be spilled to the frame because printf was called
;;;   inside the loop.
;;;
;;;   THAT CONTRAST IS THE LESSON THE FOUR SIMD FILES ARE BUILDING TO. Registers
;;;   are only "scarce" relative to what you are doing with them. A tight loop
;;;   with no calls in it can keep everything in registers and never touch memory
;;;   except to read its input. Put one `call` inside that loop and every
;;;   caller-saved register -- including all sixteen ymm registers -- becomes
;;;   unreliable, and you are back to spilling. Prove it to yourself:
;;;       break printf
;;;       c
;;;       p $ymm0.v4_double        the minima, still intact
;;;       finish
;;;       p $ymm0.v4_double        whatever printf left behind
;;;   Now imagine that happening 43 times inside the loop instead of once at the
;;;   end. THAT is why vectorised inner loops never contain function calls, and
;;;   why the whole reduction is done before printf is allowed anywhere near the
;;;   registers.
;;;
;;;   One last thing worth checking, because it is the only stack rule still in
;;;   play: `p $rsp % 16` at the breakpoint on printf must be 8 -- `call` pushed
;;;   8 bytes onto the 16-aligned stack that `and rsp, -16` established. The C
;;;   library uses aligned vector loads on its own stack memory, so a misaligned
;;;   stack here is a fault, not a slowdown.
;;; ============================================================================

section .data                           ; initialised, writable data
sample:                                 ; 172 doubles, in rows of four
        dq 96.1718, 80.8484, 95.2312, 12.1916
        dq 32.5818, 11.4896, 42.8641, 51.2455
        dq 52.1779, 56.3347, 14.8188, 92.1523
        dq 43.8695, 34.1928, 16.7395, 85.6557
        dq 44.5534, 94.9655, 86.8459, 32.1999
        dq 62.2914, 96.9621, 58.5607, 93.5703
        dq 22.3382, 96.7021, 35.8124, 57.9127
        dq 10.9557, 23.7534, 96.8266, 51.9063
        dq 34.8289, 21.8146, 90.9442, 13.7077
        dq 76.9575, 32.8763, 31.5055, 42.4096
        dq 53.8326, 32.4243, 73.5602, 85.7678
        dq 66.4255, 69.5429, 41.7452, 93.1886
        dq 27.9286, 47.5015, 89.9464, 42.7962
        dq 44.1866, 85.6127, 68.9273, 16.6703
        dq 48.8974, 80.5159, 77.6592, 12.7647
        dq 30.8304, 79.5308, 94.7173, 36.2284
        dq 87.2777, 27.4244, 56.3336, 15.6792
        dq 21.3969, 85.3258, 34.4592, 57.1645
        dq 32.6628, 35.8243, 12.1827, 61.9408
        dq 73.1785, 31.8773, 63.6888, 18.4526
        dq 63.7494, 94.3193, 12.1066, 50.5095
        dq 82.3048, 27.9579, 25.4646, 39.3162
        dq 52.8395, 36.1814, 54.4841, 87.5964
        dq 52.1535, 97.2988, 99.9001, 92.5129
        dq 84.9077, 80.9838, 97.6403, 14.6752
        dq 61.3047, 81.3916, 73.1201, 43.9868
        dq 58.7898, 21.4613, 60.2337, 10.7538
        dq 34.1944, 26.3309, 93.2193, 47.3578
        dq 20.3761, 45.5243, 12.7449, 54.3413
        dq 81.6804, 68.6813, 48.7148, 54.1934
        dq 62.8312, 90.3593, 72.9626, 79.6045
        dq 19.6616, 64.8917, 43.5148, 29.5925
        dq 71.9392, 79.4136, 78.5343, 81.6629
        dq 84.6281, 54.8005, 62.3565, 95.8625
        dq 61.5016, 58.4369, 86.4835, 80.3342
        dq 12.7024, 32.5363, 52.5692, 67.8161
        dq 79.3387, 18.1344, 57.5913, 64.5804
        dq 21.5105, 80.5835, 93.4775, 82.5121
        dq 61.4172, 35.9423, 75.9389, 31.8715
        dq 73.4112, 98.7219, 53.2434, 49.5041
        dq 74.2182, 94.5252, 53.1548, 52.7846
        dq 89.9503, 65.9427, 46.6071, 11.3474
        dq 69.7084, 90.3573, 37.8022, 11.8797
                                        ; `dq` = define QUADWORD: 8 bytes each,
                                        ;   holding IEEE-754 doubles. Four fit in
                                        ;   one 256-bit ymm register.
N:
        dq ($ - sample) >> 3            ; THE ARRAY MEASURES ITSELF: `$` is the
                                        ;   address of this point, so `$ - sample` is
                                        ;   the byte count above and `>> 3` turns
                                        ;   bytes into doubles. Computed by NASM at
                                        ;   assembly time; edit the data and it
                                        ;   corrects itself.
fmt_output:
        db `min(sample) = %g; max(sample) = %g\n\0`
                                        ; TWO %g conversions, so two doubles -- which
                                        ;   the ABI will take from xmm0 and xmm1, in
                                        ;   that order. The format names min first,
                                        ;   matching the register order below.


section .bss                            ; declared but empty: no uninitialised storage

extern printf                           ; supplied by the C library
global main                             ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- find the minimum and maximum of `sample` in one pass.
;;;   C equivalent : double lo = sample[0], hi = sample[0];
;;;                  for (i = 1; i < N; i++) {
;;;                      if (sample[i] < lo) lo = sample[i];
;;;                      if (sample[i] > hi) hi = sample[i];
;;;                  }
;;;   Receives     : nothing
;;;   Returns      : rax = 0
;;;   Registers    : ymm0 = four running MINIMA, one per lane
;;;                  ymm1 = four running MAXIMA, one per lane
;;;                  ymm2 = the current block of four values
;;;                  rcx  = the iteration count (`loopnz` insists on rcx)
;;;                  rdx  = the byte offset into the array
;;;   How it works : seed both accumulators from the first block, then walk the
;;;                  rest updating both with branchless packed min/max. Finally
;;;                  reduce each accumulator from four lanes to one, and hand the
;;;                  two answers to printf in xmm0 and xmm1.
;;; ----------------------------------------------------------------------------
main:
        push rbp                        ; save the old frame-pointer (callee-saved)
        mov rbp, rsp                    ; anchor this frame
        and rsp, -16                    ; align the stack for the printf at the end

        mov rcx, qword [N]              ; the element count the assembler computed
        shr rcx, 2                      ; divide by 4: four doubles per iteration
        dec rcx                         ; ...one fewer, because the FIRST block has
                                        ;   already been consumed as the seed below
        mov rdx, 32                     ; ...and start at the SECOND block, 32 bytes
                                        ;   in. Three coordinated adjustments; get
                                        ;   any one wrong and the answer is silently
                                        ;   incorrect.
        vmovupd ymm0, [sample]          ; seed the minima with the first four values
        vmovapd ymm1, ymm0              ; and the maxima with the same four.
                                        ;   `vmovapd` is the ALIGNED move -- safe
                                        ;   here because it is register-to-register.
                                        ;   Seeding from real data avoids needing
                                        ;   +infinity and -infinity constants.

.Loop:
        vmovupd ymm2, [sample + rdx]    ; four more doubles. `u` = Unaligned load.
        vminpd ymm0, ymm0, ymm2         ; four BRANCHLESS comparisons: lane k keeps
                                        ;   whichever of the two is smaller. No cmp,
                                        ;   no jump, no branch misprediction.
        vmaxpd ymm1, ymm1, ymm2         ; and four more, keeping the larger. The same
                                        ;   loaded block feeds both, so the array is
                                        ;   read only ONCE.
        add rdx, 8*4                    ; 8 bytes per double * 4 lanes = 32 bytes
        loopnz .Loop                    ; decrement rcx and repeat while non-zero

;;; --- TWO horizontal reductions, each using its own operation ---
        vextractf128 xmm2, ymm0, 1      ; the upper 128 bits of the minima
        vminpd xmm0, xmm0, xmm2         ; four lanes folded into two
        vextractf128 xmm2, ymm1, 1      ; the upper 128 bits of the maxima
        vmaxpd xmm1, xmm1, xmm2         ; four lanes folded into two

        movapd xmm2, xmm0               ; copy the two candidate minima...
        unpckhpd xmm2, xmm2             ; ...and broadcast the HIGH lane into both,
                                        ;   so a scalar op can reach it
        vminsd xmm0, xmm0, xmm2         ; SCALAR min (`sd`): xmm0 lane 0 is now the
                                        ;   minimum of the whole sample

        movapd xmm2, xmm1               ; the same fold for the maxima...
        unpckhpd xmm2, xmm2             ; ...broadcast the high lane...
        vmaxsd xmm1, xmm1, xmm2         ; ...and the scalar max. xmm1 lane 0 is the
                                        ;   maximum of the whole sample.

        mov rdi, fmt_output             ; printf argument 1: the format string
        mov rax, 2                      ; |{xmm0, xmm1}| = 2
                                        ;   THE VARIADIC RULE: rax counts the vector
                                        ;   registers carrying arguments. Two doubles,
                                        ;   already sitting in xmm0 and xmm1 exactly
                                        ;   as the ABI requires, so no moves are needed.
        call printf

        mov rax, 0                      ; status OK for the OS
        mov rsp, rbp                    ; restore the stack pointer from the anchor
        pop rbp                         ; restore the caller's frame-pointer
        ret                             ; pop the return address into rip

section .note.GNU-stack noalloc noexec  ; required Linux marker: stack is not exec
