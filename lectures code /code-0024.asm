;;; ============================================================================
;;; code-0024.asm -- Dot product of two 64-element int32 vectors, using AVX2
;;; (the original header calls this file dot-product-i32.asm)
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Computes sum(A[i] * B[i]) over 64 pairs of 32-bit integers -- in EIGHT
;;;   loop iterations instead of sixty-four. The answer is 211052.
;;;
;;;   THE IDEA IS SIMD: Single Instruction, Multiple Data. A ymm register is 256
;;;   bits wide, which holds EIGHT 32-bit integers side by side, and `vpmulld`
;;;   multiplies all eight pairs at once. So one iteration does eight elements
;;;   and the loop count drops by a factor of eight. This is the same hardware
;;;   your compiler is trying to use when it says it "vectorised" a loop.
;;;
;;;   THE REGISTER FAMILY, which is worth getting straight once:
;;;       xmm0   128 bits   4 x int32   (SSE, 1999)
;;;       ymm0   256 bits   8 x int32   (AVX, 2011) -- xmm0 is its lower half
;;;       zmm0   512 bits  16 x int32   (AVX-512)
;;;   They are not separate registers: xmm0 IS the bottom 128 bits of ymm0. That
;;;   overlap is what makes the reduction below work.
;;;
;;;   THE INSTRUCTIONS:
;;;       vpxor  ymm0, ymm0, ymm0   XOR a register with itself = zero it. The
;;;                                 idiomatic "clear", and shorter to encode
;;;                                 than loading a constant.
;;;       vmovdqu ymm1, [A + rdx]   move 32 bytes, Unaligned. The `u` matters:
;;;                                 `vmovdqa` would FAULT unless the address is
;;;                                 32-byte aligned. Here `align 64` before A
;;;                                 makes it aligned anyway, so either would work.
;;;       vpmulld ymm3, ymm1, ymm2  Packed MULtiply Low Doubleword: eight 32x32
;;;                                 multiplies, keeping the low 32 bits of each.
;;;       vpaddd  ymm0, ymm0, ymm3  Packed ADD Doubleword: eight independent adds.
;;;
;;;   THE PART THAT ALWAYS CONFUSES PEOPLE IS THE END. After the loop, ymm0 holds
;;;   EIGHT partial sums, one per lane, and you need ONE number. That is a
;;;   HORIZONTAL REDUCTION, and SIMD hardware is deliberately bad at it -- lanes
;;;   are designed not to talk to each other. The standard trick is to fold the
;;;   register in half, repeatedly:
;;;
;;;       8 lanes:  [ a b c d | e f g h ]
;;;         vextracti128 xmm1, ymm0, 1   -> xmm1 = [ e f g h ], the UPPER half
;;;         vpaddd xmm0, xmm0, xmm1      -> [ a+e  b+f  c+g  d+h ]      (4 lanes)
;;;         vpshufd + vpaddd             -> pairs added                 (2 lanes)
;;;         vpshufd + vpaddd             -> everything in lane 0        (1 lane)
;;;         movd eax, xmm0               -> lane 0 into a general register
;;;
;;;   `vpshufd xmm1, xmm0, imm8` PERMUTES the four 32-bit lanes. The immediate is
;;;   four 2-bit fields, read right to left, each naming a SOURCE lane for the
;;;   corresponding destination lane. NASM's `0b10_11_00_01` underscores are just
;;;   readability -- so that pattern is (from the low field up) 01, 00, 11, 10:
;;;   destination lane 0 takes source lane 1, lane 1 takes lane 0, lane 2 takes
;;;   lane 3, lane 3 takes lane 2. In other words, SWAP NEIGHBOURS -- which is
;;;   exactly what you want before adding pairs together.
;;;
;;;   `movd eax, xmm0` moves 32 bits into eax, and WRITING TO A 32-BIT REGISTER
;;;   ZEROES THE UPPER 32 BITS OF THE 64-BIT ONE. That is why `mov rsi, rax` on
;;;   the next line is safe and why the professor's comment says "zero ext".
;;;
;;;   NOTE: this uses AVX2 (`vpmulld` on ymm). Under the course's Docker setup it
;;;   runs through qemu, which emulates AVX2 faithfully -- it just is not using
;;;   your Mac's actual vector unit.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0024.asm"        # The dot product is 211052
;;;
;;;   Check it independently:
;;;   python3 -c "
;;;   import re;s=open('originals/lectures code/code-0024.asm').read()
;;;   b=[[int(x) for l in re.findall(r'^ *dd (.*)\$',p,re.M) for x in l.split(',')]
;;;      for p in s.split('A:')[1].split('B:')]
;;;   print(sum(x*y for x,y in zip(*b)))"
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0024.asm"
;;;
;;;   The commands you need are the VECTOR ones:
;;;     break code-0024.asm:NN     put NN on the `vpaddd ymm0, ymm0, ymm3` line
;;;     c
;;;     p $ymm1.v8_int32           the eight elements of A in this block
;;;     p $ymm2.v8_int32           the matching eight from B
;;;     p $ymm3.v8_int32           their eight products
;;;     p $ymm0.v8_int32           the eight running partial sums
;;;     si
;;;     p $ymm0.v8_int32           each lane grew by its own product
;;;     c                          next block of eight
;;;
;;;   Then watch the reduction collapse:
;;;     break code-0024.asm:NN     NN on the `vextracti128` line
;;;     c
;;;     p $ymm0.v8_int32           eight numbers
;;;     si si                      extract + add
;;;     p $xmm0.v4_int32           four numbers
;;;     si si                      shuffle + add
;;;     p $xmm0.v4_int32           two distinct values, duplicated
;;;     si si                      shuffle + add
;;;     p $xmm0.v4_int32           the answer, in every lane
;;;     p $xmm0.v4_int32[0]        211052
;;;
;;;   And see what vpshufd actually does:
;;;     p $xmm0.v4_int32           before
;;;     si
;;;     p $xmm1.v4_int32           after -- neighbours swapped
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Almost nothing, and that is itself the lesson. `bt` shows two frames; `p
;;;   $rsp` never changes after the prologue; there are no locals, no pushes and
;;;   no calls inside the loop. THE VECTOR REGISTERS ARE THE WORKING STORAGE, and
;;;   they are enormous -- ymm0 alone holds 32 bytes, more than four of the stack
;;;   slots you have been carefully managing since code-0015.
;;;
;;;   THE POINT WORTH TAKING AWAY. Every earlier file in this course spent
;;;   instructions moving values between registers and the stack, because
;;;   registers were scarce. This one has so much register space that the stack
;;;   becomes irrelevant. Performance work in practice is largely about getting
;;;   into that regime -- keeping the hot data in registers, and out of memory.
;;;
;;;   THERE IS ONE STACK RULE STILL IN FORCE, and it is the one that will bite
;;;   you: `and rsp, -16` before `call printf`. Vector code makes it MORE
;;;   important, not less, because the C library's own SIMD routines use
;;;   ALIGNED loads (`movaps`, `vmovdqa`) on stack memory, and those FAULT on a
;;;   misaligned stack rather than merely running slowly. Test it:
;;;       break printf
;;;       c
;;;       p $rsp % 16       must be 8 here -- the `call` pushed 8 onto a
;;;                         16-aligned stack
;;;   If you ever see 0 at that point, your stack was misaligned before the call
;;;   and printf is one `movaps` away from a segmentation fault.
;;;
;;;   ONE MORE THING TO INSPECT, since it is invisible in the source: the ABI
;;;   says ALL of xmm0-xmm15 (and hence ymm0-ymm15) are CALLER-SAVED. So printf
;;;   may destroy every one of them. That is precisely why the final answer is
;;;   moved into eax BEFORE the call. Check it:
;;;       break printf
;;;       c
;;;       p $ymm0.v8_int32     whatever printf feels like
;;;       p $rsi               211052 -- safe, because it was moved in time
;;; ============================================================================

