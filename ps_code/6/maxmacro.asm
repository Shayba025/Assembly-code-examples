;;; ============================================================================
;;; maxmacro.asm -- NASM macros: naming a pattern instead of repeating it
;;; Practice session 6                       (study annotations added)
;;; The original header reads: "max-with-macros.asm / Programmer: Gemini AI
;;; (based on Mayer Goldberg)"
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Reads the numbers on the command line and prints the largest.
;;;   (Verified: `3 9 -2 7` prints `The maximum of 4 number(s) is 9`.)
;;;
;;;   THE SUBJECT IS MACROS, and there are two of them. A NASM macro is expanded
;;;   by the PREPROCESSOR, before assembly begins -- it generates no code of its
;;;   own, it is textual substitution with parameters. `%1`, `%2`, `%3` are the
;;;   arguments; the number after the name says how many there are.
;;;
;;;       %macro PRINT_MSG 3        three arguments
;;;           mov rdi, %1
;;;           ...
;;;       %endmacro
;;;
;;;   Written once, `PRINT_MSG fmt, count, value` then stands for five
;;;   instructions. Compare code-0023.asm in "lectures code ", whose `fldlit`
;;;   macro does something genuinely impossible to write inline.
;;;
;;;   THE IMPORTANT DETAIL IS `%%skip`. A macro that contains a label cannot use
;;;   an ordinary name, because expanding it twice would define that label twice
;;;   and the assembly would fail. `%%name` makes NASM invent a FRESH, UNIQUE
;;;   label at every expansion. The original comment says exactly this. You met
;;;   the same construct in ps_code/4, where `%%L` marks the return address inside
;;;   the hand-made CALL macro.
;;;
;;;   MACROS ARE NOT FUNCTIONS, and the difference matters:
;;;       a macro       is copied in at every use. No call, no return, no stack.
;;;                     Fast, and it makes the program bigger.
;;;       a function    exists once. Every use costs a `call`, a `ret`, and 8
;;;                     bytes of stack for the return address.
;;;   `UPDATE_MAX` is used once here, so it saves nothing -- but it names the
;;;   idea, which is the other reason macros exist.
;;;
;;;   THE ALGORITHM is the standard running-maximum: start at the smallest
;;;   possible value and replace it whenever something larger turns up.
;;;       max_val: dq -9223372036854775808
;;;   That is -2^63, the most negative 64-bit signed integer, so ANY input beats
;;;   it. Picking a sentinel that is genuinely smaller than every possible input
;;;   is what makes the loop need no special case for the first element.
;;;
;;;   `jle` IS A SIGNED COMPARISON, which is correct here -- negative arguments
;;;   must compare as smaller. Using `jbe` (unsigned) would make -2 look enormous.
;;;
;;;   A LATENT BUG WORTH KNOWING ABOUT: `atoi` returns an `int`, i.e. 32 bits, and
;;;   the ABI does not promise anything about the upper 32 bits of rax. This code
;;;   compares the FULL 64-bit rax. In practice glibc sign-extends and the program
;;;   works (check: `-5 -9` correctly gives -5), but the robust version would use
;;;   `atoll`, which really does return a 64-bit value -- as every file in
;;;   "lectures code " does.
;;;
;;;   RUN IT WITH NO ARGUMENTS and you get "The maximum of 0 number(s) is
;;;   -9223372036854775808" -- the sentinel, leaking out because the loop never
;;;   ran. Compare code-0005.asm, which checks argc and refuses.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/6/maxmacro.asm" 3 9 -2 7
;;;   ./asm "ps_code/6/maxmacro.asm" -5 -9
;;;   ./asm "ps_code/6/maxmacro.asm" 42
;;;   ./asm "ps_code/6/maxmacro.asm"            # the sentinel leaks out
;;;
;;;   See what the macros expanded to -- this is the most useful thing you can do
;;;   with a macro-heavy file:
;;;   docker run --rm -v "$PWD/ps_code/6:/work" -w /work asm-course \
;;;       nasm -e maxmacro.asm | grep -v '^ *$' | tail -40
;;;   `nasm -e` runs ONLY the preprocessor and prints the result. Every macro is
;;;   gone, replaced by the instructions it stands for.
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/6/maxmacro.asm" 3 9 -2 7
;;;
;;;   Useful session -- watch the running maximum change:
;;;     break atoi
;;;     c
;;;     x/s $rdi                  the string about to be converted
;;;     finish
;;;     p $rax                    the number
;;;     p (long)max_val           the best so far
;;;     c                         next argument
;;;
;;;   Watch the macro's local label in action:
;;;     disassemble main          the UPDATE_MAX expansion is inline -- a cmp, a
;;;                               conditional jump, and a store. No `call`
;;;                               anywhere, because a macro is not a function.
;;;     info line *$pc
;;;
;;;   And see the sentinel:
;;;     break main
;;;     p (long)max_val           -9223372036854775808
;;;     p/x (long)max_val         0x8000000000000000 -- the sign bit alone
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE MACROS COST NOTHING ON THE STACK, and that is the whole difference
;;;   between a macro and a function. Break inside the UPDATE_MAX expansion and
;;;   check:
;;;       bt                      one frame -- you are still in `main`
;;;       p $rsp                  unchanged
;;;   Now compare with `call atoi` two lines earlier:
;;;       break atoi
;;;       c
;;;       bt                      TWO frames
;;;       p $rsp                  8 lower -- the return address
;;;
;;;   THAT IS THE TRADE. A macro is free at run time and costs you code size at
;;;   every use; a function is compact and costs 8 bytes plus two jumps per call.
;;;   For three instructions, inline wins. For thirty, it does not. It is exactly
;;;   the decision a C compiler makes when it decides whether to inline, and
;;;   `%macro` is you making it by hand.
;;;
;;;   NOTE ALSO WHERE THE STATE LIVES. `i`, `max_val`, `argc` and `argv` are all
;;;   in .data or .bss, not in registers and not on the stack -- because `call
;;;   atoi` and `call printf` would destroy any caller-saved register holding
;;;   them. This is the same choice code-0003.asm makes, and the third of the
;;;   four answers you have now seen to "a value must outlive a call":
;;;       push/pop around the call      code-0002.asm
;;;       keep it in .data              code-0003.asm, this file
;;;       keep it in a stack local      code-0015.asm, code-0018.asm
;;;       keep it in a callee-saved reg multboard.asm in this folder
;;;
;;;   One alignment note the source does not mention: there is no `and rsp, -16`,
;;;   and it works out anyway. `call main` left rsp at 8 mod 16 and `push rbp`
;;;   made it 0, so each subsequent `call` sees the 8 mod 16 the ABI promises.
;;;   Verify with `break printf` then `p $rsp % 16`.
;;; ============================================================================

