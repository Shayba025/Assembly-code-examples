;;; ============================================================================
;;; code-0019.asm -- Our own read_hex, reading from fd(in) == 0 by hand
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prompts, reads a hexadecimal number from standard input, prints its value.
;;;   scanf could do this in one line. The point is to build the machinery
;;;   underneath scanf yourself, and there is more of it than you would guess:
;;;
;;;   1. A RAW `getchar` ON TOP OF sys_read. Call number 0 is read(2):
;;;          ssize_t read(int fd, void *buf, size_t count);
;;;      so rax=0, rdi=0 (stdin), rsi=a one-byte buffer, rdx=1. That is the
;;;      whole of "read one character" at the system level.
;;;
;;;   2. A ONE-CHARACTER PUSHBACK BUFFER -- `ungetchar`. THIS IS THE CENTRAL
;;;      IDEA OF THE FILE. A tokeniser cannot know it has finished reading a
;;;      number until it has read one character too many. It must then put that
;;;      character BACK, so the next stage of parsing can see it. Every scanner
;;;      and every parser in existence needs exactly this, and C exposes it as
;;;      `ungetc`. Here it is two globals:
;;;          unget_buffer -- the one character
;;;          is_fresh     -- 1 if that character has been pushed back and not
;;;                          yet re-read; 0 if the buffer is stale
;;;      `getchar` checks the flag first and only calls the kernel when it must.
;;;
;;;   3. HORNER'S METHOD AND THE TWO-`lea` MULTIPLY BY 16, exactly as in
;;;      code-0016 -- read that file's notes for the arithmetic.
;;;
;;;   4. `fflush(stdout)`. The prompt does not end in a newline, and C's stdout
;;;      is LINE-BUFFERED when attached to a terminal, so without the flush the
;;;      prompt would still be sitting in a buffer while the program waits for
;;;      you to type. Notice the consequence: this program mixes buffered
;;;      library output (printf) with UNBUFFERED raw input (sys_read). Those two
;;;      worlds do not coordinate, and the flush is the seam.
;;;
;;;   A BUG WORTH SPOTTING: `getchar` ignores sys_read's return value. At
;;;   end-of-file read returns 0 and writes nothing, so `unget_buffer` keeps
;;;   whatever it held before -- and if that was a hex digit, the loop never
;;;   ends. Try `printf 'ff' | ./asm ...` (no newline, immediate EOF) and see.
;;;   A correct version compares rax to 0 after the syscall.
;;;
;;;   ANOTHER ONE: `read_hex` uses rbx as its accumulator and never saves it,
;;;   though rbx is callee-saved. Same latent defect as code-0012/13/16.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0019.asm"          # then type e.g.  ff  + Enter
;;;   echo ff       | ./asm "lectures code /code-0019.asm"
;;;   echo DEADBEEF | ./asm "lectures code /code-0019.asm"
;;;   echo 10       | ./asm "lectures code /code-0019.asm"
;;;
;;;   Watch the pushback do its job -- everything after the number survives:
;;;   echo "ff rest of the line" | ./asm "lectures code /code-0019.asm"
;;;
;;;   And see the EOF bug:
;;;   printf 'ff' | ./asm "lectures code /code-0019.asm"     # may hang; Ctrl-C
;;;
;;; DEBUG IT
;;;   echo 1f3 | ./debug "lectures code /code-0019.asm"
;;;
;;;   Useful session:
;;;     break getchar
;;;     c
;;;     p (long)is_fresh          0 -> it will call the kernel
;;;     finish
;;;     p/c $rax                  the character just read
;;;     p $rbx                    the accumulator so far
;;;     c                         next character: 0, 1, 31, 499
;;;
;;;   Catch the pushback happening:
;;;     break ungetchar
;;;     c                         reached once the newline is read
;;;     x/1gx $rsp                the return address
;;;     x/1gd $rsp+8              the ARGUMENT -- the character being pushed back
;;;     finish
;;;     p (long)is_fresh          now 1
;;;     p/c unget_buffer[0]       and there is the character, parked
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THIS FILE HAS THE MOST INTERESTING FUNCTIONS IN THE COURSE FROM A STACK
;;;   POINT OF VIEW, because they are all different shapes:
;;;
;;;   * `between` -- entered by `jmp`, left by `jmp`. NO stack use at all, not
;;;     even a return address. `bt` inside it shows its caller's frame.
;;;   * `getchar` -- entered by `call`, left by `ret`. Uses the stack for
;;;     exactly 8 bytes: the return address. No rbp, no locals.
;;;   * `ungetchar` -- entered by `call` with ONE PUSHED ARGUMENT, left by
;;;     `ret 8*1`. No frame pointer either, which is why it reads its argument
;;;     as `[rsp + 8*1]` rather than `[rbp + 8*2]`.
;;;   * `read_hex` -- entered by `call`, no frame, keeps everything in registers.
;;;
;;;   THE INSTRUCTIVE ONE IS `ungetchar`. Look at how it finds its argument:
;;;       mov rax, [rsp + 8*1]
;;;   With no `push rbp` there is no anchor, so the offsets are counted from rsp
;;;   directly:  [rsp + 8*0] is the return address that `call` pushed, and
;;;   [rsp + 8*1] is the argument pushed before it. Compare with `fact` in
;;;   code-0011, where the same argument sat at [rbp + 8*2] -- one slot further
;;;   out, because the prologue had pushed rbp in between. Same stack, two ways
;;;   to count. Verify both in gdb:
;;;       break ungetchar
;;;       x/2gx $rsp             return address, then the argument
;;;       info symbol *(long*)$rsp   which line it will return to
;;;
;;;   THE DANGER OF THE rsp-RELATIVE STYLE: every push you make shifts every
;;;   offset. `ungetchar` gets away with it because it pushes nothing. `fact`
;;;   could not have, because it pushes constantly. That is the real reason to
;;;   set up a frame pointer -- not tradition, but the fact that rbp does not
;;;   move and rsp does.
;;;
;;;   FINALLY, THE STATE MACHINE. `is_fresh` and `unget_buffer` are in .data and
;;;   .bss, NOT on the stack -- deliberately, because they must persist between
;;;   separate calls to getchar. A stack frame dies at `ret`; a global does not.
;;;   That is the whole criterion for choosing between them. Watch it:
;;;       break getchar
;;;       c c c
;;;       p (long)is_fresh       0 each time... until ungetchar has run
;;; ============================================================================

