;;; ============================================================================
;;; code-0016.asm -- Convert a hex string on the command line to its value
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   `./prog ff` prints 255. `./prog DEADBEEF` prints 3735928559. It is a
;;;   hand-written `strtol(s, NULL, 16)`, and it reuses the `between`
;;;   continuation trick from code-0005 to classify each character.
;;;
;;;   THE ALGORITHM is Horner's method, the same one you use to read decimal:
;;;       value = 0
;;;       for each character c:  value = value*16 + digitvalue(c)
;;;   Reading "1f3" left to right gives 0, then 1, then 1*16+15 = 31, then
;;;   31*16+3 = 499. No powers of 16 are ever computed.
;;;
;;;   THE INSTRUCTION TO STUDY -- multiplying by 16 with two `lea`s:
;;;       lea rax, [2*rax]                  ; rax := 2*rax
;;;       lea rax, [rdi + 8*rax - '0']      ; rax := 8*(2*rax) + rdi - '0'
;;;   which together give 16*rax + (c - '0'). Why in two steps? Because the
;;;   address unit's scale factor can only be 1, 2, 4 or 8 -- there is no
;;;   16*rax addressing mode. So you double first, then scale by 8. The second
;;;   `lea` folds THREE operations -- the multiply, the add of the digit, and
;;;   the subtraction of the ASCII bias -- into one instruction that touches no
;;;   memory and sets no flags. This is the kind of thing compilers do
;;;   constantly, and reading it fluently is a real skill.
;;;
;;;   THE ASCII ARITHMETIC. '0'..'9' are 0x30..0x39, so c - '0' is the digit.
;;;   'a'..'f' are 0x61..0x66 and must map to 10..15, so the bias is 'a' - 10.
;;;   'A'..'F' likewise with 'A' - 10. NASM evaluates ('a' - 10) at assembly
;;;   time -- there is no run-time subtraction of a subtraction.
;;;
;;;   `movzx rdi, byte [rbx]` -- MOVE WITH ZERO EXTENSION. A byte load into a
;;;   64-bit register must say what happens to the other 56 bits. `movzx`
;;;   fills them with zeros (right for a character); `movsx` would replicate
;;;   the sign bit. Get this wrong and characters above 0x7F become huge
;;;   negative numbers and every range test fails.
;;;
;;;   A BUG WORTH SPOTTING: `rbx` holds the string cursor and is never saved or
;;;   restored, yet rbx is CALLEE-SAVED. Same latent defect as code-0012 and
;;;   code-0013; the fix is `push rbx` / `pop rbx` around main's body.
;;;
;;;   ALSO NOTE: an empty-looking argument (`./prog ""`) prints 0 rather than
;;;   complaining, because the loop simply never runs. Real strtol reports that.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0016.asm" ff              # 255
;;;   ./asm "lectures code /code-0016.asm" FF              # 255
;;;   ./asm "lectures code /code-0016.asm" 10              # 16
;;;   ./asm "lectures code /code-0016.asm" DEADBEEF        # 3735928559
;;;   ./asm "lectures code /code-0016.asm" 7fffffffffffffff
;;;   ./asm "lectures code /code-0016.asm" xyz             # usage error
;;;   ./asm "lectures code /code-0016.asm"                 # usage error
;;;
;;;   Check it against the shell's own converter:
;;;   for h in 0 9 a f 10 ff abc DEADBEEF; do
;;;       printf "%-10s mine=%s  shell=%d\n" "$h" \
;;;           "$(./asm "lectures code /code-0016.asm" $h | cut -d' ' -f2)" \
;;;           "$((16#$h))"
;;;   done
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0016.asm" 1f3
;;;
;;;   Useful session -- watch Horner's method build the number:
;;;     break code-0016.asm:NN     put NN on the `movzx rdi, byte [rbx]` line
;;;     c
;;;     x/s $rbx                   the REST of the string, from the cursor on
;;;     p/c $rdi                   the character about to be classified
;;;     p $rax                     the value accumulated so far
;;;     c                          next character: 0, 1, 31, 499
;;;
;;;   Watch the two-lea multiply:
;;;     break code-0016.asm:NN     NN on the first `lea rax, [2*rax]`
;;;     c
;;;     p $rax                     say 1
;;;     si                         -> 2
;;;     si                         -> 8*2 + 'f' - '0'... check it by hand
;;;     p $rax
;;;
;;;   And the classifier:
;;;     break between
;;;     c
;;;     info registers rdi rsi rdx
;;;     info symbol $rcx           the label for "this IS a 0-9 digit"
;;;     info symbol $r8            the label for "try the next range"
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   The same lesson as code-0005, now in a loop: `between` is entered by `jmp`
;;;   and left by `jmp`, so it costs nothing on the stack. Break on `between`,
;;;   hit `c` a dozen times, and print `p $rsp` at every stop -- it never moves,
;;;   even though the "subroutine" has been invoked three times per character.
;;;   `bt` will keep showing only `main`, because as far as the stack is
;;;   concerned control never left it.
;;;
;;;   THE DETAIL WORTH NOTICING IN THIS FILE. Look at the last classifier:
;;;       mov r8, .usage
;;;   The "outside all ranges" continuation is the ERROR EXIT. So a bad
;;;   character does not return an error code that someone must remember to
;;;   check -- it simply continues into the error handler, in one jump, from
;;;   whatever depth. In continuation-passing style, error handling is not a
;;;   separate mechanism; it is just a different "what to do next". Set
;;;   `break between`, run with `./debug ... 1z3`, and step until r8 lands you
;;;   in .usage -- you will see the program leave through a door it was handed
;;;   three instructions earlier.
;;;
;;;   ONE MORE THING TO INSPECT, about labels rather than the stack: both `main`
;;;   and `between` define a local label called `.L`. They do not collide,
;;;   because a NASM label beginning with '.' belongs to the most recent
;;;   non-local label. In gdb they appear as `main.L` and `between.L`. Type
;;;   `info functions` and `info line main.L` to see the two of them coexist.
;;; ============================================================================

