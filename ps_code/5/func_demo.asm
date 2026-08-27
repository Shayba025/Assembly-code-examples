;;; ============================================================================
;;; func_demo.asm -- calling your own function, and then calling printf
;;; Practice session 5                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Calls `add3(10, 20, 30)` and prints "add3(10,20,30)=60". It contains the
;;;   same `add3` as add3.asm in this folder, plus a `main` that exercises it --
;;;   so unlike add3.asm it links and runs on its own.
;;;   (Verified: prints `add3(10,20,30)=60`. The exit status is 18, printf's
;;;   character count: `main` never resets rax before its `ret`.)
;;;
;;;   THE FILE IS REALLY ABOUT ONE THING: THE ARGUMENT REGISTERS, and how they
;;;   are reused between two different calls in a row.
;;;
;;;       for add3         rdi = 10, rsi = 20, rdx = 30
;;;       for printf       rdi = fmt, esi = 10, edx = 20, ecx = 30, r8d = result
;;;
;;;   Six integer arguments fit in registers, in this fixed order:
;;;       rdi, rsi, rdx, rcx, r8, r9
;;;   and anything beyond the sixth goes on the stack. printf here takes five --
;;;   the format string plus four numbers -- so all five fit.
;;;
;;;   WHY THE 32-BIT NAMES (esi, edx, ecx, r8d, eax)? Because `%d` prints a
;;;   32-bit `int`. Writing to a 32-bit register also ZEROES the upper 32 bits of
;;;   the 64-bit one (see invert.asm in ps_code/2), so `mov esi, 10` leaves rsi
;;;   holding exactly 10 with no junk above it -- and the instruction encodes one
;;;   byte shorter than `mov rsi, 10`. Compilers do this constantly.
;;;
;;;   `xor eax, eax` BEFORE printf IS NOT OPTIONAL. For a VARIADIC function, rax
;;;   must hold the number of VECTOR (xmm) registers carrying arguments. There
;;;   are no floating-point arguments here, so it is 0. Get it wrong and printf
;;;   may read xmm registers that contain nothing useful, print garbage, or
;;;   crash. The professor's comment calls it "demand for printf", which is
;;;   exactly right.
;;;
;;;   NOTE WHERE THE RESULT GOES. `call add3` leaves the sum in rax, and the very
;;;   next thing that happens is `mov rdi, fmt` -- which does NOT disturb rax --
;;;   followed eventually by `mov r8d, eax`. The result survives only because
;;;   nothing in between touches rax. Add one more `call` in the middle and it
;;;   would be destroyed, because rax is CALLER-saved. printf_alignment_demo.asm
;;;   in this folder handles the same situation the safe way, by parking the
;;;   result in the callee-saved r12.
;;;
;;;   A LATENT BUG WORTH SPOTTING: `main` sets up a frame with `push rbp` /
;;;   `mov rbp, rsp` but never does `and rsp, -16`. It happens to work here --
;;;   at entry to main rsp is 8 mod 16, the `push rbp` makes it 0 mod 16, and the
;;;   `call printf` pushes 8 more, so printf sees exactly the 8 mod 16 the ABI
;;;   promises. But that is arithmetic you got right by luck rather than by
;;;   design. Push one extra register and it breaks -- which is precisely what
;;;   printf_alignment_demo.asm demonstrates, and fixes.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/5/func_demo.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/5/func_demo.asm"
;;;
;;;   Useful session:
;;;     break add3
;;;     c
;;;     info registers rdi rsi rdx     10, 20, 30
;;;     bt                             #0 add3, #1 main
;;;     finish
;;;     p $rax                         60
;;;     break printf
;;;     c
;;;     x/s $rdi                       the format string
;;;     info registers rsi rdx rcx r8  10, 20, 30, 60 -- the four %d values
;;;     p $rax                         0 -- the variadic vector-register count
;;;     p $rsp % 16                    8, which is what the ABI requires here
;;;
;;;   See the 32-bit trick zero the upper half:
;;;     break func_demo.asm:NN         NN on the `mov esi, 10` line
;;;     c
;;;     set $rsi = 0xFFFFFFFFFFFFFFFF  poison the whole register
;;;     si
;;;     p/x $rsi                       0xa -- the top half was cleared for free
;;;
;;;   And break the variadic rule on purpose, to see why it matters:
;;;     break func_demo.asm:NN         NN on the `xor eax, eax` line
;;;     c
;;;     si
;;;     set $rax = 8                   claim eight xmm registers are in use
;;;     c
;;;   printf now goes looking for floating-point arguments that were never
;;;   passed. Depending on what happens to be in those registers you get
;;;   nonsense or a crash -- and nothing warned you.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   TWO CALLS, TWO COMPLETELY DIFFERENT STACK COSTS, and comparing them is the
;;;   exercise:
;;;
;;;     * `call add3` costs 8 bytes -- just the return address. `add3` is a leaf
;;;       function with no frame. Break on it and `p $rsp` before and after
;;;       `finish` to confirm.
;;;     * `call printf` costs 8 bytes from your side too, but printf itself
;;;       builds a substantial frame. Break on printf, `bt`, and then `finish`
;;;       while watching `p $rsp` -- the library function allocates and frees a
;;;       good deal more than yours does.
;;;
;;;   Both are invisible to the caller, and that is the value of the convention:
;;;   `main` does not need to know or care how much stack a callee uses, only
;;;   that it gives rsp back where it found it. Check that promise directly:
;;;       break printf
;;;       c
;;;       p $rsp
;;;       finish
;;;       p $rsp                     8 higher -- exactly the return address gone,
;;;                                  and nothing else disturbed
;;;
;;;   THE ALIGNMENT ARITHMETIC IS WORTH DOING ONCE BY HAND, because it explains
;;;   `and rsp, -16` for good:
;;;       at the first instruction of main   rsp % 16 == 8   (call pushed 8)
;;;       after `push rbp`                   rsp % 16 == 0
;;;       at the first instruction of printf rsp % 16 == 8   (call pushed 8)
;;;   The ABI's rule is "rsp is a multiple of 16 immediately BEFORE the call",
;;;   which is the same as "8 mod 16 at the callee's first instruction". Verify
;;;   every step with `p $rsp % 16` and you will never guess again.
;;; ============================================================================

