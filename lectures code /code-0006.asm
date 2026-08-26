;;; ============================================================================
;;; code-0006.asm -- Demonstrating that the format string can be on the stack!
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints the number 496351. That is all it prints -- and the entire lesson is
;;;   in WHERE the format string "%lld\n" lives while it does so.
;;;
;;;   Up to now every format string sat in `section .data`, a fixed address baked
;;;   into the executable. This file has NO .data section at all. Instead:
;;;
;;;       mov rdi, `%lld\n\0`   <-- the five characters are an IMMEDIATE CONSTANT
;;;       push rdi              <-- ...which we drop onto the stack
;;;       mov rdi, rsp          <-- ...and rsp is now its address
;;;
;;;   THE IDEA WORTH INTERNALISING: a string is not a special kind of object. It
;;;   is a run of bytes, and a "string" argument is just the ADDRESS of the first
;;;   one. NASM's backquoted literal in a `mov` context is assembled as a 64-bit
;;;   integer whose bytes are those characters. `%lld\n\0` is 6 bytes, fits in a
;;;   register with room to spare (the 7th and 8th bytes are zero-filled, which
;;;   conveniently supplies extra terminators).
;;;
;;;   BECAUSE x86 IS LITTLE-ENDIAN, the byte that ends up at the LOWEST address --
;;;   the one printf reads first -- is the register's LEAST significant byte, '%'.
;;;   So the characters come out of memory in the right order without any
;;;   reversal on your part. Read the constant as `%lld\n\0` and it just works;
;;;   in code-0007a you will see the same trick done by hand in hex, where you
;;;   have to reverse the bytes yourself.
;;;
;;;   This also means printf cannot tell the difference. It receives a pointer;
;;;   whether that pointer aims at .data, at the stack, at the heap, or at bytes
;;;   you computed a microsecond ago is entirely invisible to it.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0006.asm"
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0006.asm"
;;;
;;;   Useful session -- this is a short program, so single-step the whole thing:
;;;     si                     step past `push rbp`
;;;     si  si                 ... `mov rbp,rsp` and `and rsp,-16`
;;;     si                     ... `mov rdi, "%lld\n\0"`
;;;     p/x $rdi               0x0a646c6c25 -- read the hex bytes right to left:
;;;                            25='%' 6c='l' 6c='l' 64='d' 0a='\n', then zeros
;;;     si                     ... `push rdi`
;;;     x/s $rsp               gdb prints "%lld\n" -- there is your string,
;;;                            sitting on the stack
;;;     x/8xb $rsp             the same six bytes plus the two zero pad bytes
;;;     si si si               set up the rest of printf's arguments
;;;     info registers rdi rsi rax
;;;     c                      let it print
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   The stack is not a special "call" area -- it is ordinary read/write memory
;;;   that happens to be managed by rsp. This program stores DATA there and hands
;;;   the address to a C function, and nothing objects.
;;;
;;;   Watch rsp do double duty:
;;;       p $rsp        after `and rsp, -16`   -- aligned, ready for a call
;;;       si            `push rdi`
;;;       p $rsp        8 lower. It is now BOTH the stack top AND the address of
;;;                     our string. That is why the very next line is
;;;                     `mov rdi, rsp`.
;;;       p $rsp % 16   8. THE STACK IS NOW MISALIGNED for the upcoming call.
;;;
;;;   That last point is the real lesson hiding in this file. `push rdi` broke
;;;   the 16-byte alignment that `and rsp, -16` established, and the code calls
;;;   printf anyway. It survives -- printf with no floating-point arguments does
;;;   not execute the aligned SSE instructions that would fault -- but it is
;;;   fragile, and code-0007 shows the disciplined version, which re-aligns with
;;;   a second `and rsp, -16` immediately before each call. Compare the two files
;;;   side by side; the difference is one instruction and it is the difference
;;;   between "works today" and "works".
;;;
;;;   Finally, note the epilogue is `mov rsp, rbp` then `pop rbp`, with no
;;;   matching `pop` for our `push rdi`. It does not need one: restoring rsp from
;;;   the anchor rbp discards our pushed string, the alignment adjustment, and
;;;   anything else we did, all in one instruction. THAT is what a frame pointer
;;;   buys you -- you can push freely without counting.
;;; ============================================================================

extern printf                           ; from the C library; the linker resolves it
global main                             ; export main for the C library start-up
section .text                           ; executable code. Note: NO .data and NO .bss --
                                        ;   this program has no statically allocated memory
                                        ;   whatsoever.
;;; ----------------------------------------------------------------------------
;;; main -- print one number using a format string built on the stack.
;;;   C signature : int main(void)
;;;   Returns     : rax = whatever printf left behind (the number of characters
;;;                 it wrote). This program never sets rax to 0, so its exit
;;;                 status is that count -- check with `; echo $?`.
;;;   How it works: materialise "%lld\n\0" as a 64-bit immediate, push it, use
;;;                 rsp as the pointer, call printf, then throw the whole thing
;;;                 away by restoring rsp from rbp.
;;; ----------------------------------------------------------------------------
main:
        push rbp                        ; save the old frame-pointer (rbp is callee-saved).
                                        ;   `push` = rsp -= 8, then store at [rsp].
        mov rbp, rsp                    ; point to the base of the new frame -- the anchor
                                        ;   that lets the epilogue undo everything at once
        and rsp, -16                    ; align the stack downwards, on 16 bytes: clear the
                                        ;   low 4 bits of rsp (-16 == 0xFFFF...FFF0)

        mov rdi, `%lld\n\0`             ; A [format] string is just a number!
                                        ;   NASM assembles the backquoted literal into the
                                        ;   64-bit immediate 0x000000000A646C6C25, i.e. the
                                        ;   bytes % l l d \n \0 \0 \0. Little-endian storage
                                        ;   will lay them out in exactly that order in
                                        ;   memory. %lld = a 64-bit signed decimal.
        push rdi                        ; ...even on the stack.
                                        ;   Now those 8 bytes are IN MEMORY, at [rsp].
                                        ;   (Side effect: rsp is now 8 mod 16 -- see the
                                        ;   alignment discussion in the header.)
        mov rdi, rsp                    ; So the rsp is its address!
                                        ;   printf wants a char*, and the address of the
                                        ;   first character is precisely the current stack
                                        ;   top. rdi = printf argument 1.
        mov rsi, 496351                 ; This is what we wish to print -- printf argument
                                        ;   2, matching the single %lld in the format.
        mov rax, 0                      ; 0 floating-point registers in use. Mandatory for
                                        ;   every variadic call: rax = number of xmm
                                        ;   registers carrying arguments.
        call printf                     ; push the return address and jump. printf reads
                                        ;   the bytes at rdi and has no idea they are on
                                        ;   the stack.

        mov rsp, rbp                    ; reset the stack-pointer. This single instruction
                                        ;   discards BOTH the pushed string and the
                                        ;   alignment adjustment -- no bookkeeping needed.
        pop rbp                         ; point to the base of the PREVIOUS frame: restore
                                        ;   the caller's rbp
        ret                             ; pop the return address into rip

section .note.GNU-stack noalloc noexec  ; required Linux marker: stack is not exec