;;; max-with-macros.asm
;;; Programmer: Gemini AI (based on Mayer Goldberg)

; --- הגדרת מאקרו 1: הדפסת הודעה עם מספר ---
%macro PRINT_MSG 3                      ; שם המאקרו, וכמות פרמטרים
                                        ;   `%macro NAME n` begins a definition taking n arguments.
                                        ;   Everything up to %endmacro is substituted by the
                                        ;   PREPROCESSOR, before assembly. It emits no code itself.
    mov rdi, %1                         ; מחרוזת הפורמט
                                        ;   %1 is the first macro argument -- printf's format string
    mov rsi, %2                         ; הפרמטר הראשון (כמות המספרים)
                                        ;   %2 -- printf argument 2
    mov rdx, %3                         ; הפרמטר השני (הערך)
                                        ;   %3 -- printf argument 3
    mov rax, 0
                                        ;   THE VARIADIC RULE: rax = the number of VECTOR registers
                                        ;   carrying arguments. No floats here, so 0.
    call printf
                                        ;   the only real `call` inside a macro in this file
%endmacro
                                        ;   end of the definition

; --- הגדרת מאקרו 2: עדכון מקסימום ---
%macro UPDATE_MAX 2                     ; מקבל ערך נוכחי וכתובת של המקסימום
                                        ;   a two-argument macro: a value, and the ADDRESS of the
                                        ;   current maximum
    cmp %1, [%2]
                                        ;   compare the value against the stored maximum. Brackets
                                        ;   on %2 mean "the contents of that address".
    jle %%skip                          ; שימוש ב-%% כדי ליצור לייבל מקומי למאקרו
                                        ;   `jle` = jump if less or equal, SIGNED -- correct, since
                                        ;   negative inputs must compare as smaller.
                                        ;   `%%skip` is a MACRO-LOCAL label: NASM invents a unique
                                        ;   name at each expansion, so the macro can be used more
                                        ;   than once without a duplicate-label error.
    mov [%2], %1
                                        ;   the new value is larger, so store it