section .data                                ; initialised, writable data
fmt_prompt:
        db `Enter a number in hex: \0`       ; NOTE: no \n at the end -- which is
                                             ;   exactly why the fflush below is needed
fmt_output:
        db `The value is %lld\n\0`           ; one 64-bit signed decimal

extern printf, fflush, stdout                ; from the C library. `stdout`, like `stderr`,
                                             ;   is a VARIABLE holding a FILE*.
global main                                  ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- prompt, read a hex number, print its value.
;;;   C signature : int main(void)
;;;   Returns     : rax = printf's character count (never explicitly zeroed)
;;;   How it works: printf the prompt, fflush so it actually appears, call
;;;                 read_hex, printf the answer.
;;; ----------------------------------------------------------------------------
main:
        push rbp                             ; backup the old fp (rbp is callee-saved)
        mov rbp, rsp                         ; set the fp to the base of the top frame
        and rsp, -16                         ; align the stack by 16 bytes for printing

        mov rdi, fmt_prompt                  ; prompt for input (printf argument 1)
        mov rax, 0                           ; no fp registers in use (the variadic rule)
        call printf

        mov rdi, qword [stdout]              ; the printf didn't end with \n so nothing is
        call fflush                          ; ...printed before we flush the buffer!
                                             ; same as fflush(stdout) in C.
                                             ;   C's stdout is line-buffered on a terminal:
                                             ;   characters sit in a buffer until a newline
                                             ;   arrives. Without this the prompt would appear
                                             ;   only AFTER you had already typed your answer.

        call read_hex                        ; read in a number in hex. Result in rax.

        mov rdi, fmt_output                  ; format string for output (printf argument 1)
        mov rsi, rax                         ; the value of the hex string (argument 2)
        mov rax, 0                           ; no fp registers in use
        call printf

        mov rsp, rbp                         ; reset the stack pointer from the anchor
        pop rbp                              ; restore fp to the base of the previous frame
        ret                                  ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; read_hex -- read hexadecimal digits from stdin until a non-digit appears.
;;;   Pseudo-C   : long read_hex(void)
;;;                {
;;;                    long acc = 0; int c;
;;;                    while (ishexdigit(c = getchar())) acc = acc*16 + val(c);
;;;                    ungetchar(c);
;;;                    return acc;
;;;                }
;;;   Receives   : nothing -- it takes its input from fd 0
;;;   Returns    : rax = the value of the digits consumed
;;;   Clobbers   : rax, rbx (CALLEE-SAVED and not preserved -- see the header),
;;;                and everything `between` uses: rdi, rsi, rdx, rcx, r8
;;;   Stack use  : only the 8-byte return address; it has no frame of its own.
;;;
;;;   How it works: Horner's method, with `between` used three times per
;;;   character as a classifier (exactly as in code-0016). The essential detail
;;;   is the exit: when a character matches NONE of the three ranges, the last
;;;   `between` jumps to .cont3, which PUSHES THAT CHARACTER BACK before
;;;   returning. Without that pushback the character would be lost, and any
;;;   later parsing of the same input would silently skip it.
;;; ----------------------------------------------------------------------------
read_hex:
        mov rbx, 0                           ; accumulator = 0 -- the value of the empty prefix.
                                             ;   (rbx is callee-saved and is being clobbered
                                             ;   without a push; see the header note.)