section .data                                ; initialised, writable data
fmt_output:
        db `Answer: %lld\n\0`                ; printf format: one 64-bit signed decimal
fmt_usage:
        db `Usage: code-0016 hex, where hex = {0..9|a..f|A..F}+\n\0`

extern printf, fprintf, exit, stderr         ; supplied by the C library. Note there is
                                             ;   no atoll here -- the whole point is doing the
                                             ;   conversion ourselves.
global main                                  ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- parse argv[1] as hexadecimal and print its value.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 on a bad character
;;;   Registers   : rbx = the string cursor (clobbered without saving -- see
;;;                       the header note)
;;;                 rax = the accumulated value (Horner's method)
;;;                 rdi = the current character, zero-extended to 64 bits
;;;                 rsi/rdx/rcx/r8 = arguments to the `between` classifier
;;;   How it works: walks the string one byte at a time. Each byte is offered to
;;;                 `between` up to three times -- once per valid range -- and
;;;                 `between` jumps either to the matching digit handler or on
;;;                 to the next test. The last test's "outside" continuation is
;;;                 the error exit, so an invalid character needs no explicit
;;;                 check.
;;; ----------------------------------------------------------------------------
main:
        push rbp                             ; back up the frame-pointer (rbp is callee-saved)
        mov rbp, rsp                         ; set fp to the base of current frame -- the anchor
        and rsp, -16                         ; align stack by 16 (for printf/scanf): clear the
                                             ;   low 4 bits of rsp

        cmp rdi, 2                           ; argc == 2 -- subtract, keep only the flags
        jne .usage                           ; print usage if not

        mov rbx, qword [rsi + 8*1]           ; argv[1] -- the address of the hex string. rbx
                                             ;   is the cursor for the rest of the function; it
                                             ;   is CALLEE-SAVED and is not being preserved
                                             ;   (see the header note).
        mov rax, 0                           ; the accumulator starts at zero: the value of the
                                             ;   empty prefix of the string
.L:
        cmp byte [rbx], `\0`                 ; have we reached the NUL terminator? `byte`
                                             ;   makes this a one-byte comparison against 0.
        je .finished                         ; end of string: print the answer

        movzx rdi, byte [rbx]                ; extend byte to 64-bit quad-word.
                                             ;   `movzx` = MOVe with Zero eXtension: load one
                                             ;   byte and fill the upper 56 bits with zeros.
                                             ;   Necessary because `between` compares full
                                             ;   64-bit registers; `movsx` (sign-extend) would
                                             ;   turn bytes >= 0x80 into negatives.
        mov rsi, '0'                         ; lower bound of the first range. A character in
                                             ;   single quotes is just its ASCII code (0x30).
        mov rdx, '9'                         ; upper bound (0x39)
        mov rcx, .digit_0_to_9               ; continuation if the character IS in range
        mov r8, .cont1                       ; continuation if it is NOT: try the next range
        jmp between                          ; JMP, not CALL -- nothing is pushed
.cont1:
        mov rsi, 'a'                         ; lower bound of the lowercase range (0x61)
        mov rdx, 'f'                         ; upper bound (0x66)
        mov rcx, .digit_a_to_f               ; continuation on success
        mov r8, .cont2                       ; continuation on failure: try uppercase
        jmp between
.cont2:
        mov rsi, 'A'                         ; lower bound of the uppercase range (0x41)
        mov rdx, 'F'                         ; upper bound (0x46)
        mov rcx, .digit_A_to_F               ; continuation on success
        mov r8, .usage                       ; THE ERROR EXIT AS A CONTINUATION. Nothing valid
                                             ;   is left to try, so "outside this range" means
                                             ;   "invalid character" -- and the failure path is
                                             ;   just another address to jump to.
        jmp between

;;; --- the three digit handlers. Each folds one character into the accumulator
;;; --- with Horner's rule and converges on .skip_and_continue.
.digit_0_to_9:
        lea rax, [2*rax]                     ; rax := 2*rax. Step one of multiplying by 16;
                                             ;   the address unit's scale can only be 1, 2, 4
                                             ;   or 8, so 16 needs two steps. `lea` computes an
                                             ;   address expression and KEEPS THE NUMBER --
                                             ;   no memory is read and no flags are set.
        lea rax, [rdi + 8*rax - '0']         ; rax := 8*(2*rax) + rdi - '0'
                                             ;   = 16*rax + (c - '0'). Three operations in one
                                             ;   instruction: the scale-by-8, the add of the
                                             ;   character, and the ASCII bias subtraction --
                                             ;   which NASM folds into the displacement field at
                                             ;   assembly time.
        jmp .skip_and_continue

.digit_a_to_f:
        lea rax, [2*rax]                     ; rax := 2*rax, as above
        lea rax, [rdi + 8*rax - ('a' - 10)]  ; 16*rax + (c - 'a' + 10), so 'a' maps
                                             ;   to 10 and 'f' to 15. ('a' - 10) is computed by
                                             ;   the assembler, not at run time.
        jmp .skip_and_continue

.digit_A_to_F:
        lea rax, [2*rax]                     ; rax := 2*rax
        lea rax, [rdi + 8*rax - ('A' - 10)]  ; 16*rax + (c - 'A' + 10), the
                                             ;   uppercase equivalent. No `jmp` follows: control
                                             ;   FALLS THROUGH into .skip_and_continue below.

.skip_and_continue:
        inc rbx                              ; advance the cursor one BYTE (characters are one
                                             ;   byte each, so the increment is 1, not 8)
        jmp .L                               ; back to the top of the loop

.finished:
        mov rdi, fmt_output                  ; format string for output (printf argument 1)
        mov rsi, rax                         ; integer value (printf argument 2)
        mov rax, 0                           ; no fp registers in use (the variadic rule)
        call printf

        mov rax, 0                           ; status OK for OS

        mov rsp, rbp                         ; restore original stack-pointer from the anchor
        pop rbp                              ; set fp to point to previous frame
        ret                                  ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; main.usage -- wrong argument count, or an invalid character. NEVER RETURNS.
;;;   Reached by an ordinary `jne` from the argc test, and -- more interestingly
;;;   -- as the "outside" CONTINUATION of the last `between` test, i.e. by an
;;;   indirect `jmp r8` from inside the classifier.
;;; ----------------------------------------------------------------------------
.usage:
        mov rdi, qword [stderr]              ; errors go to stderr. Brackets: `stderr` is a
                                             ;   VARIABLE holding a FILE*; load its contents.
        mov rsi, fmt_usage                   ; explain correct usage (fprintf's argument 2)
        mov rax, 0                           ; no fp registers in use
        call fprintf                         ; send output to stderr...

        mov rax, -1                          ; status NOT OK
        call exit                            ; exit as per error. Never returns.

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
;;;   Stack cost : zero. Nothing is pushed and rsp is untouched.
;;;   Clobbers   : nothing; it only reads registers and jumps.
;;;
;;;   Here it is used as a CHARACTER CLASSIFIER, three times per character. Note
;;;   that its `.L` is a different label from main's `.L` -- a '.'-prefixed name
;;;   belongs to the nearest preceding non-local label, so they are really
;;;   `between.L` and `main.L`.
;;; ----------------------------------------------------------------------------
between:
        cmp rdi, rsi                         ; n - lo, flags only
        jl .L                                ; `jl` = jump if less (signed): below the range
        cmp rdi, rdx                         ; n - hi, flags only
        jg .L                                ; `jg` = jump if greater (signed): above the range
        jmp rcx                              ; in range: INDIRECT jump to the "inside"
                                             ;   continuation, whose address is the value in rcx
.L:
        jmp r8                               ; out of range: indirect jump to the "outside"
                                             ;   continuation

section .note.GNU-stack noalloc noexec       ; required Linux marker: stack is not exec
