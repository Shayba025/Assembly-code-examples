;;; ============================================================================
;;; bsf.asm -- BSF and BSR: finding the lowest and highest set bit
;;; Practice session 2                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Scans 0x5566 for its lowest and highest set bits.
;;;   (Verified: rax = 1 and rcx = 14 at the `nop`.)
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` has no `ret`.
;;;
;;;   THE TWO INSTRUCTIONS:
;;;       bsf dst, src    Bit Scan Forward  -- dst := index of the LOWEST set bit
;;;       bsr dst, src    Bit Scan Reverse  -- dst := index of the HIGHEST set bit
;;;   Bit 0 is the least significant, so both answers are counted from the right.
;;;
;;;   CHECK IT BY HAND. 0x5566 in binary, bit 15 on the left:
;;;
;;;       bit:  15 14 13 12 11 10  9  8   7  6  5  4  3  2  1  0
;;;             ---------------------------------------------------
;;;              0  1  0  1  0  1  0  1   0  1  1  0  0  1  1  0
;;;              \____ 5 ____/\____ 5 ___/\____ 6 ___/\____ 6 ___/
;;;
;;;   The lowest 1 is at bit 1, so `bsf` gives 1. The highest is at bit 14, so
;;;   `bsr` gives 14. (Note `bsr` returns the INDEX, not the count of bits -- the
;;;   number of bits needed to represent the value is bsr + 1, which is also
;;;   floor(log2(x)) + 1.)
;;;
;;;   THE TRAP: WHAT HAPPENS WHEN THE SOURCE IS ZERO. There is no "lowest set
;;;   bit" of 0, so both instructions leave the destination UNDEFINED and set ZF
;;;   to 1 instead. You must test ZF before trusting the answer:
;;;       bsf rax, rbx
;;;       jz  no_bits_set        ; rax is garbage -- do not use it
;;;   This is the single most common bug with these two instructions, and it is
;;;   the reason the newer TZCNT and LZCNT instructions exist: they return the
;;;   operand width (64) for a zero input instead of leaving you with rubbish.
;;;
;;;   WHERE YOU WOULD USE THEM:
;;;     * `bsr` is floor(log2(x)) -- how many bits a number needs, which bucket a
;;;       size falls into in an allocator, how many digits to print.
;;;     * `bsf` finds the first free slot in a bitmap: page allocators, file-system
;;;       block maps, and the ready-queue of every operating system scheduler do
;;;       exactly this.
;;;     * `x & -x` isolates the lowest set bit as a VALUE, where `bsf` gives its
;;;       POSITION. Both are useful, and the pair is worth remembering together.
;;;
;;;   THE RELATED INSTRUCTIONS: `popcnt` counts how many bits are set (see
;;;   countones.asm in this folder, which does it the hard way and gets it
;;;   wrong), and `bt`/`bts`/`btr`/`btc` test and modify a single bit by index
;;;   (see onbit.asm).
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   `main` has no `ret`, so running it is unreliable. To watch what happens:
;;;   ./asm "ps_code/2/bsf.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/2/bsf.asm"
;;;
;;;   Useful session:
;;;     si                        mov rbx, 0x5566
;;;     p/t $rbx                  the value in BINARY -- count the positions
;;;     si                        bsf rax, rbx
;;;     p $rax                    1  -- the lowest set bit
;;;     si                        bsr rcx, rbx
;;;     p $rcx                    14 -- the highest set bit
;;;
;;;   Now reproduce the zero-input trap without editing the file:
;;;     break bsf.asm:NN          NN on the `bsf rax, rbx` line
;;;     c
;;;     set $rbx = 0
;;;     si
;;;     info registers eflags     ZF is SET -- that is the "no bits" signal
;;;     p $rax                    whatever was there before; NOT a valid answer
;;;
;;;   And check the log2 interpretation:
;;;     set $rbx = 1000
;;;     # step the bsr
;;;     p $rcx                    9, and 2^9 = 512 <= 1000 < 1024 = 2^10
;;;     p/x $rbx & -$rbx          the lowest set bit as a VALUE, not a position
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing moves on the stack. The transferable lesson is about a DIFFERENT
;;;   kind of contract: an instruction whose output is only valid when a flag
;;;   says so.
;;;
;;;   You have already met the same shape in three other places in this course:
;;;     * `scanf` returns how many items it converted -- code-0023.asm checks
;;;       `cmp rax, 1` after every call and jumps to .usage if it fails.
;;;     * a Linux system call returns a NEGATIVE value for an error --
;;;       code-0022.asm follows every `syscall` with `cmp rax, 0 / jl`.
;;;     * `malloc` returns NULL when it fails -- code-0021.asm does NOT check,
;;;       which is a latent bug in that file.
;;;   `bsf`/`bsr` are the same idea pushed down into the hardware: the result
;;;   register is meaningless unless ZF is clear. Checking the status BEFORE
;;;   using the value is a habit, not a special case, and it applies from single
;;;   instructions all the way up to library calls.
;;;
;;;   As everywhere in this folder, rbx is CALLEE-SAVED and is being clobbered
;;;   without a push, and the return address sits untouched at [rsp]:
;;;       break main
;;;       info symbol *(long*)$rsp
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

;;; ----------------------------------------------------------------------------
;;; main -- find the lowest and highest set bits of a constant.
;;;   Receives : nothing
;;;   Returns  : rax = 1 (lowest set bit), rcx = 14 (highest) -- but no `ret`
;;;   Clobbers : rax, rcx, and rbx (which is CALLEE-SAVED and is not preserved)
;;; ----------------------------------------------------------------------------
main:
    mov rbx, 0x5566                     ; the value to scan.
                                        ;   0x5566 = 0101 0101 0110 0110 in binary,
                                        ;   so the set bits are at positions
                                        ;   1, 2, 5, 6, 8, 10, 12, 14.
    bsf rax, rbx                        ; Bit Scan Forward: rax := the index of the
                                        ;   LOWEST set bit, counting from bit 0 at the
                                        ;   right. Here 1.
                                        ;   IF rbx WERE ZERO, rax would be UNDEFINED
                                        ;   and ZF would be set -- always test ZF
                                        ;   before trusting the result.
    bsr rcx, rbx                        ; Bit Scan Reverse: rcx := the index of the
                                        ;   HIGHEST set bit. Here 14 -- which is also
                                        ;   floor(log2(0x5566)).
                                        ;   Same zero-input caveat.
   nop                                  ; the end -- AND NO `ret`.
