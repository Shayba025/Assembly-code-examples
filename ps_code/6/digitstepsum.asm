;;; ============================================================================
;;; digitstepsum.asm -- sum of digits, written in a continuation-passing STYLE
;;; Practice session 6                       (study annotations added)
;;; The original header reads: "sum-digits-cps.asm ... inspired by the structure
;;; of Mayer Goldberg's code-0005.asm"
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Reads one integer from the command line and prints the sum of its decimal
;;;   digits.
;;;   (Verified: `12345` prints `The sum of digits is: 15`.)
;;;
;;;   IT IS PRESENTED AS CONTINUATION-PASSING STYLE, after code-0005.asm in
;;;   "lectures code ". The idea there was that a routine is handed "where to go
;;;   next" as an explicit argument in a register, and finishes with `jmp rcx`
;;;   instead of `ret`. Look at line
;;;       mov rdx, print_result
;;;   -- rdx is being loaded with a code address, exactly in that spirit.
;;;
;;;   *** BUT THE CONTINUATION IS NEVER ACTUALLY USED, AND IT CANNOT BE. ***
;;;   Two lines later, inside `digit_step`, comes
;;;       mov rdx, 0                  ; clear rdx before div
;;;   which is mandatory before a `div` -- and which destroys the continuation.
;;;   The program then finishes with a HARD-CODED `jmp print_result` rather than
;;;   `jmp rdx`. So the address in rdx is set once, immediately overwritten, and
;;;   never read.
;;;
;;;   THIS IS WORTH MORE THAN A WORKING EXAMPLE WOULD BE, because the reason it
;;;   fails is instructive: rdx is not a free register. `div` commandeers it as
;;;   the high half of the dividend and as the destination for the remainder --
;;;   a hardware convention you cannot negotiate with. code-0005.asm keeps its
;;;   continuations in rcx and r8 precisely because its `between` routine does no
;;;   arithmetic at all. THE FIX HERE is one instruction: hold the continuation
;;;   in a register `div` does not touch (r12, say, which is also callee-saved
;;;   and survives calls) and end with `jmp r12`. Try it -- the program will
;;;   behave identically and the CPS will be real.
;;;
;;;   THE ALGORITHM ITSELF is the standard digit loop: divide by 10, add the
;;;   remainder to a running total, repeat until the number is zero. Compare
;;;   sum_digits.asm in ps_code/5, which does the same thing RECURSIVELY and
;;;   therefore has to spill values to the stack at every level. This version is
;;;   a loop and uses no stack at all -- the same tail-call transformation that
;;;   gcd.asm in this folder applies to Euclid.
;;;
;;;   THE `div` CONTRACT, since it is what breaks the CPS:
;;;       xor rdx, rdx / mov rdx, 0   clear the HIGH half of the dividend
;;;       div rcx                     rax := (rdx:rax)/rcx , rdx := remainder
;;;   One operand, three hidden registers. Leave junk in rdx and you get a wrong
;;;   answer or a #DE exception that arrives as SIGFPE.
;;;
;;;   A SMALL BUG: the usage message is printed with `printf`, i.e. to STDOUT,
;;;   and the program still exits 0. Diagnostics belong on stderr and errors
;;;   deserve a non-zero status -- compare code-0005.asm, which uses `fprintf`
;;;   with `stderr` and then `exit(-1)`. Note `exit` is even declared `extern`
;;;   here and never called.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/6/digitstepsum.asm" 12345        # 15
;;;   ./asm "ps_code/6/digitstepsum.asm" 999999999    # 81
;;;   ./asm "ps_code/6/digitstepsum.asm" 7            # 7
;;;   ./asm "ps_code/6/digitstepsum.asm" 0            # 0
;;;   ./asm "ps_code/6/digitstepsum.asm"              # usage message
;;;
;;;   Check it against the shell:
;;;   for n in 12345 999999999 1000000 42; do
;;;       printf "%-12s " $n
;;;       ./asm "ps_code/6/digitstepsum.asm" $n
;;;   done
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/6/digitstepsum.asm" 12345
;;;
;;;   THE session for this file -- watch the continuation being destroyed:
;;;     break digitstepsum.asm:NN     NN on the `mov rdx, print_result` line
;;;     c
;;;     si
;;;     info symbol $rdx              gdb names the label: the continuation is set
;;;     break digitstepsum.asm:NN     NN on the `mov rdx, 0` line
;;;     c
;;;     info symbol $rdx              still print_result
;;;     si
;;;     p $rdx                        0. THE CONTINUATION IS GONE, two instructions
;;;                                   after it was created.
;;;
;;;   Watch the digits being peeled off:
;;;     break digitstepsum.asm:NN     NN on the `div rcx` line
;;;     c
;;;     display/d $rdi                what is left of the number
;;;     display/d $rsi                the running sum
;;;     si
;;;     p $rdx                        this digit
;;;     c                             5, then 4, then 3, then 2, then 1
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE WHOLE COMPUTATION USES NO STACK AT ALL. Break anywhere inside
;;;   `digit_step` and check:
;;;       p $rsp                      identical on every iteration
;;;       bt                          one frame, always
;;;   `digit_step`, `.finish` and `print_result` are reached by `jmp`, never by
;;;   `call`, so nothing is ever pushed. The three of them are not really
;;;   separate functions -- they are labelled regions of `main`, and gdb will
;;;   often report them that way.
;;;
;;;   THAT IS THE POINT OF THE CPS IDEA, even in this half-finished form. The
;;;   distinction to hold on to:
;;;       call   go there AND remember to come back    -- costs 8 bytes of stack
;;;       jmp    go there                              -- costs nothing
;;;   A continuation is a return address that you carry in a REGISTER and jump to
;;;   explicitly, instead of one that `call` hides on the stack for you. Once you
;;;   see that, `call` and `ret` stop being primitive -- which is exactly what
;;;   call_return_demo.asm in ps_code/4 demonstrates by writing them out.
;;;
;;;   Try the repair suggested in the header -- keep the continuation in r12 and
;;;   end `.finish` with `jmp r12` -- and then, in gdb:
;;;       info symbol $r12            at the end, it still names print_result
;;;       si                          and the jump goes there
;;;   You will have written a genuine continuation-passing program, and `p $rsp`
;;;   will still never have moved.
;;; ============================================================================