%%skip:
                                        ;   the macro-local label itself
%endmacro
                                        ;   end of the definition

section .data
                                        ;   initialised, writable data
fmt_max: db `The maximum of %ld number(s) is %ld\n\0`
                                        ;   printf format: two 64-bit signed decimals
i:       dq 1
                                        ;   the loop index, starting at 1 so argv[0] (the program's
                                        ;   own name) is skipped
max_val: dq -9223372036854775808
                                        ;   THE SENTINEL: -2^63, the most negative 64-bit signed
                                        ;   integer. Every possible input beats it, which is what
                                        ;   lets the loop skip a special case for the first element.
                                        ;   In hex it is 0x8000000000000000 -- the sign bit alone.

section .bss
                                        ;   zero-filled at load time, no file space
argc: resq 1
                                        ;   one quadword to stash the incoming argc
argv: resq 1
                                        ;   ...and one for the argv pointer

extern atoi, printf
                                        ;   supplied by the C library. NOTE `atoi`, not `atoll` --
                                        ;   see the 32-bit caveat in the header.
global main
                                        ;   export `main` for the C library start-up
section .text
                                        ;   the executable-code section
main:
    push rbp
                                        ;   prologue: save the caller's frame pointer. Also takes
                                        ;   rsp from 8 mod 16 to 0 mod 16, which is what makes the
                                        ;   calls below legal without an `and rsp, -16`.
    mov rbp, rsp
                                        ;   anchor the frame

    mov qword [argc], rdi
                                        ;   save argc out of the volatile register rdi and into
                                        ;   memory, where no callee can touch it
    mov qword [argv], rsi
                                        ;   same for argv

.L:
                                        ;   top of the loop. A '.'-prefixed name is LOCAL to the
                                        ;   preceding non-local label, so this is really `main.L`.
    mov rax, qword [i]
                                        ;   load the index
    cmp rax, qword [argc]
                                        ;   compare it against argc
    je .done
                                        ;   every argument has been consumed

    mov rdi, qword [argv]
                                        ;   rdi := the address of the argv array
    mov rdi, qword [rdi + 8*rax]
                                        ;   dereference element i. base + 8*index is the array idiom;
                                        ;   8 because each element is a 64-bit pointer. rdi is now
                                        ;   argv[i], a char* -- atoi's one argument.
    call atoi                           ; התוצאה ב-RAX
                                        ;   int atoi(const char *): pointer in rdi, result in rax.
                                        ;   Returns a 32-BIT int -- see the caveat in the header.

                                        ; שימוש במאקרו לעדכון המקסימום
    UPDATE_MAX rax, max_val
                                        ;   the macro expands INLINE here: a cmp, a conditional jump
                                        ;   and a store. No call, no stack, no return.

    inc qword [i]
                                        ;   ++i, incremented straight in memory so the calls cannot
                                        ;   disturb it
    jmp .L
                                        ;   round again

.done:
                                        ;   local to main, i.e. `main.done`
                                        ; שימוש במאקרו להדפסה
    mov rsi, qword [argc]
                                        ;   printf argument 2: the number of arguments...
    dec rsi
                                        ;   ...minus one, because argv[0] is the executable's name
    PRINT_MSG fmt_max, rsi, qword [max_val]
                                        ;   the second macro expands here into five instructions.
                                        ;   Note `mov rsi, rsi` is generated and is a harmless no-op --
                                        ;   an artefact of passing rsi as %2.

    mov rsp, rbp
                                        ;   epilogue: restore rsp from the anchor
    pop rbp
                                        ;   restore the caller's frame pointer
    ret
                                        ;   pop the return address into rip. rax is not reset, so the
                                        ;   exit status is printf's character count.
