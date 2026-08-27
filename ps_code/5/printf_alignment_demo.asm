;;; ============================================================================
;;; printf_alignment_demo.asm -- keeping the stack 16-byte aligned across a push
;;; Practice session 5                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Adds 10 and 20 and prints "The sum of 10 and 20 is 30". The arithmetic is
;;;   trivial; the file is about the four lines around the printf call.
;;;   (Verified: prints correctly, exit status 0.)
;;;
;;;   THE RULE. The System V AMD64 ABI requires that rsp be a MULTIPLE OF 16 at
;;;   the moment you execute `call`. Equivalently -- and this is the form that is
;;;   easier to check in gdb -- rsp is 8 mod 16 at the callee's FIRST
;;;   instruction, because the `call` itself pushed eight bytes.
;;;
;;;   WHY IT MATTERS. The C library's own routines use SSE instructions such as
;;;   `movaps` on stack memory, and those instructions FAULT on a misaligned
;;;   address rather than merely running slowly. A misaligned call to printf does
;;;   not print badly -- it segfaults, somewhere deep inside the library, with a
;;;   backtrace that points at code you did not write. It is one of the most
;;;   baffling bugs in assembly programming until you know to look for it.
;;;
;;;   THE ARITHMETIC IN THIS FILE, verified in gdb:
;;;       at main's first instruction   rsp % 16 == 8    (call main pushed 8)
;;;       after `push rbp`              rsp % 16 == 0
;;;       after `push r12`              rsp % 16 == 8    <- now BROKEN
;;;       after `sub rsp, 8`            rsp % 16 == 0    <- repaired
;;;       at printf's first instruction rsp % 16 == 8    <- correct
;;;   Then `add rsp, 8` and `pop r12` undo the two adjustments in reverse order.
;;;
;;;   *** THE COMMENT IN THE ORIGINAL IS WRONG, THOUGH THE CODE IS RIGHT. *** It
;;;   says "at entry to main rsp is aligned to 16 bit (rsp%16=0)". It is not --
;;;   it is 8, because `call main` pushed a return address. Check it yourself:
;;;       break main
;;;       print $rsp        ends in ...a8, and 0xa8 % 16 = 8
;;;   Work the sequence through starting from 0 instead of 8 and you will find
;;;   the `sub rsp, 8` would MIS-align rather than repair. The code compensates
;;;   correctly; the reasoning written next to it does not. Worth knowing, because
;;;   the right premise is what lets you get the next case right.
;;;
;;;   AN ALTERNATIVE THAT NEEDS NO ARITHMETIC AT ALL is what every lecture file
;;;   does:
;;;       and rsp, -16
;;;   -16 is 0xFFFF...FFF0, so this clears rsp's low four bits, rounding it DOWN
;;;   to a multiple of 16 regardless of what came before. It works whatever you
;;;   have pushed, it cannot be got wrong by miscounting, and the epilogue's
;;;   `mov rsp, rbp` cleans it up. The cost is that you must have a frame pointer
;;;   to restore rsp from -- which you do.
;;;
;;;   WHY r12 IS PUSHED IN THE FIRST PLACE. The sum has to survive the setup for
;;;   printf, and rax is CALLER-saved. r12 is CALLEE-saved, so printf is obliged
;;;   to hand it back unchanged -- but for the same reason THIS function is
;;;   obliged to hand it back to ITS caller unchanged, hence the push and pop.
;;;   That is the trade: callee-saved registers are safe across calls, at the
;;;   price of two instructions and eight bytes of stack. Compare func_demo.asm,
;;;   which keeps the result in rax and gets away with it only because nothing is
;;;   called in between.
;;;
;;;   `mov ecx, r12d` uses the 32-bit names because `%d` prints an int. Writing a
;;;   32-bit register also zeroes the upper 32 bits, so no junk can leak through.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/5/printf_alignment_demo.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is the file to check alignment in
;;;   ./debug "ps_code/5/printf_alignment_demo.asm"
;;;
;;;   THE session for this file -- verify every step of the arithmetic:
;;;     break main
;;;     c
;;;     p $rsp % 16               8, NOT 0 -- the original comment is wrong
;;;     si                        push rbp
;;;     p $rsp % 16               0
;;;     break printf_alignment_demo.asm:NN    NN on the `push r12` line
;;;     c
;;;     si
;;;     p $rsp % 16               8 -- alignment is now broken
;;;     # ...step on to the `sub rsp, 8`
;;;     si
;;;     p $rsp % 16               0 -- repaired
;;;     break printf
;;;     c
;;;     p $rsp % 16               8 -- exactly what the ABI promises printf
;;;
;;;   NOW BREAK IT DELIBERATELY, which is the most useful experiment in the file:
;;;     ./debug "ps_code/5/printf_alignment_demo.asm"
;;;     break printf
;;;     c
;;;     set $rsp = $rsp - 8       misalign the stack under printf's feet
;;;     c
;;;   Depending on which code path inside the library gets reached, you will see
;;;   it survive, misprint, or crash in a function you have never heard of. That
;;;   unpredictability is exactly why the rule is worth obeying mechanically
;;;   rather than case by case.
;;;
;;;   And confirm r12 really is preserved by printf:
;;;     break printf
;;;     c
;;;     p $r12                    30
;;;     finish
;;;     p $r12                    30 -- unchanged, as callee-saved promises
;;;     p $rax                    printf's character count: rax was NOT preserved
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE WHOLE FILE IS A STACK LESSON, so here is the summary worth memorising.
;;;
;;;   Two obligations sit on every function you write, and they are independent:
;;;
;;;     1. ALIGNMENT. rsp must be 0 mod 16 at every `call`. You can satisfy this
;;;        by counting pushes (as here) or by `and rsp, -16` (as the lecture
;;;        files do). The second is harder to get wrong.
;;;
;;;     2. REGISTER PRESERVATION. rbx, rbp, r12-r15 must come back unchanged.
;;;        Everything else -- rax, rcx, rdx, rsi, rdi, r8-r11, and every xmm
;;;        register -- may be destroyed by any call.
;;;
;;;   This file discharges both, and the four instructions that do it are
;;;   `push r12` / `sub rsp, 8` ... `add rsp, 8` / `pop r12`. Notice they UNDO IN
;;;   REVERSE ORDER. That is not a stylistic choice: the stack is last-in
;;;   first-out, so the adjustment made last must be undone first, or rsp ends up
;;;   pointing at the wrong thing. The same reversal governs every prologue and
;;;   epilogue pair in the course, and it is why code-0007a.asm has to push the
;;;   three chunks of its string in reverse order.
;;;
;;;   One last thing to look at, because it makes the invariant concrete:
;;;       break printf
;;;       c
;;;       x/1gx $rsp                  the return address printf will use
;;;       info symbol *(long*)$rsp    a line in YOUR main
;;;       x/4gx $rsp                  and just above it: your r12, your rbp
;;;   Alignment padding, saved registers, and the return address all live in the
;;;   same eight-byte-granular region, and keeping track of how many of each you
;;;   have put there IS the discipline of writing assembly.
;;; ============================================================================

