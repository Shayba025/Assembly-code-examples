;;; ============================================================================
;;; code-0023.asm -- Solving the quadratic equation using the x87 FPU
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Reads a, b and c from the command line and solves a*x^2 + b*x + c = 0 in
;;;   80-bit extended precision, reporting two roots, one root, or none.
;;;
;;;   THE WHOLE POINT IS THE x87 FPU, WHICH IS A STACK MACHINE. This is the one
;;;   part of the x86 architecture that does not have named registers you can
;;;   assign to. Instead there are eight 80-bit slots arranged as a stack:
;;;
;;;       st0   the TOP -- every instruction's implicit operand
;;;       st1   one below the top
;;;       ...
;;;       st7   the bottom
;;;
;;;   `fld <mem>` PUSHES a value (everything shifts down a slot). `fstp <mem>`
;;;   POPS one off. Arithmetic instructions ending in `p` -- `faddp`, `fmulp`,
;;;   `fsubp`, `fdivp` -- combine the top two slots and POP, so the stack shrinks
;;;   by one. This is Reverse Polish Notation, in hardware.
;;;
;;;   THAT IS WHY EVERY x87 LINE IN THIS FILE HAS A PICTURE NEXT TO IT. The
;;;   comment `; -b   -b + t1   2a` is not decoration -- it is the contents of
;;;   the FPU stack after that instruction, top-of-stack listed LAST. Read the
;;;   column of those comments downward and you can follow the whole computation
;;;   without simulating a single instruction in your head. WRITE COMMENTS LIKE
;;;   THIS WHENEVER YOU USE x87; without them the code is genuinely unreadable.
;;;
;;;   THE INSTRUCTIONS, in the order you meet them:
;;;       fninit          reset the FPU: empty the stack, clear the flags
;;;       fld tword [m]   push an 80-bit ("tword" = ten-byte) value from memory
;;;       fld st0         push a copy of the top -- the RPN way to say "dup"
;;;       fldz            push the constant 0.0
;;;       fstp tword [m]  pop the top into memory
;;;       fstp st0        pop the top and throw it away
;;;       faddp/fmulp/fsubp/fdivp    st1 op st0 -> st1, then pop
;;;       fchs            negate the top in place
;;;       fsqrt           square root of the top, in place
;;;       fucomip st1     compare st0 with st1, set the ORDINARY flags (so you
;;;                       can use ja/jb afterwards), and pop
;;;
;;;   NOTE THE ARGUMENT ORDER TRAP: `fsubp` computes st1 - st0, and `fdivp`
;;;   computes st1 / st0. The value pushed FIRST is the left operand. Get this
;;;   backwards and you silently compute the reciprocal or the negation.
;;;
;;;   THE `fldlit` MACRO at the top is a neat trick worth understanding. x87 has
;;;   no "load an immediate" instruction -- constants must come from memory. So
;;;   the macro plants the ten bytes of the constant IN THE MIDDLE OF THE CODE,
;;;   jumps over them, and loads from there:
;;;       jmp %%Lcont      ; skip over the data
;;;   %%Lflit: dt 4.0      ; the constant, sitting inside .text
;;;   %%Lcont: fld tword [%%Lflit]
;;;   `%%` makes the labels unique per expansion, so the macro can be used more
;;;   than once. Data living inside the instruction stream is unusual and worth
;;;   noticing -- `x/3i` around it in gdb produces nonsense, because the
;;;   disassembler tries to decode the number as instructions.
;;;
;;;   WHY EPSILON: comparing a floating-point discriminant against exact zero is
;;;   almost always wrong, because rounding makes an exact double root come out
;;;   as 1e-19 instead of 0. So `|desc| < epsilon` is treated as "one root". The
;;;   choice of 1.0e-17 is a judgement call about how much error you expect.
;;;
;;;   PASSING A long double TO printf is unlike anything else in this course.
;;;   Long doubles are NOT passed in registers -- they go ON THE STACK, each
;;;   occupying 16 bytes (10 bytes of value, 6 of padding, to keep the alignment).
;;;   Hence `sub rsp, 16*2` and two `fstp tword [rsp + 16*k]`. And rax must still
;;;   be 0, because rax counts XMM registers, and x87 values are not in XMM
;;;   registers at all.
;;;
;;;   `rest 1` in .bss reserves one ten-byte extended-precision slot -- the
;;;   80-bit sibling of resq/resd/resb.
;;;
;;;   A BUG WORTH SPOTTING: rbx is used to reload argv and is never saved, though
;;;   it is CALLEE-SAVED. Also, the first sscanf reads argv[1] via rsi directly
;;;   and only afterwards reloads from the frame -- correct, but the comments on
;;;   the second and third blocks say argv[1] and argv[2] when they mean argv[2]
;;;   and argv[3].
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0023.asm" 1 -3 2       # two roots: 2 and 1
;;;   ./asm "lectures code /code-0023.asm" 1 -2 1       # one root: 1
;;;   ./asm "lectures code /code-0023.asm" 1 2 5        # no real roots
;;;   ./asm "lectures code /code-0023.asm" 2 5 -3       # 0.5 and -3
;;;   ./asm "lectures code /code-0023.asm" 1 0 -2       # +/- sqrt 2, to 18 digits
;;;   ./asm "lectures code /code-0023.asm" 1 2          # usage error
;;;   ./asm "lectures code /code-0023.asm" 1 x 3        # usage error (sscanf fails)
;;;
;;;   See the precision you are paying for -- 18 significant digits:
;;;   ./asm "lectures code /code-0023.asm" 1 0 -2
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0023.asm" 1 -3 2
;;;
;;;   THE COMMAND THAT MATTERS HERE IS `info float`. It prints the entire x87
;;;   stack, slot by slot, plus the status word. Use it after every step:
;;;     break code-0023.asm:NN     put NN on the `fninit` line
;;;     c
;;;     info float                 an empty stack
;;;     si                         fld tword [b]
;;;     info float                 one value -- and check it really is b
;;;     si                         fld st0
;;;     info float                 TWO copies now
;;;     si                         fmulp -- two become one
;;;     info float                 b squared
;;;
;;;   Or watch just the top three slots as you step:
;;;     display $st0
;;;     display $st1
;;;     display $st2
;;;     si  si  si  ...
;;;   Compare what you see against the picture in the comment on each line. When
;;;   they disagree, you have found either your misunderstanding or a bug.
;;;
;;;   Look at the stored intermediates:
;;;     p (long double)desc
;;;     p (long double)t1
;;;     p (long double)t2
;;;     p (long double)x1
;;;
;;;   And catch the long doubles being handed to printf:
;;;     break printf
;;;     c
;;;     p *(long double*)$rsp        the first argument, x1
;;;     p *(long double*)($rsp+16)   the second, x2
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THIS FILE HAS TWO STACKS AT ONCE, AND THAT IS THE LESSON.
;;;
;;;   The x87 register stack is eight slots deep, lives inside the CPU, is
;;;   addressed only relatively (st0, st1, ...) and is NOT in memory at all. The
;;;   call stack is as deep as your address space, lives in RAM, is addressed
;;;   absolutely through rsp and rbp, and holds return addresses and frames. They
;;;   have the word "stack" in common and nothing else. In gdb:
;;;       info float      the FPU stack
;;;       x/8gx $rsp      the call stack
;;;   Two completely different pictures, updated by different instructions.
;;;
;;;   THE PLACE THEY MEET is the printf call, and it is worth watching closely:
;;;       sub rsp, 16*2          make room on the CALL stack
;;;       fstp tword [rsp]       pop from the FPU stack INTO it
;;;       fstp tword [rsp + 16]  and again
;;;   Step those three instructions with `si`, running `info float` and
;;;   `x/4gx $rsp` after each. You will see the FPU stack shrink by one and the
;;;   memory fill in, twice. That is a value being transferred between the two
;;;   worlds -- and it is exactly what "long doubles are passed on the stack"
;;;   means in practice.
;;;
;;;   THE OVERFLOW YOU MUST RESPECT. The FPU stack has EXACTLY EIGHT SLOTS, and
;;;   there is no growing it. Push a ninth value and you do not get more memory,
;;;   you get an INVALID-OPERATION exception and a NaN. Try it in gdb:
;;;       break code-0023.asm:NN     anywhere in the x87 section
;;;       c
;;;       p $st0                     fine
;;;       # now, in the source, add nine consecutive `fld tword [a]` lines,
;;;       # rebuild, and look at `info float` -- the ninth is not there.
;;;   Every `fld` must be matched by a pop, which is exactly why the professor
;;;   wrote `fninit` at BOTH ends of the computation and why `.one_root` uses
;;;   `fstp st0` purely to discard a value. Leaking FPU stack slots is the x87
;;;   equivalent of leaking memory, and it takes only eight leaks to break.
;;;
;;;   ONE LAST THING TO SEE: `fucomip st1` sets the ORDINARY flags -- ZF, CF, PF
;;;   -- so that `ja` and `jb` work on floating-point comparisons. Break on it,
;;;   `info registers eflags`, `si`, and look again. That instruction is the
;;;   bridge from the FPU's world back into the integer branch machinery.
;;; ============================================================================

