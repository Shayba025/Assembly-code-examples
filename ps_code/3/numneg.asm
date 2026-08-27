;;; ============================================================================
;;; numneg.asm -- counting the negative numbers in an array of 16-bit words
;;; Practice session 3                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Walks ten 16-bit values and counts how many are negative, storing the
;;;   answer in `count`. It prints nothing, but it does have a `ret`, so it exits
;;;   cleanly.
;;;   (Verified: rbx = 6 and count = 6.)
;;;
;;;   THE IDEA: A NUMBER IS NEGATIVE EXACTLY WHEN ITS TOP BIT IS SET. In two's
;;;   complement -- which is how every signed integer on this machine is stored
;;;   -- the most significant bit IS the sign. For a 16-bit word that is bit 15,
;;;   whose mask is 0x8000. So
;;;       and ax, 8000h
;;;       jz  not_negative
;;;   is the whole test. No comparison with zero, no subtraction: just look at
;;;   one bit.
;;;
;;;   CHECK IT AGAINST THE DATA. Take the top hex digit of each value -- if it is
;;;   8 or above, bit 15 is set:
;;;       9865  -> 9  negative
;;;       ab54  -> a  negative
;;;       12a6  -> 1  positive
;;;       6875  -> 6  positive
;;;       8abd  -> 8  negative
;;;       dfdf  -> d  negative
;;;       eacf  -> e  negative
;;;       4fdd  -> 4  positive
;;;       5eee  -> 5  positive
;;;       cbd4  -> c  negative
;;;   Six negatives, which is what the program produces. Being able to read
;;;   signedness straight off the leading hex digit is a genuinely useful habit.
;;;
;;;   THE ALTERNATIVES, all equivalent here:
;;;       and ax, 8000h  / jz         what this file does -- but it DESTROYS ax
;;;       test ax, ax    / jns        `test` keeps only the flags, so ax survives,
;;;                                   and `jns` reads the sign flag directly
;;;       cmp ax, 0      / jge        the obvious spelling, one byte longer
;;;       bt  ax, 15     / jnc        explicit bit test (see onbit.asm)
;;;   `test ax, ax / js` is what a compiler would emit. The version here works
;;;   because ax is reloaded from memory at the top of every iteration, so
;;;   clobbering it costs nothing.
;;;
;;;   `n equ 10` is an ASSEMBLE-TIME constant -- pure text substitution, no
;;;   memory, no instruction. Note it is NOT kept in step with the `dw` list
;;;   below: add an eleventh value and you must remember to change `n` as well.
;;;   Compare code-0026.asm in "lectures code ", which makes the array measure
;;;   itself with `dq ($ - sample) >> 3` and cannot drift.
;;;
;;;   A SIZE MISMATCH WORTH SPOTTING: `count resb 1` reserves ONE BYTE, and the
;;;   program stores `bl` -- the low byte of rbx -- into it. Consistent, but it
;;;   silently caps the count at 255. With `n` this small it does not matter; in
;;;   general, making the counter's width match the maximum possible count is
;;;   part of the design.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/3/numneg.asm" ; echo "exit status = $?"
;;;
;;;   It prints nothing, and it happens to exit 0 -- but only by accident. Unlike
;;;   array1.asm and array2.asm, this file never sets rax before its `ret`, so
;;;   the shell receives the low byte of whatever was left in rax. The last
;;;   `and ax, 8000h` left 0x8000 there, whose low byte is 0. Change the data and
;;;   the status changes with it. Adding `xor eax, eax` before the `ret` is the
;;;   fix.
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/3/numneg.asm"
;;;
;;;   Useful session:
;;;     x/10xh &vec               the ten values, in hex -- read the leading digits
;;;     x/10dh &vec               the same values as SIGNED decimals: the negatives
;;;                               are obvious now
;;;     x/10uh &vec               and as UNSIGNED -- same bits, different meaning.
;;;                               This is the single most useful demonstration of
;;;                               what "signed" actually means.
;;;     break numneg.asm:31       the `ret` line
;;;     c
;;;     p $rbx                    6
;;;     x/1xb &count              0x06
;;;
;;;   Watch the sign test decide, one element at a time:
;;;     break numneg.asm:22       the `and ax, 8000h` line
;;;     c
;;;     p/x $ax                   the current value
;;;     p/d $ax                   ...as a signed number
;;;     si                        the AND
;;;     info registers eflags     ZF set means the top bit was CLEAR, i.e. positive
;;;     p $rbx                    the running count
;;;     c                         next element
;;;
;;;   And see two's complement for yourself:
;;;     p/d (short)0x9865         -26523
;;;     p/u (unsigned short)0x9865  38997
;;;     p/t (short)0x9865         the bit pattern -- note the leading 1
;;;   One pattern of bits, two interpretations. The CPU stores only the bits; the
;;;   INSTRUCTION you choose (jl versus jb, shr versus sar, mul versus imul) is
;;;   what decides which meaning applies.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing happens on it: no prologue, no locals, no calls, and `p $rsp` is
;;;   identical at `main` and at the `ret`. The return address the C library
;;;   pushed sits untouched at [rsp] the whole time, and the `ret` pops it:
;;;       break main
;;;       x/1gx $rsp
;;;       info symbol *(long*)$rsp
;;;       break numneg.asm:31
;;;       c
;;;       si                        the ret
;;;       bt                        you are back in the C library
;;;
;;;   THE ONE ABI POINT THIS FILE ACTUALLY BREAKS is worth dwelling on, because
;;;   it is invisible and it is a real bug. rbx is CALLEE-SAVED: a function that
;;;   uses it MUST give it back unchanged. This one uses rbx as its counter and
;;;   never saves it, then returns. Watch it:
;;;       break main
;;;       p/x $rbx                  whatever the C library left there
;;;       break numneg.asm:31
;;;       c
;;;       p/x $rbx                  6 -- a promise has been broken
;;;   Here nothing downstream cares, so the program survives. In a larger program
;;;   this is exactly how you produce a crash in a function that looks innocent.
;;;   The fix is two instructions:
;;;       main:  push rbx     ...     pop rbx  ;  ret
;;;   and that push is the entire reason stack frames exist for callee-saved
;;;   registers. Callee-saved on x86-64: rbx, rbp, r12, r13, r14, r15, rsp.
;;;   Everything else is scratch.
;;; ============================================================================

