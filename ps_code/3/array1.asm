;;; ============================================================================
;;; array1.asm -- filling a byte array with consecutive values
;;; Practice session 3                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Fills a 12-byte array with 0x17, 0x18, 0x19, ... 0x22 -- twelve consecutive
;;;   values starting from the byte stored in `start`. It prints nothing, but it
;;;   DOES have a `ret`, so unlike the ps_code/1 and ps_code/2 exercises it exits
;;;   cleanly.
;;;   (Verified: the array reads 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22.)
;;;
;;;   THE FOUR IDEAS IN TWENTY LINES:
;;;
;;;   1. `lea rdi, [array]` -- Load Effective Address. It computes the address of
;;;      `array` and puts THE ADDRESS in rdi. Compare `mov rdi, [array]`, which
;;;      would load the CONTENTS. This is the single most confusing distinction
;;;      in assembly, and the brackets are the only thing that tells them apart:
;;;          lea rdi, [array]     rdi = &array        (a pointer)
;;;          mov rdi, [array]     rdi = *(long*)array (the data)
;;;          mov rdi, array       rdi = &array        (also a pointer, in NASM)
;;;      In this file `lea` and the bare `mov rdi, array` would do the same
;;;      thing. `lea` becomes essential when the address is COMPUTED -- see
;;;      code-0015.asm and code-0016.asm in "lectures code ", where it is used
;;;      for arithmetic rather than for addressing at all.
;;;
;;;   2. A WALKING POINTER. Instead of indexing `array[i]`, the loop keeps rdi
;;;      pointing at the current element and does `inc rdi` each pass. For bytes
;;;      the step is 1; array2.asm in this folder does the same with 16-bit
;;;      elements and steps by 2. THE STEP IS THE ELEMENT SIZE -- get it wrong
;;;      and you write into the middle of your data.
;;;
;;;   3. BYTE-SIZED OPERATIONS. `mov byte [rdi], al` stores ONE byte, and `inc
;;;      al` increments only the low 8 bits of rax. The `byte` keyword is
;;;      mandatory here: NASM cannot tell from `[rdi]` alone how wide the access
;;;      should be.
;;;
;;;   4. `xor eax, eax` BEFORE `mov al, [start]`. Writing to `al` preserves the
;;;      upper 56 bits (see notal.asm in ps_code/2), so the register is cleared
;;;      first to make sure nothing is left over. Note it is `xor eax, eax`, not
;;;      `xor rax, rax` -- a 32-bit write zeroes the upper 32 bits for free, so
;;;      the shorter encoding does the whole job.
;;;
;;;   `dup` IS UNUSUAL SYNTAX. `array db 12 dup (55h)` is MASM/TASM style,
;;;   supported by NASM 2.15 and later. The idiomatic NASM spelling is
;;;       array: times 12 db 0x55
;;;   and you will see `times` used that way in code-0020.asm. Both emit twelve
;;;   bytes of 0x55, which the program then overwrites -- so the 0x55 is only
;;;   ever visible if you break BEFORE the loop.
;;;
;;;   `loop` decrements rcx and jumps while it is non-zero. The counter must be
;;;   rcx, it tests AFTER decrementing (so rcx = 0 on entry means 2^64
;;;   iterations), and it leaves the flags alone.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/3/array1.asm" ; echo "exit status = $?"
;;;
;;;   It prints nothing and exits 0 -- `xor eax, eax` sets the return value just
;;;   before the `ret`. The interesting output is in memory, so use gdb.
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/3/array1.asm"
;;;
;;;   Useful session:
;;;     x/12xb &array             all 0x55 -- the initial `dup` fill
;;;     x/1xb &start              0x17, the seed
;;;     break array1.asm:19       the `ret` line
;;;     c
;;;     x/12xb &array             17 18 19 1a 1b 1c 1d 1e 1f 20 21 22
;;;
;;;   Watch one element being written:
;;;     break array1.asm:14       the `mov byte [rdi], al` line
;;;     c
;;;     p/x $rdi                  where we are about to write
;;;     p/x $al                   what we are about to write
;;;     p $rdi - (char*)&array    the index, computed from the pointer
;;;     si
;;;     x/12xb &array             one more byte has changed
;;;     c                         next element
;;;
;;;   And see why the `byte` keyword matters:
;;;     x/1xb $rdi                one byte
;;;     x/1xg $rdi                the same address read as EIGHT bytes
;;;   The address is identical; only the width differs. That width is exactly
;;;   what `byte`, `word`, `dword` and `qword` specify.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THIS IS THE FIRST FILE IN ps_code WITH A `ret`, so it is worth watching it
;;;   work. Everything in ps_code/1 and ps_code/2 walked off the end of `main`
;;;   and crashed. This one goes home properly:
;;;       break main
;;;       p $rsp                       note the value
;;;       x/1gx $rsp                   the return address the C library pushed
;;;       info symbol *(long*)$rsp     __libc_start_call_main, or similar
;;;       break array1.asm:19
;;;       c
;;;       p $rsp                       IDENTICAL -- the program never pushed
;;;                                    anything, so the return address is still
;;;                                    exactly where `call main` left it
;;;       si                           execute the `ret`
;;;       p $rsp                       8 higher, and rip is now in the C library
;;;       bt                           you are outside your own code
;;;
;;;   That is the whole mechanism: `call` pushed 8 bytes, `ret` popped them, and
;;;   because nothing in between disturbed rsp, no frame pointer was needed at
;;;   all. This function has NO prologue and NO epilogue -- no `push rbp`, no
;;;   `sub rsp` -- and it is perfectly correct, because it has no locals and
;;;   calls nothing. Compare code-0018.asm, which needs all of it.
;;;
;;;   The other thing to notice is where the DATA lives. `array` is in .data, not
;;;   on the stack, so it survives independently of any frame. Had it been a
;;;   local (`sub rsp, 16` and address it from rbp), it would have ceased to
;;;   exist at the `ret` -- and printing it afterwards, as you just did, would
;;;   have shown you whatever the next function put there. Static versus
;;;   automatic storage, in one experiment.
;;; ============================================================================