%macro fldlit 1                         ; a one-argument macro: `fldlit 4.0` pushes
                                        ;   the literal 4.0 onto the x87 stack. x87
                                        ;   cannot load an immediate, so the value
                                        ;   has to exist somewhere in memory.
        jmp %%Lcont                     ; step OVER the ten bytes of data below --
                                        ;   they are not instructions
%%Lflit:                                ; `%%` makes the label unique to each
                                        ;   expansion, so the macro can be used more
                                        ;   than once without a name collision
        dt %1                           ; `dt` = define ten bytes: the 80-bit
                                        ;   extended-precision form of the argument,
                                        ;   sitting INSIDE the code section
%%Lcont:
        fld tword [%%Lflit]             ; push those ten bytes onto the FPU stack
%endmacro

section .data                           ; initialised, writable data
fmt_long_double:
        db `%Lg\0`                      ; sscanf format: `L` = long double, `g` =
                                        ;   accept either 1.5 or 1.5e3 notation
fmt_usage:
        db `Usage: ./code-0023 <long double> <long double> <long double>\n\0`
fmt_no_real_solution:
        db `There are no solutions in ℝ! `
        db `Tell your instructor not to be so lazy, `
        db `and to add support for ℂ!\n\0`
                                        ; three `db` directives, only the last
                                        ;   terminated -- so this is ONE string
                                        ;   split across three source lines. The
                                        ;   blackboard-bold R and C are UTF-8.