section .data                              ; initialised, writable data
fmt_dot_product:
        db `The dot product is %ld\n\0`    ; %ld = one 64-bit signed decimal
align 64                                   ; `align k` pads with zero bytes until the
                                           ;   next address is a multiple of k. 64 is
                                           ;   a cache-line boundary, so a 32-byte
                                           ;   vector load never straddles two lines.
A:                                         ; 64 x 32-bit integers = 256 bytes
        dd 71, 50, 61, 64, 88, 68, 89, 99, 70, 59, 86, 41, 57, 10, 84, 57
        dd 90, 44, 68, 56, 87, 16, 95, 32, 56, 85, 52, 42, 71, 96, 56, 18
        dd 44, 47, 75, 80, 53, 84, 37, 25, 74, 58, 58, 60, 21, 72, 67, 79
        dd 24, 41, 29, 42, 52, 76, 33, 31, 91, 90, 83, 71, 92, 67, 76, 93
                                           ; `dd` = define DOUBLEWORD: 4 bytes each.
                                           ;   Eight of these fit in one ymm register.
B:                                         ; the second vector, same shape
        dd 80, 40, 74, 57, 98, 61, 84, 31, 96, 38, 87, 45, 60, 55, 64, 76
        dd 49, 86, 21, 47, 44, 28, 36, 56, 25, 72, 19, 12, 42, 82, 18, 34
        dd 96, 11, 51, 16, 17, 98, 70, 67, 17, 50, 55, 88, 40, 32, 52, 17
        dd 13, 37, 24, 73, 81, 18, 79, 55, 56, 67, 94, 17, 33, 72, 83, 33

;;; The dot product should be 211052

section .bss                               ; declared but empty: this program needs no
                                           ;   uninitialised storage at all