;;; sum-digits-cps.asm
;;; מחשב סכום ספרות של מספר בשיטת המשכיות (Continuations)
;;; השראה מהמבנה של Mayer Goldberg בקובץ code-0005.asm

section .data
                                        ;   initialised, writable data
    fmt_res:   db `The sum of digits is: %ld\n\0`
                                        ;   printf format: one 64-bit signed decimal.
                                        ;   Backquotes make \n and \0 real control characters.
    fmt_usage: db `Usage: sum-digits <positive integer>\n\0`
                                        ;   the message shown when no argument is given.
                                        ;   NOTE it is printed to STDOUT below, not stderr.

section .text
                                        ;   the executable-code section
extern atoll, printf, exit
                                        ;   supplied by the C library. `exit` is declared
                                        ;   but never actually called -- see the header.
global main
                                        ;   export `main` for the C library start-up

main:
    push rbp
                                        ;   prologue: save the caller's frame pointer
                                        ;   (rbp is callee-saved)
    mov rbp, rsp
                                        ;   anchor the frame at the current stack top
    and rsp, -16                        ; יישור המחסנית כפי שראינו ב
                                        ;   round rsp DOWN to a multiple of 16 by clearing its
                                        ;   low 4 bits (-16 == 0xFFFF...FFF0). The alignment
                                        ;   every `call` requires.

    cmp rdi, 2                          ; בדיקת argc
                                        ;   argc == 2? `cmp` subtracts and keeps only the flags
    jne error_usage
                                        ;   `jne` = jump if not equal: wrong argument count

    mov rdi, qword [rsi + 8*1]          ; argv[1]
                                        ;   rsi is argv; base + 8*1 selects element 1, a char*.
                                        ;   This is atoll's one argument.
    call atoll                          ; המרה למספר 64 ביט (RAX)
                                        ;   long long atoll(const char *): pointer in rdi,
                                        ;   result in rax

    mov rdi, rax                        ; המספר לעיבוד
                                        ;   rdi := the number to process. From here to the end,
                                        ;   rdi means "what is left of n".
    mov rsi, 0                          ; אוגר צובר (הסכום)
                                        ;   rsi := 0, the running sum of digits

                                        ; הגדרת ה"המשכיות": לאן ללכת כשנסיים את החישוב
    mov rdx, print_result
                                        ;   THE CONTINUATION: load the ADDRESS of print_result
                                        ;   into rdx. A bare label used as a value is its
                                        ;   address -- code addresses are ordinary numbers.
                                        ;   *** AND IT IS DESTROYED TWELVE LINES BELOW, by the
                                        ;   `mov rdx, 0` that `div` requires. See the header. ***
    jmp digit_step                      ; קפיצה לצעד הראשון
                                        ;   JMP, not CALL: nothing is pushed, so this costs
                                        ;   nothing on the stack

