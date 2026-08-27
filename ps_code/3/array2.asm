;;; ============================================================================
;;; array2.asm -- the same loop with 16-bit elements, and a different recurrence
;;; Practice session 3                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Fills the first FIVE words of a six-word array with 4, 9, 19, 39, 79. The
;;;   sixth word keeps its initial 0xAAAA.
;;;   (Verified: 0x0004 0x0009 0x0013 0x0027 0x004F 0xAAAA.)
;;;
;;;   READ IT NEXT TO array1.asm, which is the same program with byte-sized
;;;   elements. Every difference between the two files comes from the element
;;;   size, and that is the point of the pair:
;;;
;;;       array1.asm (bytes)              array2.asm (words)
;;;       ---------------------------     ---------------------------
;;;       array db 12 dup (55h)           array dw 6 dup (0aaaah)
;;;       mov al,  [start]                mov ax,  [start]
;;;       mov byte [rdi], al              mov word [rdi], ax
;;;       inc rdi           (step 1)      add rdi, 2        (step 2)
;;;
;;;   THE STEP MUST MATCH THE ELEMENT SIZE. `inc rdi` on a word array would land
;;;   you halfway into an element and write the low byte of one and the high byte
;;;   of the next. This is the same idea as the `8*index` scaling in the lecture
;;;   files, where quadwords make the multiplier 8.
;;;
;;;   THE RECURRENCE. The body stores ax and then computes the next value with
;;;       shl ax, 1     ; ax := 2*ax
;;;       inc ax        ; ax := 2*ax + 1
;;;   so the sequence is 4, 9, 19, 39, 79, ... -- each term is one more than
;;;   twice the previous. In binary that is very pretty: the value gains a 1 bit
;;;   at the bottom each time.
;;;       4  = 0000 0100
;;;       9  = 0000 1001
;;;       19 = 0001 0011
;;;       39 = 0010 0111
;;;       79 = 0100 1111
;;;   `shl` (SHift Left) by k multiplies by 2^k and is the cheap way to double.
;;;   Its right-hand counterparts are `shr` (logical, zero-filled) and `sar`
;;;   (arithmetic, sign-filled) -- see collatz.asm in this folder for `shr`.
;;;
;;;   WHY ONLY FIVE OF THE SIX ELEMENTS ARE WRITTEN: `mov rcx, 5` while the
;;;   array holds six. Deliberate or not, it makes the file a useful experiment:
;;;   the untouched sixth word still reads 0xAAAA, which lets you SEE the
;;;   boundary of what the loop actually touched. Change 5 to 6 and watch it
;;;   disappear; change it to 7 and you are writing past the end of the array,
;;;   exactly the off-by-one that code-0020.asm in "lectures code " commits for
;;;   real.
;;;
;;;   `xor eax, eax` before `mov ax, [start]` clears the register, because a
;;;   16-bit write preserves the upper 48 bits (see notal.asm in ps_code/2).
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/3/array2.asm" ; echo "exit status = $?"
;;;
;;;   It prints nothing and exits 0. The result is in memory, so use gdb.
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/3/array2.asm"
;;;
;;;   Useful session:
;;;     x/6xh &array              all 0xaaaa -- the initial fill
;;;     x/1xh &start              0x0004, the seed
;;;     break array2.asm:20       the `ret` line
;;;     c
;;;     x/6xh &array              0004 0009 0013 0027 004f aaaa
;;;     x/6dh &array              the same, in decimal: 4 9 19 39 79 -21846
;;;
;;;   Watch the recurrence one step at a time:
;;;     break array2.asm:15       the `shl ax, 1` line
;;;     c
;;;     p/d $ax                   the value just stored
;;;     p/t $ax                   ...in binary
;;;     si si                     shl then inc
;;;     p/t $ax                   one more 1-bit at the bottom
;;;     c                         next iteration
;;;
;;;   And see the pointer stepping correctly:
;;;     break array2.asm:14       the `mov word [rdi], ax` line
;;;     c
;;;     p ($rdi - (char*)&array)      0 -- the byte offset
;;;     c
;;;     p ($rdi - (char*)&array)      2 -- one WORD along, not one byte
;;;     p ($rdi - (short*)&array)     ...or ask gdb to scale it for you
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Like array1.asm, this function has NO prologue and NO epilogue -- no
;;;   `push rbp`, no `sub rsp` -- and it is completely correct, because it has no
;;;   local variables and calls nothing. Confirm it:
;;;       break main
;;;       p $rsp
;;;       break array2.asm:20
;;;       c
;;;       p $rsp                    identical
;;;       x/1gx $rsp                the return address, untouched all along
;;;       si                        the `ret`
;;;       bt                        you are back in the C library
;;;
;;;   THE QUESTION WORTH ASKING is when you would need a frame here. Answer: as
;;;   soon as you call anything. Add a `call printf` inside the loop to display
;;;   each value and three things break at once --
;;;       * rcx, rdi and rax are all CALLER-SAVED, so printf may destroy them;
;;;       * the stack must be 16-byte aligned at the `call`, which nothing here
;;;         guarantees;
;;;       * you would want somewhere safe to keep the loop state.
;;;   The answer to all three is the prologue you have been writing since
;;;   code-0001.asm: `push rbp / mov rbp, rsp / and rsp, -16`, plus either
;;;   push/pop around the call (code-0002.asm) or stack locals (code-0018.asm).
;;;   Try adding the printf and fixing the fallout -- it is the single most
;;;   useful exercise in this folder.
;;;
;;;   And as in array1.asm, note that `array` lives in .data, so it outlives any
;;;   frame. A local array would vanish at the `ret`.
;;; ============================================================================