fmt_one_solution:
        db `There is one solution: x = %.18Lg\n\0`
                                        ; %.18Lg prints a long double to 18
                                        ;   significant digits -- roughly what
                                        ;   80-bit precision actually buys you
fmt_two_solutions:
        db `There are two solutions: x₁ = %.18Lg, x₂ = %.18Lg\n\0`
                                        ; subscripted 1 and 2 in UTF-8; two
                                        ;   long-double conversions
epsilon:
        dt 1.0e-17                      ; `dt` = ten bytes: the tolerance below
                                        ;   which the discriminant counts as zero.
                                        ;   Comparing floats against exact 0 is
                                        ;   almost always a bug; this is the fix.

section .bss                            ; zero-filled at load time, no file space
a:
        rest 1                          ; `rest k` reserves k ten-byte extended
b:                                      ;   precision slots -- the 80-bit sibling
        rest 1                          ;   of resq/resd/resb. One slot per
c:                                      ;   coefficient...
        rest 1
desc:
        rest 1                          ; ...the discriminant b^2 - 4ac...
t1:
        rest 1                          ; ...sqrt(discriminant)...
t2:
        rest 1                          ; ...2a...
x1:
        rest 1                          ; ...and the two roots.
x2:
        rest 1

extern printf, fprintf, stderr, sscanf, exit
                                        ; sscanf is new: it parses a STRING rather
                                        ;   than stdin --
                                        ;   int sscanf(const char *s, const char
                                        ;              *fmt, ...);
global main                             ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- parse three long doubles and solve the quadratic.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 on bad input
;;;   Locals      : [rbp - 8*1] = argv, saved because sscanf destroys rsi
;;;   Clobbers    : rax, rbx (CALLEE-SAVED and unsaved -- see the header), and
;;;                 the whole x87 stack
;;;   How it works: three sscanf calls fill a, b and c in .bss. Then the x87
;;;                 section computes the discriminant, branches three ways, and
;;;                 each branch prints its answer. `fninit` bookends the whole
;;;                 floating-point computation.
;;;
;;;   READ THE x87 SECTION BY ITS RIGHT-HAND COLUMN. Each comment shows the
;;;   contents of the FPU stack AFTER that instruction, top-of-stack last.
;;; ----------------------------------------------------------------------------
main:
        push rbp                        ; back up the pointer to the previous frame
        mov rbp, rsp                    ; set fp to the base of the new frame
        sub rsp, 8*1                    ; we need to keep local variable for argv
        and rsp, -16                    ; align the stack for printing