global main                             ; export `main` for the C library start-up

section .data                           ; initialised, writable data
   start db 17h                         ; the seed value, 0x17. `db` = define byte.
                                        ;   NASM accepts both `17h` and `0x17`.
   array db 12 dup (55h)                ; twelve bytes, each initialised to 0x55.
                                        ;   `dup` is MASM/TASM syntax that NASM 2.15+
                                        ;   accepts; the idiomatic NASM spelling is
                                        ;   `times 12 db 0x55`. The 0x55 filler is
                                        ;   entirely overwritten by the loop below.
section .text                           ; the executable-code section

;;; ----------------------------------------------------------------------------
;;; main -- fill `array` with twelve consecutive bytes starting at `start`.
;;;   C equivalent : for (i = 0; i < 12; i++) array[i] = start + i;
;;;   Receives : nothing
;;;   Returns  : rax = 0
;;;   Registers: rdi = a walking pointer into the array
;;;              rcx = the countdown, because `loop` insists on rcx
;;;              al  = the value being stored, incremented each pass
;;;   No prologue and no epilogue: this function has no locals and calls nothing,
;;;   so it never touches the stack. See the call-stack notes above.
;;; ----------------------------------------------------------------------------
main:
     lea rdi, [array]                   ; Load Effective Address: rdi := &array, THE
                                        ;   ADDRESS of the first element. Contrast
                                        ;   `mov rdi, [array]`, which would load the
                                        ;   eight bytes stored there instead.
     mov rcx, 12                        ; the element count -- and the loop counter,
                                        ;   which must be rcx for `loop` to work
     xor eax, eax                       ; zero the whole of rax. `xor r, r` is the
                                        ;   idiomatic clear, and using the 32-bit name
                                        ;   `eax` zeroes the upper 32 bits for free
                                        ;   while encoding one byte shorter.
     mov al, [start]                    ; al := 0x17, the seed. An 8-BIT load, so only
                                        ;   the low byte of rax is written -- which is
                                        ;   why the register was cleared first.
loop1:
      mov byte[rdi], al                 ; store one byte at the current position. The
                                        ;   `byte` keyword is REQUIRED: `[rdi]` alone
                                        ;   does not tell NASM how wide the access is.
      inc al                            ; the next value. An 8-bit increment: it wraps
                                        ;   at 0xFF and never disturbs the rest of rax.
      inc rdi                           ; advance the pointer by ONE, because the
                                        ;   elements are one byte each. THE STEP IS THE
                                        ;   ELEMENT SIZE -- compare array2.asm, which
                                        ;   steps by 2.
      loop loop1                        ; decrement rcx and jump back while non-zero.
                                        ;   Twelve passes in all.
      xor eax, eax                      ; the value `main` returns: 0 = success
      ret                               ; pop the return address into rip. Unlike the
                                        ;   ps_code/1 and /2 exercises, this file
                                        ;   actually goes home.