section .data                           ; initialised, writable data
  fmt db "add3(%d,%d,%d)=%d", 10, 0     ; printf format: four 32-bit ints, then a
                                        ;   newline (10) and the NUL terminator (0).
                                        ;   Double quotes do not expand escapes in
                                        ;   NASM, so \n and \0 are written as numbers.

section .text                           ; the executable-code section
global main                             ; export `main` for the C library start-up
extern printf                           ; supplied by the C library

;------------------------------
; long add3(long a, long b, long c)
; arguments: rdi=a, rsi=b , rdx=d
; returned value: rax
;----------------------------------
;;; ----------------------------------------------------------------------------
;;; add3 -- return the sum of three long arguments. (Identical to add3.asm.)
;;;   C signature : long add3(long a, long b, long c)
;;;   Receives    : rdi = a, rsi = b, rdx = c   (System V AMD64 ABI)
;;;   Returns     : rax = a + b + c
;;;   Clobbers    : rax only
;;;   Stack use   : just the 8-byte return address. A LEAF FUNCTION -- no locals,
;;;                 no calls, no callee-saved registers, therefore no frame.
;;; ----------------------------------------------------------------------------
add3:
   mov rax, rdi                         ; rax := a -- seed the result register
   add rax, rsi                         ; rax := a + b
   add rax, rdx                         ;rax = rdi+rsi+rdx
                                        ;   the ABI puts the return value in rax, and
                                        ;   it is already there
   ret                                  ; return the value of rax
                                        ;   pops the return address into rip

;-------------------------------------
; int main () demoonstrates calling to  add3
; from assembly
;------------------------------------------
;;; ----------------------------------------------------------------------------
;;; main -- call add3 and print the result.
;;;   Receives : nothing
;;;   Returns  : rax = printf's character count (18) -- never reset to 0
;;;   Clobbers : rax, rdi, rsi, rdx, rcx, r8
;;;   Builds a frame (push rbp / mov rbp, rsp) but does NOT do `and rsp, -16`.
;;;   The alignment happens to come out right anyway -- see the header, and see
;;;   printf_alignment_demo.asm for the case where it does not.
;;; ----------------------------------------------------------------------------
main:
  push rbp                              ; prologue: save the caller's frame pointer
                                        ;   (rbp is callee-saved). This also flips rsp
                                        ;   from 8 mod 16 to 0 mod 16.
  mov  rbp, rsp                         ; anchor the frame
                                        ;  prepare the arguments for add3  10, 20, 30
  mov rdi, 10                           ; add3's argument 1
  mov rsi, 20                           ; argument 2
  mov rdx, 30                           ; argument 3. The first six integer arguments
                                        ;   always go rdi, rsi, rdx, rcx, r8, r9.
  call add3                             ; rax = 10+20+30
                                        ;   pushes the return address and jumps

                                        ; prepare printf argumenrs
  mov rdi, fmt                          ;format string
                                        ;   printf argument 1. Note this does NOT
                                        ;   disturb rax, which still holds the sum.
  mov esi, 10                           ; first %d
                                        ;   the 32-BIT name, because %d prints an int.
                                        ;   Writing esi also zeroes the top half of rsi.
  mov edx, 20                           ;second %d
  mov ecx, 30                           ; third %d
                                        ;   argument 4 goes in rcx -- the fourth slot
  mov r8d , eax                         ; result
                                        ;   argument 5 goes in r8. eax still holds
                                        ;   add3's answer, because nothing in between
                                        ;   touched it -- see the header.
  xor eax, eax                          ;demand for printf
                                        ;   THE VARIADIC RULE: rax = the number of
                                        ;   VECTOR registers carrying arguments. No
                                        ;   floats here, so 0. This is mandatory.
  call printf

  mov rsp, rbp                          ; epilogue: discard anything this frame did
  pop rbp                               ; restore the caller's frame pointer
  ret                                   ; back to the C library. NOTE rax is not reset
                                        ;   first, so the exit status is printf's
                                        ;   character count.