;;; The activation frame
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | argv     | qword [rbp - 8*1] |

        cmp rdi, 4                      ; program + a + b + c --> 4 arguments
        jne .usage

        mov qword [rbp - 8*1], rsi      ; argv
                                        ;   saved into the frame at once, because
                                        ;   sscanf is entitled to destroy rsi
        mov rdi, qword [rsi + 8*1]      ; argv[1] == a
                                        ;   sscanf argument 1: the STRING to parse
        mov rsi, fmt_long_double        ; format for one (long double)
        mov rdx, a                      ; &a -- where to store the parsed value
        mov rax, 0                      ; no fp registers used (the variadic rule)
        call sscanf                     ; try to read one (long double)
        cmp rax, 1                      ; if failed,
        jne .usage                      ; ...complain!
                                        ;   sscanf returns HOW MANY items it
                                        ;   converted. Checking that count is the
                                        ;   only way to detect malformed input.

        mov rbx, qword [rbp - 8*1]      ; argv -- reloaded from the frame, since rsi
                                        ;   is gone. (rbx is callee-saved: bug.)
        mov rdi, qword [rbx + 8*2]      ; argv[1] == b
                                        ;   (the comment says argv[1]; the index 2
                                        ;   makes it argv[2], which is correct)
        mov rsi, fmt_long_double        ; format for one (long double)
        mov rdx, b                      ; &b
        mov rax, 0                      ; no fp registers used
        call sscanf                     ; try to read one (long double)
        cmp rax, 1                      ; if failed,
        jne .usage                      ; ...complain!

        mov rbx, qword [rbp - 8*1]      ; argv
        mov rdi, qword [rbx + 8*3]      ; argv[2] == c
                                        ;   again, index 3 means argv[3] -- correct
        mov rsi, fmt_long_double        ; format for one (long double)
        mov rdx, c                      ; &c
        mov rax, 0                      ; no fp registers used
        call sscanf                     ; try to read one (long double)
        cmp rax, 1                      ; if failed,
        jne .usage                      ; ...complain!

;;; --- compute the discriminant. The right-hand comments are the FPU stack. ---
        fninit                          ; reset the x87 subsystem: empty the eight
                                        ;   slots and clear the status word. Always
                                        ;   start from a known state.
        fld tword [b]                   ; b
        fld st0                         ; b b
                                        ;   `fld st0` DUPLICATES the top -- the RPN
                                        ;   idiom for "use this value twice"
        fmulp                           ; b^2
                                        ;   st1 * st0 -> st1, then pop: two slots
                                        ;   become one
        fldlit 4.0                      ; 4
                                        ;   our macro: jump over ten bytes of data
                                        ;   planted in .text, and load them
        fld tword [a]                   ; a
        fmulp                           ; 4a
        fld tword [c]                   ; c
        fmulp                           ; 4ac
        fsubp                           ; b^2 - 4ac
                                        ;   ORDER MATTERS: fsubp computes st1 - st0,
                                        ;   i.e. (pushed first) - (pushed second)
        fld st0                         ; (b^2 - 4ac)   (b^2 - 4ac)
                                        ;   duplicate, because the next instruction
                                        ;   consumes one copy
        fstp tword [desc]               ; desc <-- (b^2 - 4ac)
                                        ;   pop the top INTO MEMORY; one copy remains
        fldz                            ; 0
                                        ;   push the constant zero
        fucomip st1                     ; 0 ? b^2 - 4ac
                                        ;   compare st0 with st1, set the ORDINARY
                                        ;   integer flags (ZF/CF/PF) so ja/jb work,
                                        ;   and pop. This is the bridge from the FPU
                                        ;   back to the branch machinery.
        ja .no_real_roots               ; 0 > b^2 - 4ac ==> .no_real_roots

        fld tword [a]                   ; a
        fld st0                         ; a   a
        faddp                           ; 2*a
                                        ;   a + a, cheaper and exact
        fstp tword [t2]                 ; t2 <-- 2*a

        fld tword [epsilon]             ; desc    epsilon
                                        ;   (the leftover copy of desc is still st1)
        fucomip st1                     ; desc ? epsilon
        fstp st0                        ; desc < epsilon (desc is positive!)
                                        ;   `fstp st0` pops and DISCARDS -- housekeeping
                                        ;   so the FPU stack does not leak a slot
        ja .one_root                    ; | desc | < epsilon ==> .one_root

