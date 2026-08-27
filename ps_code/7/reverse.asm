;;; ============================================================================
;;; reverse.asm -- reverse a line of input, with NO C library at all
;;; Practice session 7                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Reads up to 256 bytes from standard input, reverses them in place, writes
;;;   them back out, and exits.
;;;   (Verified: `printf 'abc\n'` produces the four bytes `\n c b a`.)
;;;
;;;   *** IT DEFINES `_start`, NOT `main`, AND THAT CHANGES EVERYTHING. ***
;;;   Every other program in this course is called BY the C library: the loader
;;;   starts libc, libc sets up the heap and stdio and the environment, and then
;;;   calls your `main`. This one IS the entry point. There is no libc, no
;;;   start-up code, and -- crucially -- NOBODY TO RETURN TO. That is why the
;;;   program ends with
;;;       mov rax, 60 ; xor rdi, rdi ; syscall     ; exit(0)
;;;   rather than a `ret`. A `ret` here would pop whatever the kernel happened to
;;;   leave at the top of the stack (which is argc, not an address) and jump to
;;;   it.
;;;
;;;   IT ALSO CHANGES HOW IT IS LINKED. `gcc` would supply its own `_start` from
;;;   crt1.o and the link would fail with "multiple definition of `_start'". The
;;;   ./asm and ./debug scripts detect the `global _start` line and link with
;;;   plain `ld` instead, producing a freestanding executable with no libc in it
;;;   at all. Check how small that makes it:
;;;       ls -l ps_code/7/reverse
;;;   -- a few kilobytes, against a hundred or so for a libc program.
;;;
;;;   THE ALGORITHM is the classic two-pointer reverse: one index walking up from
;;;   the start, one walking down from the end, swapping as they pass and
;;;   stopping when they meet. n/2 swaps, no extra memory.
;;;
;;;   *** AND THERE IS A BUG WORTH FINDING. *** `read` returns the number of
;;;   bytes it got, INCLUDING the newline you pressed Enter for. Nothing strips
;;;   it, so the newline is treated as an ordinary character and ends up at the
;;;   FRONT of the output:
;;;       printf 'abc\n' | ./asm "ps_code/7/reverse.asm" | od -c
;;;       0000000   \n   c   b   a
;;;   The blank line you see before the reversed text is that newline. The fix is
;;;   to test whether buf[rax-1] is 10 and, if so, decrement the count before
;;;   reversing. Try it.
;;;
;;;   `default rel` at the top tells NASM to use RIP-RELATIVE addressing by
;;;   default for memory operands -- `[buf]` becomes "buf, as an offset from the
;;;   current instruction" rather than an absolute address. That is what makes
;;;   position-independent executables possible, and it is the modern default.
;;;
;;;   A SECOND, SUBTLER BUG: `bl` is used as a swap temporary, but rbx is
;;;   CALLEE-SAVED. In a `_start` there is no caller to break, so it is harmless
;;;   here -- but the habit is not.
;;;
;;;   AND A THIRD: if `read` returns 0 (immediate end of input), `dec rdx` makes
;;;   rdx = -1, and `cmp rcx, rdx / jge` with rcx = 0 is true, so the loop is
;;;   skipped. It survives by luck rather than by check.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   printf 'hello\n' | ./asm "ps_code/7/reverse.asm"
;;;   printf 'abcdef\n' | ./asm "ps_code/7/reverse.asm"
;;;   printf 'racecar\n' | ./asm "ps_code/7/reverse.asm"     # a palindrome
;;;   ./asm "ps_code/7/reverse.asm"                          # type it yourself
;;;
;;;   SEE THE NEWLINE BUG for yourself -- this is the point of the exercise:
;;;   printf 'abc\n' | ./asm "ps_code/7/reverse.asm" | od -c
;;;   printf 'abc'   | ./asm "ps_code/7/reverse.asm" | od -c   # no newline: clean
;;;
;;;   And see how small a program with no C library is:
;;;   ls -l ps_code/7/reverse
;;;
;;; DEBUG IT
;;;   printf 'abc\n' | ./debug "ps_code/7/reverse.asm"
;;;
;;;   Note gdb stops at `main` by default and there is no `main` here, so set
;;;   your own breakpoint:
;;;     break _start
;;;     c
;;;
;;;   Useful session -- watch the two pointers close in:
;;;     break reverse.asm:NN      NN on the `cmp rcx, rdx` line
;;;     c
;;;     display/d $rcx            the left index
;;;     display/d $rdx            the right index
;;;     x/s &buf                  the buffer as it stands
;;;     c   c   c                 ...and watch them meet in the middle
;;;
;;;   Catch the newline red-handed:
;;;     break reverse.asm:NN      NN on the `mov rdx, rax` line, just after read
;;;     c
;;;     p $rax                    4 for "abc\n" -- one MORE than the letters
;;;     x/4xb &buf                61 62 63 0a -- there it is, byte 0x0a
;;;     x/4c &buf                 'a' 'b' 'c' '\n'
;;;
;;;   And watch one swap happen:
;;;     break reverse.asm:NN      NN on the `mov al, [buf+rcx]` line
;;;     c
;;;     x/4c &buf                 before
;;;     si si si si               the four instructions of the swap
;;;     x/4c &buf                 two characters have traded places
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE STACK AT `_start` IS NOT WHAT YOU ARE USED TO, and this is the one
;;;   place in the course where you can look at it. When the kernel starts a
;;;   process it does not push a return address -- it lays out the program's
;;;   arguments and environment directly:
;;;
;;;       [rsp]        argc          (an INTEGER, not an address)
;;;       [rsp+8]      argv[0]
;;;       [rsp+16]     argv[1]
;;;       ...
;;;       argv[argc] = NULL
;;;       then envp[0], envp[1], ... NULL
;;;       then the auxiliary vector
;;;
;;;   Look at it yourself:
;;;       break _start
;;;       c
;;;       x/1gd $rsp                 argc
;;;       x/s *(char**)($rsp+8)      argv[0] -- the program's own path
;;;       x/s *(char**)($rsp+16)     argv[1], if you passed one
;;;       bt                         essentially nothing: there is no caller
;;;
;;;   THAT IS WHERE `int main(int argc, char *argv[])` COMES FROM. The C
;;;   library's own `_start` reads exactly those quadwords, moves argc into rdi
;;;   and the address of argv[0] into rsi, and then calls your `main`. Every
;;;   `mov rdi, qword [rsi + 8*1]` you have written since code-0002.asm is
;;;   reading a structure that the KERNEL built, and that libc merely handed on.
;;;   Here you would have to do that translation yourself.
;;;
;;;   THE SECOND OBSERVATION: this program never pushes anything, never builds a
;;;   frame, and never calls anything. `p $rsp` is identical at the first
;;;   instruction and the last. Everything the ABI asks of you -- 16-byte
;;;   alignment, callee-saved registers, the variadic rax count -- exists to let
;;;   your code interoperate with C. Take C away and none of it applies. Four
;;;   system calls and a loop.
;;;
;;;   The price is that you get nothing for free either: no printf, no malloc, no
;;;   buffered I/O, no automatic exit. Compare cp.asm in this same folder, which
;;;   does its real work with the same raw system calls but keeps libc around for
;;;   printf -- and therefore has to obey all the rules again.
;;; ============================================================================