.inner:
        call getchar                         ; rax <-- char from fd(in) = 0

        mov rdi, rax                         ; char read -- `between`'s first argument
        mov rsi, '0'                         ; '0' <= ch   (a character literal is its ASCII code)
        mov rdx, '9'                         ; && ch <= '9'
        mov rcx, .digit_0_to_9               ; handle 0..9 -- the "inside" continuation
        mov r8, .cont1                       ; or else... -- the "outside" continuation
        jmp between                          ; JMP, not CALL: nothing is pushed
.cont1:
        mov rsi, 'a'                         ; 'a' <= ch
        mov rdx, 'f'                         ; && ch <= 'f'
        mov rcx, .digit_a_to_f               ; handle a..f
        mov r8, .cont2                       ; or else...
        jmp between
.cont2:
        mov rsi, 'A'                         ; 'A' <= ch
        mov rdx, 'F'                         ; && ch <= 'F'
        mov rcx, .digit_A_to_F               ; handle A..F
        mov r8, .cont3                       ; or else... -- and .cont3 is the LOOP EXIT
        jmp between
.cont3:
        push rax                             ; return char to unget-buffer. The character in rax
                                             ;   is not a hex digit, so it does not belong to us
                                             ;   -- but we have already consumed it from the
                                             ;   input. Pushing it as an argument...
        call ungetchar                       ; ...and handing it to ungetchar puts it back.
                                             ;   THE WHOLE REASON THIS FILE EXISTS. Note no
                                             ;   `add rsp, 8` follows: ungetchar is Pascal-style
                                             ;   and cleans up its own argument.

        mov rax, rbx                         ; rax <-- accumulator: move the answer into the
                                             ;   return register
        ret                                  ; back to main
.digit_0_to_9:
        lea rbx, [2*rbx]                     ; step 1 of multiplying by 16: the address unit's
                                             ;   scale can only be 1, 2, 4 or 8, so double first.
                                             ;   `lea` keeps the computed address as a NUMBER --
                                             ;   no memory is touched, no flags are set.
        lea rbx, [rax + 8*rbx - '0']         ; (16 * accumulator) + (ch - '0')
                                             ;   Three operations folded into one instruction:
                                             ;   scale by 8, add the character, subtract the
                                             ;   ASCII bias (which NASM computes at assembly time).
        jmp .inner                           ; loop again
.digit_a_to_f:
        lea rbx, [2*rbx]                     ; double, as above
        lea rbx, [rax + 8*rbx - ('a' - 10)]  ; 16 * accumulator + (ch - 'a' + 10)
                                             ;   so 'a' maps to 10 and 'f' to 15
        jmp .inner                           ; loop again
.digit_A_to_F:
        lea rbx, [2*rbx]                     ; double, as above
        lea rbx, [rax + 8*rbx - ('A' - 10)]  ; 16 * accumulator + (ch - 'A' + 10)
        jmp .inner                           ; loop again

;;; --- the one-character pushback state. These MUST be globals, not stack
;;; --- locals: they have to survive between separate calls to getchar, and a
;;; --- stack frame dies at `ret`.
section .data
;;; is_fresh == 1 means we read the next call to getchar
;;; reads the char from the unget_buffer, and not from fd(in) == 0
is_fresh:
        dq 0                                 ; the flag, initially 0 = "the buffer is stale,
                                             ;   go ask the kernel"

section .bss
unget_buffer:
        resb 1                               ; `resb 1` reserves ONE byte, zero-filled at load
                                             ;   time. It serves double duty: it is both the
                                             ;   pushback slot and the destination sys_read
                                             ;   writes into.

section .text
;;; ----------------------------------------------------------------------------
;;; getchar -- return the next character of standard input, honouring pushback.
;;;   Pseudo-C   : int getchar(void)
;;;                { if (is_fresh) { is_fresh = 0; }
;;;                  else { read(0, unget_buffer, 1); }
;;;                  return (unsigned char) unget_buffer[0]; }
;;;   Receives   : nothing
;;;   Returns    : rax = the character, zero-extended to 64 bits
;;;   Clobbers   : rax, rdi, rsi, rdx -- and rcx and r11, destroyed by `syscall`
;;;   Stack use  : only the 8-byte return address; no frame.
;;;
;;;   How it works: if a character was pushed back, clear the flag and return
;;;   the buffer's contents without touching the kernel. Otherwise issue a
;;;   one-byte sys_read straight INTO the same buffer -- a neat trick that means
;;;   the ".done" tail is shared by both paths.
;;;
;;;   THE BUG (see the header): the return value of sys_read is ignored. At
;;;   end-of-file it returns 0 and writes nothing, so the buffer keeps its old
;;;   contents and the caller can loop forever.
;;; ----------------------------------------------------------------------------
getchar:
        cmp qword [is_fresh], 0              ; is_fresh == 0 --> read char from fd(in)
        jz .must_read                        ; `jz` == `je`: the flag is clear, so nothing was
                                             ;   pushed back and we must ask the kernel
        mov qword [is_fresh], 0              ; set is_fresh to 0 -- consume the pushback, so a
                                             ;   second getchar will go to the kernel again
        jmp .done                            ; the character is already in the buffer