;;; --- two distinct real roots ---
        fld tword [desc]                ; desc
        fsqrt                           ; sqrt(desc)
                                        ;   in place, on the top of the stack
        fstp tword [t1]                 ; t1 <-- sqrt(desc)
        fld tword [b]                   ; b
        fchs                            ; -b
                                        ;   change sign, in place
        fld st0                         ; -b    -b
        fld tword [t1]                  ; -b    -b     t1
        faddp                           ; -b    -b + t1
        fld tword [t2]                  ; -b    -b + t1    2a
        fdivp                           ; -b    (-b + t1)/(2a)
                                        ;   st1 / st0 -- again, first-pushed is the
                                        ;   numerator
        fstp tword [x1]                 ; x1 <-- root1
        fld tword [t1]                  ; -b    t1
        fsubp                           ; -b - t1
        fld tword [t2]                  ; -b - t1    2a
        fdivp                           ; x2 == (-b - t1)/(2a)
        fld tword [x1]                  ; x2    x1
        sub rsp, 16*2                   ; make room on stack; aligned by 16
                                        ;   LONG DOUBLES ARE PASSED ON THE STACK,
                                        ;   16 bytes apiece (10 of value, 6 of pad).
                                        ;   No register can carry one.
        mov rdi, fmt_two_solutions      ; fmt for x1, x2
        fstp tword [rsp]                ; [rsp] <-- x1
                                        ;   the FIRST variadic argument, at the
                                        ;   lowest address
        fstp tword [rsp + 16*1]         ; [rsp] <-- x2
                                        ;   the second, 16 bytes higher
        mov rax, 0                      ; no fp registers in use
                                        ;   rax counts XMM registers, and these
                                        ;   values are in memory, not XMM -- so 0.
        call printf
        jmp .done                       ; cleanup and quit

;;; ----------------------------------------------------------------------------
;;; main.no_real_roots -- the discriminant is negative.
;;; ----------------------------------------------------------------------------
.no_real_roots:
        mov rdi, fmt_no_real_solution   ; fmt for x
        mov rax, 0                      ; no fp registers in use
        call printf
        jmp .done                       ; cleanup and quit

;;; ----------------------------------------------------------------------------
;;; main.one_root -- the discriminant is within epsilon of zero, so x = -b/(2a).
;;;   Recomputes 2a from scratch rather than reusing t2 -- slightly wasteful, and
;;;   a good illustration that the FPU stack cannot be relied on across a branch
;;;   unless you have tracked it carefully.
;;; ----------------------------------------------------------------------------
.one_root:
        fld tword [b]                   ; b
        fchs                            ; -b
        fld tword [a]                   ; -b    a
        fld st0                         ; -b    a    a
        faddp                           ; -b    2a
        fdivp                           ; -b/(2a)
        sub rsp, 16*1                   ; make room on stack; aligned by 16
                                        ;   one long double = one 16-byte slot
        fstp tword [rsp]                ; [rsp] <-- x
                                        ;   pop from the FPU stack into the CALL
                                        ;   stack: the two worlds meeting
        mov rdi, fmt_one_solution       ; fmt for x
        mov rax, 0                      ; no fp registers in use
        call printf

.done:
        fninit                          ; reset the x87 subsystem -- leave the FPU as
                                        ;   clean as we found it, so nothing we
                                        ;   pushed is still occupying a slot
        mov rax, 0                      ; status: OK
        mov rsp, rbp                    ; restore the stack pointer -- this discards
                                        ;   the 16 or 32 bytes of long-double
                                        ;   arguments along with the local
        pop rbp                         ; point fp to the previous frame
        ret                             ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; main.usage -- wrong argument count, or a coefficient that would not parse.
;;;   NEVER RETURNS.
;;; ----------------------------------------------------------------------------
.usage:
        mov rdi, qword [stderr]         ; errors go to FILE *stderr -- brackets,
                                        ;   because `stderr` is a VARIABLE
        mov rsi, fmt_usage              ; fmt for usage
        mov rax, 0                      ; no fp registers in use
        call fprintf
        mov rax, -1                     ; status: ERROR
        call exit                       ; terminate. Never returns.

section .note.GNU-stack noalloc noexec  ; required Linux marker: stack is not exec