default rel                             ; use RIP-RELATIVE addressing by default, so
                                        ;   `[buf]` means "buf, as an offset from the
                                        ;   current instruction" rather than an absolute
                                        ;   address. This is what makes the code
                                        ;   position-independent.
section .bss                            ; zero-filled at load time, no file space
    buf: resb 256                       ; `resb 256` reserves 256 BYTES for the line

section .text                           ; the executable-code section
global _start                           ; THE PROGRAM'S ENTRY POINT -- not `main`. The
                                        ;   kernel jumps straight here, with no C
                                        ;   library in the picture at all. See the header.

;;; ----------------------------------------------------------------------------
;;; _start -- read a line, reverse it in place, write it back, exit.
;;;   Receives : nothing in registers. argc and argv are ON THE STACK, laid out
;;;              by the kernel -- see the call-stack notes above. This program
;;;              ignores them.
;;;   Returns  : it does not. It ends with the exit system call.
;;;   Registers: rcx = the left index, rdx = the right index,
;;;              r12 = the byte count (kept because rdx is reused),
;;;              al / bl = the two characters being swapped
;;;   Stack use: NONE. No frame, no pushes, no calls.
;;; ----------------------------------------------------------------------------
_start:
    mov rax, 0                          ; sys_read -- for a SYSTEM call, rax selects the
                                        ;   service. 0 is read(2) on x86-64 Linux.
    mov rdi, 0                          ; argument 1: file descriptor 0 = standard input
    mov rsi, buf                        ; argument 2: where to put the bytes
    mov rdx, 256                        ; argument 3: at most this many -- exactly the
                                        ;   size of the buffer, so nothing can overrun
    syscall                             ; trap into the kernel. Destroys rcx and r11;
                                        ;   returns the byte count in rax (or -errno).
    mov rdx, rax                        ; rdx := the number of bytes read.
                                        ;   NOTE this INCLUDES the trailing newline --
                                        ;   see the bug described in the header.

        dec rdx                         ; the index of the LAST byte, since indices run
                                        ;   0 .. count-1. This is the right-hand pointer.
        xor rcx, rcx                    ; the left-hand pointer starts at 0. `xor r, r`
                                        ;   is the idiomatic zeroing.

        mov r12, rax                    ; keep the original count: rdx is about to be
                                        ;   walked downward, and the write at the end
                                        ;   still needs the length

.rev_loop:
    cmp rcx, rdx                        ; have the two pointers met or crossed?
    jge .rev_done                       ; `jge` = jump if greater or equal, SIGNED.
                                        ;   Everything has been swapped.

    mov al, [buf+rcx]                   ; load the left character. `al` is the low BYTE
                                        ;   of rax; the widths must match a one-byte
                                        ;   memory operand.
    mov bl, [buf+rdx]                   ; load the right character. (`bl` is the low byte
                                        ;   of rbx, which is CALLEE-SAVED -- harmless in
                                        ;   a `_start` with no caller, but see the header.)
    mov [buf+rcx], bl                   ; ...and write them back crossed over. No third
    mov [buf+rdx], al                   ;   register is needed: both values are already
                                        ;   in registers.

    inc rcx                             ; the left pointer moves right...
    dec rdx                             ; ...and the right pointer moves left
    jmp .rev_loop                       ; round again. n/2 iterations in total.

.rev_done:

    mov rax, 1                          ; sys_write
    mov rdi, 1                          ; argument 1: file descriptor 1 = standard output
    mov rsi, buf                        ; argument 2: the reversed bytes
    mov rdx, r12                        ; argument 3: THE ORIGINAL COUNT, recovered from
                                        ;   r12 because rdx was consumed by the loop.
                                        ;   A count, not a terminator -- these are not
                                        ;   C strings.
    syscall

    mov rax, 60                         ; sys_exit -- call number 60
    xor rdi, rdi                        ; argument 1: the exit status, 0 = success
    syscall                             ; THE PROGRAM ENDS HERE. There is no `ret`,
                                        ;   because there is nobody to return to: the
                                        ;   kernel started us directly. This system call
                                        ;   never returns.