global main                             ; export `main` for the C library start-up



n equ 10                                ; number of numbers in vec
                                        ;   `equ` = an ASSEMBLE-TIME constant: pure
                                        ;   text substitution, no memory, no code. It
                                        ;   must be kept in step with the list below
                                        ;   by hand -- see the header.

section .data                           ; initialised, writable data
   vec dw 9865h, 0ab54h,  12a6h, 6875h, 8abdh, 0dfdfh, 0eacfh, 4fddh, 5eeeh, 0cbd4h
                                        ; ten 16-bit values. `dw` = define word.
                                        ;   Constants beginning with a letter need a
                                        ;   leading 0 (`0ab54h`), or NASM would read
                                        ;   them as label names.
                                        ;   Six of these have their top bit set.

section .bss                            ; zero-filled at load time, no file space
  count  resb 1                         ; ONE byte for the answer -- see the size note
                                        ;   in the header

section .text                           ; the executable-code section

;;; ----------------------------------------------------------------------------
;;; main -- count how many of the ten words are negative.
;;;   C equivalent : unsigned char c = 0;
;;;                  for (i = 0; i < n; i++) if (vec[i] & 0x8000) c++;
;;;                  count = c;
;;;   Receives : nothing
;;;   Returns  : rax is never set, so the exit status is junk -- see the header
;;;   Registers: rdi = a walking pointer into vec, stepping by 2
;;;              rcx = the countdown, because `loop` insists on rcx
;;;              ax  = the current element, destroyed by the AND each pass
;;;              rbx = the running count -- CALLEE-SAVED, and not preserved
;;;   No prologue and no locals: nothing is called, so the stack is never touched.
;;; ----------------------------------------------------------------------------
main:
   lea rdi, [vec]                       ; Load Effective Address: rdi := &vec, the
                                        ;   ADDRESS of the first element
   mov  rcx, n                          ; the element count -- and the loop counter,
                                        ;   which must be rcx for `loop`. `n` was
                                        ;   replaced by 10 before assembly began.
    xor eax, eax                        ; clear the whole of rax. The 32-bit name zeroes
                                        ;   the upper 32 bits for free and encodes one
                                        ;   byte shorter than `xor rax, rax`.
    xor rbx, rbx                        ; the running count starts at zero
  loop1:
      mov ax, [rdi]                     ; load the current element. A 16-BIT load, so
                                        ;   only the low word of rax is written.
     and ax, 8000h                      ; MASK OFF EVERYTHING BUT THE SIGN BIT. 0x8000
                                        ;   is bit 15, which in two's complement IS the
                                        ;   sign. The result is either 0x8000 or 0, and
                                        ;   the flags record which.
                                        ;   (This destroys ax -- fine here, since it is
                                        ;   reloaded next pass. `test ax, ax / jns`
                                        ;   would leave it intact.)
     jz cont                            ; ZF set => the sign bit was clear => the value
                                        ;   is non-negative => skip the increment
     inc rbx                            ; count one negative
cont:
     add rdi, 2                         ; advance by TWO bytes, the size of one word
     loop loop1                         ; decrement rcx and jump back while non-zero
                                        ;lea rdi, [num]
                                        ; (commented out in the original -- a leftover
                                        ;   from an earlier version)
     lea rdi, [count]                   ; rdi := &count, the destination
     mov byte [rdi], bl                 ; store the low BYTE of the count. `bl` matches
                                        ;   the one-byte `resb 1` reservation, so the
                                        ;   widths agree -- but the count is silently
                                        ;   capped at 255.
     ret                                ; pop the return address into rip.
                                        ;   NOTE: rax is never set to 0 first, so the
                                        ;   process exit status is whatever happened to
                                        ;   be in rax. Compare array1.asm, which ends
                                        ;   with `xor eax, eax` then `ret`.