global main                             ; export `main` for the C library start-up

section .data                           ; initialised, writable data
   start dw 4                           ; the seed value. `dw` = define WORD, two bytes.
   array dw 6 dup (0aaaah)              ; six words, each initialised to 0xAAAA.
                                        ;   The leading 0 is required: NASM needs a
                                        ;   hex literal to start with a digit, so
                                        ;   `aaaah` would be read as a label name.
                                        ;   Only five of the six get overwritten --
                                        ;   see the header.
section .text                           ; the executable-code section

;;; ----------------------------------------------------------------------------
;;; main -- fill five words with the recurrence x := 2x + 1, starting from 4.
;;;   C equivalent : short x = start;
;;;                  for (i = 0; i < 5; i++) { array[i] = x; x = 2*x + 1; }
;;;   Receives : nothing
;;;   Returns  : rax = 0
;;;   Registers: rdi = a walking pointer into the array, stepping by 2
;;;              rcx = the countdown, because `loop` insists on rcx
;;;              ax  = the current value of the recurrence
;;;   No prologue and no epilogue -- no locals, no calls, so the stack is never
;;;   touched. See the call-stack notes above.
;;; ----------------------------------------------------------------------------
main:
     lea rdi, [array]                   ; Load Effective Address: rdi := &array, the
                                        ;   ADDRESS of the first element (not its
                                        ;   contents -- compare `mov rdi, [array]`)
     mov rcx, 5                         ; five iterations, though the array holds six
                                        ;   elements. rcx is not a free choice: `loop`
                                        ;   uses it.
     xor eax, eax                       ; clear the whole register first, because the
                                        ;   16-bit load below preserves the upper bits
     mov ax, [start]                    ; ax := 4. A 16-BIT load: only the low word of
                                        ;   rax is written.
loop1:
      mov word [rdi], ax                ; store two bytes at the current position. The
                                        ;   `word` keyword is REQUIRED -- `[rdi]` alone
                                        ;   does not say how wide the access is.
      shl ax, 1                         ; SHift Left by one: ax := 2*ax. Shifting left
                                        ;   by k multiplies by 2^k, and is far cheaper
                                        ;   than a multiply instruction.
      inc ax                            ; ax := 2*ax + 1. Together with the shift this
                                        ;   is the recurrence 4, 9, 19, 39, 79 -- one
                                        ;   extra 1-bit at the bottom each time.
      add rdi, 2                        ; advance the pointer by TWO, because the
                                        ;   elements are two bytes each. Compare
                                        ;   array1.asm's `inc rdi` for byte elements.
      loop loop1                        ; decrement rcx and jump back while non-zero
      xor eax, eax                      ; the value `main` returns: 0 = success
      ret                               ; pop the return address into rip
