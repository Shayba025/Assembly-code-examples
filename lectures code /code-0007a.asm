;;; ============================================================================
;;; code-0007a.asm -- code-0007 with EVERY string built on the stack, in hex
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Exactly what code-0007 does -- prompt, read an integer, echo it -- but this
;;;   version has no `section .data` at all. Even the long output string
;;;   "You entered: %lld\n" is assembled at run time, from three 64-bit
;;;   immediates pushed onto the stack.
;;;
;;;   READ THE TWO FILES SIDE BY SIDE. The only difference is that
;;;       mov rdi, fmt_output          (code-0007: a pointer into .data)
;;;   becomes
;;;       push 3 quadwords ; mov rdi, rsp   (here: a pointer into the stack)
;;;
;;;   DECODING THE HEX -- do this by hand once and you will never be confused by
;;;   endianness again. x86 is LITTLE-ENDIAN: the LEAST significant byte of a
;;;   register goes to the LOWEST address. So read each constant RIGHT TO LEFT:
;;;
;;;     0x65746E6520756F59  ->  59 6F 75 20 65 6E 74 65  ->  Y  o  u  _  e  n  t  e
;;;     0x6C6C25203A646572  ->  72 65 64 3A 20 25 6C 6C  ->  r  e  d  :  _  %  l  l
;;;     0x0A64              ->  64 0A 00 00 00 00 00 00  ->  d  \n \0 ...
;;;
;;;   Concatenated: "You ente" + "red: %ll" + "d\n\0"  =  "You entered: %lld\n"
;;;
;;;   WHY THE PUSHES ARE IN REVERSE ORDER. The stack grows DOWNWARD, so each
;;;   push lands 8 bytes BELOW the previous one. The chunk pushed LAST ends up at
;;;   the LOWEST address, and the lowest address is where the string starts. So
;;;   you must push the TAIL first and the HEAD last:
;;;
;;;        higher addresses
;;;          [rsp+16]  "d\n\0....."   <- pushed 1st
;;;          [rsp+8]   "red: %ll"     <- pushed 2nd
;;;          [rsp]     "You ente"     <- pushed 3rd, and rsp points here
;;;        lower addresses
;;;
;;;   Note that the first constant, 0x0A64, is only two significant bytes; the
;;;   `mov` zero-extends it to 64 bits, which conveniently supplies the six
;;;   NUL bytes that terminate the string. The three chunks must be contiguous,
;;;   which they are precisely because nothing intervenes between the pushes.
;;;
;;;   (Also note: the header comment inside the original file says "code-0007".
;;;   That is the professor's copy-paste; this file is the 'a' variant.)
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0007a.asm"        # then type a number + Enter
;;;   echo 12345 | ./asm "lectures code /code-0007a.asm"
;;;
;;; DEBUG IT
;;;   echo 12345 | ./debug "lectures code /code-0007a.asm"
;;;
;;;   The session that makes this file click -- stop after the three pushes:
;;;     break printf
;;;     c                      first stop: the "int> " prompt
;;;     c                      second stop: the interesting one
;;;     x/s $rdi               "You entered: %lld\n"  -- assembled from thin air
;;;     x/3gx $rdi             the three quadwords you pushed, in memory order
;;;     x/24xb $rdi            the same 24 bytes one at a time...
;;;     x/24c $rdi             ...and now as characters. Compare with the table
;;;                            above, byte for byte.
;;;     p $rdi == $rsp         1 -- the string IS the stack top
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   The stack is just memory, and `push` is just a store with an automatic
;;;   pointer decrement. This program uses it as a scratch buffer -- something
;;;   you would normally call malloc for -- and the only reason that is safe is
;;;   that the data is consumed before anything else touches the stack.
;;;
;;;   The instructive experiment is to break the contiguity. In gdb, after the
;;;   three pushes, do:
;;;       p $rsp
;;;       x/s $rsp
;;;   then imagine a `call` had been inserted between push #2 and push #3: the
;;;   return address would have been written into the middle of your string.
;;;   That is precisely why nothing may intervene, and it is the same reasoning
;;;   behind the ABI's RED ZONE rules and behind why you must never keep data
;;;   below rsp across a call.
;;;
;;;   Second thing to look at: `p $rsp % 16` after the three pushes. Three pushes
;;;   = 24 bytes = 8 mod 16, so alignment is broken again, and again the code
;;;   fixes it with `and rsp, -16` immediately before the call -- AFTER rdi has
;;;   already captured the address. Order matters: capture the pointer, then
;;;   align. Rounding rsp DOWN can only move it further from your data, never
;;;   over it, which is why this is safe.
;;;
;;;   Finally, `bt` inside printf shows one frame of yours, as always, and
;;;   `x/1gx $rbp+8` shows the return address into the C library. The whole
;;;   three-chunk string lives at negative offsets from rbp and vanishes the
;;;   instant the epilogue runs `mov rsp, rbp`.
;;; ============================================================================

extern printf, scanf                    ; supplied by the C library; no .data, no .bss
global main                             ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- prompt, read an integer, echo it, with all three strings on the stack.
;;;   C equivalent : int main(void) { long long x; printf("int> ");
;;;                                   scanf("%lld", &x);
;;;                                   printf("You entered: %lld\n", x); }
;;;   Returns      : rax = printf's character count (never explicitly zeroed)
;;;   Frame layout : [rbp]      saved caller rbp
;;;                  [rbp-8*1]  whichever short format string is current
;;;                  [rbp-8*2]  the integer scanf writes
;;;                  [rbp-8*3..-8*5] the three chunks of the output string
;;;   How it works : three stanzas. The first two are identical to code-0007;
;;;                  the third replaces a .data pointer with three pushes.
;;; ----------------------------------------------------------------------------
main:
        push rbp                        ; save the old frame-pointer (rbp is callee-saved)
        mov rbp, rsp                    ; point to the base of the new frame -- the anchor
                                        ;   every local below is measured from

        mov rdi, `int> \0`              ; a [format] string is just a number!
                                        ;   'i','n','t','>',' ','\0' in one 64-bit immediate
        push rdi                        ; ...even on the stack. Lands at [rbp - 8*1].
        mov rdi, rsp                    ; so the rsp is its address! printf argument 1.
        mov rax, 0                      ; 0 floating-point registers in use (variadic rule)
        and rsp, -16                    ; align the stack downwards, on 16 bytes -- the push
                                        ;   left rsp at 8 mod 16. Done after rdi captured
                                        ;   the address, so nothing is lost.
        call printf                     ; prints the prompt "int> "
        mov rsp, rbp                    ; restore the rsp: clean slate for the next stanza

        mov rdi, `%lld\0`               ; the scanf format-string as a number
        push rdi                        ; ...on the stack, at [rbp - 8*1]
        mov rdi, rsp                    ; So the rsp is its address! scanf argument 1.
        sub rsp, 8*1                    ; Making room for the integer -- rsp down 8 bytes
                                        ;   allocates a local. The slot is [rbp - 8*2].
        mov rsi, rsp                    ; So the rsp is its address! scanf argument 2: the
                                        ;   POINTER scanf writes the converted value into.
        and rsp, -16                    ; align the stack downwards, on 16 bytes
        call scanf                      ; reads a decimal from stdin into [rbp - 8*2]

                                        ;; --- build "You entered: %lld\n" on the stack, tail chunk first ---
        mov rdi, 0x0A64                 ; bytes 64 0A = 'd' '\n', then six zero bytes
                                        ;   supplied free by the 64-bit zero-extension.
                                        ;   This is the LAST 8 bytes of the string, so it
                                        ;   is pushed FIRST (it must end up highest).
        push rdi                        ; -> [rbp - 8*3]
        mov rdi, 0x6C6C25203A646572
                                        ; bytes 72 65 64 3A 20 25 6C 6C = "red: %ll"
                                        ;   (read the hex right-to-left: little-endian)
        push rdi                        ; -> [rbp - 8*4], immediately below the previous
        mov rdi, 0x65746E6520756F59
                                        ; bytes 59 6F 75 20 65 6E 74 65 = "You ente"
                                        ;   the HEAD of the string, so pushed LAST
        push rdi                        ; -> [rbp - 8*5], the lowest of the three: the
                                        ;   string now reads correctly from here upward
        mov rdi, rsp                    ; printf argument 1: the address of the first
                                        ;   character, which is exactly the stack top
        mov rsi, qword [rbp - 8*2]      ; this is the number we read with scanf.
                                        ;   Read from rbp, not rsp -- rsp has moved four
                                        ;   times since the slot was carved out.
        mov rax, 0                      ; 0 floating-point registers in use
        and rsp, -16                    ; align the stack downwards, on 16 bytes (three
                                        ;   pushes put it at 8 mod 16)
        call printf                     ; prints "You entered: <n>" -- from a format string
                                        ;   that exists nowhere in the executable file

        mov rsp, rbp                    ; restore the rsp: all five quadwords of locals and
                                        ;   strings are discarded in one instruction
        pop rbp                         ; point to the base of the previous frame
        ret                             ; pop the return address into rip

section .note.GNU-stack noalloc noexec  ; required Linux marker: stack is not exec