extern printf                              ; supplied by the C library
global main                                ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- vectorised dot product of A and B.
;;;   C equivalent : long s = 0; for (i = 0; i < 64; i++) s += A[i]*B[i];
;;;   Receives     : nothing
;;;   Returns      : rax = 0
;;;   Registers    : ymm0 = eight running partial sums, one per lane
;;;                  ymm1, ymm2 = the current block of A and of B
;;;                  ymm3 = their eight products
;;;                  rcx = the loop counter (`loopnz` insists on rcx)
;;;                  rdx = the byte offset into both arrays
;;;   How it works : eight iterations, each handling eight elements, accumulating
;;;                  LANE-WISE. Afterwards a horizontal reduction folds the eight
;;;                  lanes into one number. See the header for the fold.
;;; ----------------------------------------------------------------------------
main:
        push rbp                           ; save the old frame-pointer (callee-saved)
        mov rbp, rsp                       ; anchor this frame
        and rsp, -16                       ; align the stack for the printf at the end

        mov rcx, 8                         ; loop counter
                                           ;   64 elements / 8 lanes = 8 iterations.
                                           ;   rcx is not a choice: `loopnz` uses it.
        mov rdx, 0                         ; the byte offset into A and B, starting at 0
        vpxor ymm0, ymm0, ymm0             ; zero out a 256-bit register
                                           ;   XOR anything with itself gives zero. The
                                           ;   accumulator starts empty in all eight
                                           ;   lanes.
.L:
        vmovdqu ymm1, [A + rdx]            ; load a packed 32-bit ints
                                           ;   32 bytes = eight int32s from A. The `u`
                                           ;   is Unaligned; `vmovdqa` would fault on a
                                           ;   non-32-byte-aligned address.
        vmovdqu ymm2, [B + rdx]            ; load a packed 32-bit ints
                                           ;   the matching eight from B
        vpmulld ymm3, ymm1, ymm2           ; packed multiply 32-bit ints
                                           ;   EIGHT multiplies in one instruction,
                                           ;   keeping the LOW 32 bits of each product
        vpaddd ymm0, ymm0, ymm3            ; packed add 32-bit ints
                                           ;   eight independent adds: lane k of the
                                           ;   accumulator gets lane k of the products.
                                           ;   Lanes never mix -- that is the whole
                                           ;   reason a reduction is needed later.
        add rdx, 4*8                       ; next displacement
                                           ;   4 bytes per int * 8 lanes = 32 bytes
        loopnz .L                          ; decrement rcx and repeat while it is
                                           ;   non-zero (and ZF is clear)
.Lout:
;;; --- the HORIZONTAL REDUCTION: eight partial sums -> one number ---
        vextracti128 xmm1, ymm0, 1         ; move the upper (1) 128-bits to xmm1
                                           ;   the immediate 1 selects the HIGH half.
                                           ;   xmm0 already IS the low half of ymm0.
        vpaddd xmm0, xmm0, xmm1            ; packed add 32-bit ints
                                           ;   eight lanes folded into four
        vpshufd xmm1, xmm0, 0b10_11_00_01  ; shuffle 4 32-bit ints
                                           ;   two bits per destination lane, read from
                                           ;   the right: lane0<-1, lane1<-0, lane2<-3,
                                           ;   lane3<-2. I.e. swap neighbours.
        vpaddd xmm0, xmm0, xmm1            ; packed add 32-bit ints
                                           ;   four lanes folded into two distinct
                                           ;   values (each appearing twice)
        vpshufd xmm1, xmm0, 0b01_00_10_11  ; shuffle 4 32-bit ints
                                           ;   now swap the two halves, so the two
                                           ;   distinct values meet
        vpaddd xmm0, xmm0, xmm1            ; packed add 32-bit ints
                                           ;   every lane now holds the full sum

        movd eax, xmm0                     ; move the lower 32-bit int to eax, zero ext
                                           ;   writing a 32-bit register automatically
                                           ;   zeroes the upper 32 bits of rax
        mov rsi, rax                       ; move the zero-extended eax to rsi --- arg
                                           ;   printf argument 2. Done BEFORE the call,
                                           ;   because every xmm/ymm register is
                                           ;   caller-saved and printf may destroy them.
        mov rdi, fmt_dot_product           ; format string for output
        mov rax, 0                         ; 0 xmm regs to preserve
                                           ;   the variadic rule: rax = how many VECTOR
                                           ;   registers carry arguments. The answer
                                           ;   travels in rsi, an integer register, so 0.
        call printf                        ; ...and print

        mov rax, 0                         ; status OK for the OS
        mov rsp, rbp                       ; restore the stack pointer from the anchor
        pop rbp                            ; restore the caller's frame-pointer
        ret                                ; pop the return address into rip

section .note.GNU-stack noalloc noexec     ; required Linux marker: stack is not exec