section .data                           ; initialised, writable data
  msg db "The sum of %d and %d is %d", 10, 0
                                        ; printf format: three 32-bit ints, then a
                                        ;   newline (10) and the NUL terminator (0)

section .text                           ; the executable-code section
global main                             ; export `main` for the C library start-up
extern printf                           ; supplied by the C library

;;; ----------------------------------------------------------------------------
;;; add2 -- return the sum of two long arguments.
;;;   C signature : long add2(long a, long b)
;;;   Receives    : rdi = a, rsi = b
;;;   Returns     : rax = a + b
;;;   Clobbers    : rax only
;;;   A LEAF FUNCTION: no locals, no calls, so no prologue and no frame. The only
;;;   stack it uses is the 8-byte return address `call` pushed.
;;; ----------------------------------------------------------------------------
add2:
  mov rax, rdi                          ; rax := a -- seed the result register
  add rax, rsi                          ; rax := a + b
  ret                                   ;ret rax
                                        ;   pops the return address; the ABI says the
                                        ;   answer goes in rax, and it is already there

;---------------------------------------------
;  int main (void)                           ;
; calling add2                               ;
; calling printf with correct stack alignment;
;-------------------------------------------
;;; ----------------------------------------------------------------------------
;;; main -- call add2, then call printf with the stack correctly aligned.
;;;   Receives : nothing
;;;   Returns  : rax = 0
;;;   Clobbers : rax, rdi, rsi, rdx, rcx -- and r12, which is CALLEE-SAVED and is
;;;              therefore pushed and popped
;;;   Stack, in order: return address (from call main), saved rbp, saved r12,
;;;              8 bytes of alignment padding. The padding is what makes rsp a
;;;              multiple of 16 at the `call printf`.
;;; ----------------------------------------------------------------------------
main:
    push rbp                            ; prologue: save the caller's frame pointer.
                                        ;   rsp goes from 8 mod 16 to 0 mod 16.
        mov rbp, rsp                    ; anchor the frame
        mov rdi, 10                     ; add2's argument 1
        mov rsi, 20                     ; argument 2

        call add2                       ; rax = 30
                                        ;save r12 because it is a callee saved register
        push r12                        ; r12 must be handed back to OUR caller unchanged,
                                        ;   so save it before using it. This also takes
                                        ;   rsp from 0 mod 16 to 8 mod 16 -- ALIGNMENT
                                        ;   IS NOW BROKEN, and the `sub rsp, 8` below
                                        ;   is what repairs it.
                                        ;save result for printf
        mov r12 , rax                   ; r12 = 10+20
                                        ;   park the sum in a CALLEE-SAVED register, so
                                        ;   printf cannot destroy it. rax would not
                                        ;   survive -- it is caller-saved.

                                        ;------------------------------------------------------;
                                        ;   prepare arguments for printf                       ;
                                        ;   printf ('The sum of %d and %d is %d\n", 10, 20, 30);
                                        ;-------------------------------------------------------;

        mov rdi, msg                    ; rdi points to the string msg
                                        ;   printf argument 1
        mov esi, 10                     ; first  %d
                                        ;   the 32-BIT name, because %d prints an int.
                                        ;   Writing esi also zeroes the top half of rsi.
        mov edx, 20                     ; second %d
        mov ecx, r12d                   ; result %d the sum is stored at the lower 32 bits of r12 this is why we use r12d
                                        ;   argument 4 goes in rcx

        xor eax, eax                    ; THE VARIADIC RULE: rax = the number of VECTOR
                                        ;   registers carrying arguments. No floats, so 0.

                                        ;----------------------------------------------------------;
                                        ; stack alignment before printf command                    ;
                                        ;  at entry to main rsp is aligned to 16 bit (rsp%16=0)    ;
                                        ; but we pushed r12 so we need to realign the stack
                                        ;----------------------------------------------------------;
                                        ; NOTE: the premise in that comment is WRONG --
                                        ;   at entry to main rsp % 16 is 8, not 0,
                                        ;   because `call main` pushed a return address.
                                        ;   The CODE is right; check it in gdb with
                                        ;   `break main` then `p $rsp % 16`.
        sub rsp, 8                      ; add 8 bytes of padding, taking rsp from
                                        ;   8 mod 16 back to 0 mod 16 -- which is what
                                        ;   the ABI requires at a `call`.
        call printf
        add rsp, 8                      ; remove the padding again. Note the adjustments
                                        ;   are undone in REVERSE ORDER: padding first,
                                        ;   then r12 -- the stack is last-in first-out.
                                        ; retreive the content of rsp after retrurn from printf
        pop r12                         ; restore the caller's r12, discharging the
                                        ;   callee-saved obligation
                                        ;----------------------------------------------------------;
                                        ;   return 0 from main                                     ;
                                        ;----------------------------------------------------------;
        mov eax, 0                      ; main's return value: 0 = success. (The 32-bit
                                        ;   name zeroes all of rax.)
        mov rsp, rbp                    ; epilogue: restore rsp from the anchor
        pop rbp                         ; restore the caller's frame pointer
        ret                             ; pop the return address into rip