digit_step:
                                        ;   not really a function -- a labelled region of main,
                                        ;   entered and left by jumps only
                                        ; rdi = המספר שנשאר לעבד
                                        ; rsi = הסכום שנצבר עד כה
                                        ; rdx = הכתובת להמשך (ההמשכיות)

    cmp rdi, 0
                                        ;   is there anything left of the number?
    je .finish                          ; אם המספר התרוקן, קפוץ לסיום
                                        ;   `.finish` is a LOCAL label: a NASM name starting
                                        ;   with '.' belongs to the nearest preceding non-local
                                        ;   label, so this is really `digit_step.finish`.

                                        ; בידוד הספרה האחרונה בעזרת חילוק ב-10
    mov rax, rdi
                                        ;   `div` always divides RDX:RAX, so the dividend must
                                        ;   be moved into rax first
    mov rcx, 10
                                        ;   the divisor. `div` takes no immediate operand, so
                                        ;   the 10 has to live in a register.
    mov rdx, 0                          ; איפוס rdx לפני div (חובה!)
                                        ;   MANDATORY: rdx is the HIGH 64 bits of the dividend.
                                        ;   Junk there gives a wrong answer or a divide-error
                                        ;   exception. `xor rdx, rdx` is the idiomatic spelling.
                                        ;   *** THIS IS THE LINE THAT DESTROYS THE CONTINUATION
                                        ;   SET IN main. *** See the header.
    div rcx                             ; rax = מנה, rdx = שארית (הספרה)
                                        ;   ONE INSTRUCTION, TWO ANSWERS: unsigned divide,
                                        ;   quotient to RAX and REMAINDER TO RDX. The remainder
                                        ;   is the last decimal digit.

    add rsi, rdx                        ; הוספת הספרה לסכום הכללי ב-rsi
                                        ;   accumulate the digit into the running total
    mov rdi, rax                        ; עדכון המספר שנשאר (המנה)
                                        ;   what remains of the number: n/10

                                        ; כאן הקסם: במקום ret, אנחנו פשוט קופצים חזרה לתחילת הצעד
                                        ; הכתובת המקורית לסיום עדיין "נמצאת באוויר" (לא השתמשה במחסנית)
    jmp digit_step
                                        ;   the loop, written as a jump. Nothing is pushed, so
                                        ;   the stack never grows however many digits there are.

.finish:
                                        ;   local to digit_step, i.e. `digit_step.finish`
                                        ; סיימנו את כל הספרות, עכשיו עוברים ליעד הסופי שנקבע ב-main
                                        ; בגישת CPS אמיתית, היינו קופצים לכתובת דינמית, כאן זהו .print_result
    jmp print_result
                                        ;   A HARD-CODED jump. In real CPS this would be
                                        ;   `jmp rdx` -- but rdx no longer holds the address.

print_result:
                                        ;   another labelled region, reached only by jumps
    mov rdi, fmt_res
                                        ;   printf argument 1: the format string
                                        ; rsi כבר מכיל את הסכום הסופי
    mov rax, 0
                                        ;   THE VARIADIC RULE: rax = the number of VECTOR
                                        ;   registers carrying arguments. No floats, so 0.
    call printf
    jmp end
                                        ;   converge on the shared exit

error_usage:
                                        ;   the error path -- reached by `jne` from the argc test
    mov rdi, fmt_usage
                                        ;   printf argument 1. NOTE: printf writes to STDOUT.
                                        ;   Diagnostics belong on stderr -- compare code-0005.asm.
    mov rax, 0
                                        ;   0 vector registers in use
    call printf

end:
                                        ;   the single shared exit, for both the success and the
                                        ;   error paths
    mov rsp, rbp
                                        ;   epilogue: restore rsp from the anchor, undoing the
                                        ;   alignment
    pop rbp
                                        ;   restore the caller's frame pointer
    ret
                                        ;   pop the return address into rip. rax is not reset,
                                        ;   so the exit status is printf's character count -- and
                                        ;   it is the same on the error path, which is a bug.