.must_read:
        mov rax, 0                           ; sys_read. For a syscall, rax selects the service;
                                             ;   0 is read(2) on x86-64 Linux.
        mov rdi, 0                           ; in = 0 -- file descriptor 0 is standard input
        mov rsi, unget_buffer                ; place char directly into the unget_buffer.
                                             ;   Reading into the SAME byte the pushback path
                                             ;   uses is what lets both paths share .done.
        mov rdx, 1                           ; only read 1 char
        syscall                              ; trap into the kernel. Destroys rcx (saved rip)
                                             ;   and r11 (saved rflags); returns the byte count
                                             ;   in rax -- which this code ignores. See the bug
                                             ;   note in the header.
.done:
        movzx rax, byte [unget_buffer]       ; movzx extends the byte into a quadword.
                                             ;   Zero-extension, not sign-extension: characters
                                             ;   are unsigned, and `movsx` would turn bytes
                                             ;   >= 0x80 into negative numbers and break every
                                             ;   range test in `between`.
        ret                                  ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; ungetchar -- push one character back, so the next getchar returns it.
;;;   Pseudo-C   : void ungetchar(int c)
;;;                { unget_buffer[0] = c; is_fresh = 1; }
;;;   Receives   : the character PUSHED ON THE STACK by the caller
;;;   Returns    : nothing
;;;   Cleanup    : ITS OWN, via `ret 8*1` (Pascal-style)
;;;   Stack use  : no frame at all -- which is why it reads its argument as
;;;                [rsp + 8*1] rather than [rbp + 8*2]. See the call-stack
;;;                discussion in the header; this is the clearest example in the
;;;                course of counting offsets from rsp.
;;;
;;;   Capacity is exactly ONE character. Calling it twice in a row without an
;;;   intervening getchar would silently lose the first. C's ungetc guarantees
;;;   only one pushback for the same reason.
;;; ----------------------------------------------------------------------------
ungetchar:
        mov rax, [rsp + 8*1]                 ; grab the argument.
                                             ;   NO frame pointer here, so offsets are counted
                                             ;   from rsp: [rsp + 8*0] is the return address
                                             ;   `call` pushed, and [rsp + 8*1] is the argument
                                             ;   the caller pushed just before it. This works
                                             ;   only because this function pushes nothing --
                                             ;   any push would shift the offset.
        mov byte [unget_buffer], al          ; write into the unget_buffer.
                                             ;   `al` is the low BYTE of rax; the destination is
                                             ;   one byte wide, so the operand sizes match.
        mov qword [is_fresh], 1              ; set is_fresh <-- 1, so that the next
                                             ; call to getchar reads from unget_buffer
        ret 8*1                              ; Pascal-style: callee cleans the argument.
                                             ;   Pops the return address into rip and then adds
                                             ;   8 to rsp, discarding the pushed character. rsp
                                             ;   moves by 16 in this single instruction.

;;; ----------------------------------------------------------------------------
;;; between -- the shared, non-returning range test (identical to code-0005).
;;;
;;; Using between:
;;; | rdi | n               |
;;; | rsi | lower bound     |
;;; | rdx | upper bound     |
;;; | rcx | addr if inside  |
;;; | r8  | addr if outside |
;;;
;;;   Semantics  : if (lo <= n && n <= hi) goto rcx; else goto r8;
;;;   Reached by : `jmp between`, never `call between`
;;;   Returns    : NEVER -- it transfers control onward
;;;   Stack cost : zero. It is the only "function" here that does not even use a
;;;                return address.
;;; ----------------------------------------------------------------------------
between:
        cmp rdi, rsi                         ; n - lo, flags only
        jl .L                                ; `jl` = jump if less (signed): below the range
        cmp rdi, rdx                         ; n - hi, flags only
        jg .L                                ; `jg` = jump if greater (signed): above the range
        jmp rcx                              ; in range: INDIRECT jump to the "inside" label
.L:
        jmp r8                               ; out of range: indirect jump to the "outside" label

section .note.GNU-stack noalloc noexec       ; required Linux marker: stack is not exec
