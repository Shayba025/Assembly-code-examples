;;; ============================================================================
;;; exp_x87.asm -- computing e two ways on the x87 FPU, and printing it by hand
;;; Practice session 8                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Computes e = 2.718281828... twice, by two completely different methods, and
;;;   prints the first to ten decimal places.
;;;   (Verified: prints `Method 1 (2^(log2e)): 2.7182818285`.)
;;;
;;;   The Taylor result is computed too, but the six lines that would print it
;;;   are commented out in `_start`. Uncomment them and you can compare the two
;;;   -- which is the obvious first exercise.
;;;
;;;   IT DEFINES `_start`, NOT `main`, so there is no C library anywhere: no
;;;   printf, no malloc, nothing. Every character it prints is produced by code
;;;   in this file and pushed out with the `write` system call. The ./asm and
;;;   ./debug scripts spot the `global _start` and link with plain `ld`.
;;;
;;;   ------------------------------------------------------------------
;;;   PART 1: THE x87 FPU IS A STACK MACHINE
;;;   ------------------------------------------------------------------
;;;   Read code-0023.asm in "lectures code " first if you have not. The essential
;;;   facts: there are eight 80-bit slots arranged as a stack, st0 is the top,
;;;   and every instruction operates on it implicitly.
;;;       fld <mem>     PUSH a value        (everything shifts down one slot)
;;;       fld1 / fldz   push the constant 1 / 0
;;;       fldl2e        push log2(e)  -- one of several built-in constants
;;;       fild <mem>    push an INTEGER, converted to floating point
;;;       fstp <mem>    POP the top into memory
;;;       fstp st0      pop and discard
;;;       fxch          swap st0 and st1
;;;       f...p         the `p` suffix means "and pop", so the stack shrinks
;;;
;;;   THE COMMENTS SHOWING THE STACK CONTENTS ARE NOT DECORATION. Reading the
;;;   right-hand column downwards is the only sane way to follow x87 code. Where
;;;   the original file's comments are ambiguous, the annotations below spell out
;;;   the whole stack after each instruction.
;;;
;;;   METHOD 1 -- e^x = 2^(x * log2 e), which is just a change of base. The x87
;;;   has no "raise to a power" instruction, but it has two that combine into
;;;   one:
;;;       f2xm1     computes 2^st0 - 1, and ONLY for -1 <= st0 <= 1
;;;       fscale    multiplies st0 by 2^(integer part of st1)
;;;   So the trick is to split y = x*log2(e) into an integer part n and a
;;;   fraction frac, use f2xm1 on the fraction (which is in range by
;;;   construction) and fscale for the integer part:
;;;       2^y = 2^(n + frac) = 2^frac * 2^n
;;;   The `-1` in f2xm1 exists for accuracy near zero, and is undone with
;;;   `fld1 / faddp`. This is exactly how a real `exp()` is implemented.
;;;
;;;   METHOD 2 -- the Taylor series e = sum(1/k!) for k = 0..20. Note it never
;;;   computes a factorial: each term is the previous one divided by k, so
;;;   1, 1/1, 1/2, 1/6, 1/24, ... appear by repeated division. Computing 20! and
;;;   dividing would overflow and lose precision; this does neither.
;;;
;;;   ------------------------------------------------------------------
;;;   PART 2: PRINTING A FLOAT WITHOUT printf
;;;   ------------------------------------------------------------------
;;;   `print_float_10dec` is the clever part of the file, and the technique is
;;;   worth stealing:
;;;       multiply by 10^10   ->   2.718281828...  becomes  27182818284.59...
;;;       fistp to an integer ->   27182818285      (rounded)
;;;       divide by 10^10     ->   quotient 2, remainder 7182818285
;;;       print "2", then ".", then the remainder padded to exactly 10 digits
;;;   Turning a fixed number of decimal places into an integer problem, and then
;;;   using `div` (which hands you the quotient AND the remainder in one
;;;   instruction) to split it, is how you print floating point when you have no
;;;   library. The last step needs LEADING ZEROS -- 0.5 would give a remainder of
;;;   5000000000, but 0.0000000005 gives 5, and printing "0.5" for both would be
;;;   wrong. That is why `print_10digits` exists separately from `print_int`.
;;;
;;;   ACCURACY: the printed value 2.7182818285 is the correctly ROUNDED
;;;   ten-decimal form of e = 2.71828182845904523... -- `fistp` rounds to
;;;   nearest, so the last digit is 5 rather than 4. Good.
;;;
;;;   ------------------------------------------------------------------
;;;   THINGS TO SPOT
;;;   ------------------------------------------------------------------
;;;   * `x_val` is 1.0, so this computes e^1. Change it to 2.0 or 0.5 and the
;;;     same code gives e^2 or sqrt(e). Try it -- and then try a NEGATIVE x and
;;;     see what `print_float_10dec` does with it (nothing good: it has no
;;;     concept of a sign).
;;;   * rbx and rcx are used freely and are pushed/popped inside the print
;;;     helpers -- but `compute_method2` clobbers rbx and rcx without saving.
;;;     There is no C library caller to complain, so it does not matter here.
;;;   * `print_int` and `print_10digits` share the same `buf`. Safe only because
;;;     each finishes writing before the next begins.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/8/exp_x87.asm"
;;;
;;;   Compare against the truth:
;;;   python3 -c "import math; print('%.10f' % math.e)"
;;;
;;;   Then uncomment the six `;mov rdi, msg2` lines in `_start`, rebuild, and see
;;;   whether the Taylor series agrees to all ten places:
;;;   ./asm "ps_code/8/exp_x87.asm"
;;;
;;;   And change `x_val: dq 1.0` to compute something else:
;;;   python3 -c "import math; print('%.10f' % math.exp(2))"
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/8/exp_x87.asm"
;;;
;;;   gdb stops at `main` by default and there is no `main`, so:
;;;     break _start
;;;     c
;;;
;;;   THE command for this file is `info float`, which prints the whole x87 stack:
;;;     break compute_method1
;;;     c
;;;     si                        finit
;;;     info float                an empty stack
;;;     si                        fld qword [x_val]
;;;     info float                one value: 1.0
;;;     si                        fldl2e
;;;     info float                TWO values -- log2(e) on top of x
;;;     si                        fmulp
;;;     info float                one value again: y = 1.4426950...
;;;
;;;   Or watch just the top three slots as you step:
;;;     display $st0
;;;     display $st1
;;;     display $st2
;;;     si  si  si ...
;;;   Compare what you see against the annotations on each line. When they
;;;   disagree, one of you is wrong -- and finding out which is the exercise.
;;;
;;;   Check the split into integer and fraction:
;;;     break exp_x87.asm:NN      NN on the `f2xm1` line
;;;     c
;;;     p $st0                    the fraction, about 0.4427 -- and note it is
;;;                               within f2xm1's required range of [-1, 1]
;;;     p $st1                    the integer part, 1
;;;
;;;   Watch the float being turned into an integer for printing:
;;;     break exp_x87.asm:NN      NN on the `fistp qword [tmp]` line
;;;     c
;;;     p $st0                    27182818284.59...
;;;     si
;;;     p (long)tmp               27182818285 -- rounded to nearest
;;;     # ...then the div splits it:
;;;     break exp_x87.asm:NN      NN on the `div rbx` line
;;;     c
;;;     si
;;;     p $rax                    2          -- the integer part
;;;     p $rdx                    7182818285 -- the ten fractional digits
;;;
;;;   And confirm the Taylor version, which the program computes but does not
;;;   print:
;;;     break exp_x87.asm:NN      NN on the `ret` at the end of compute_method2
;;;     c
;;;     p *(double*)&res2         2.718281828459045...
;;;     p *(double*)&res1         and method 1's answer, for comparison
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THERE ARE TWO STACKS IN THIS PROGRAM AND THEY HAVE NOTHING TO DO WITH EACH
;;;   OTHER. The x87 register stack is eight slots deep, lives inside the CPU,
;;;   and is addressed only relatively (st0, st1, ...). The call stack is as deep
;;;   as your address space, lives in RAM, and holds return addresses and saved
;;;   registers. In gdb:
;;;       info float        the FPU stack
;;;       x/8gx $rsp        the call stack
;;;       bt                the call stack, interpreted as frames
;;;   Two entirely separate pictures, updated by different instructions.
;;;
;;;   THE EIGHT-SLOT LIMIT IS REAL AND UNFORGIVING. Push a ninth value and you do
;;;   not get more memory -- you get an invalid-operation exception and a NaN,
;;;   silently, and every subsequent result is rubbish. That is why this file is
;;;   so careful to balance its pushes and pops: `compute_method1` ends with
;;;   `fstp qword [res1]` AND a bare `fstp` purely to discard the leftover n, and
;;;   `compute_method2` ends with `fstp st0` for the same reason. Watch it:
;;;       break exp_x87.asm:NN     NN on the `ret` at the end of compute_method1
;;;       c
;;;       info float               the stack should be EMPTY again
;;;   Leaking FPU slots is the x87 equivalent of leaking memory, and it takes
;;;   only eight leaks to break the program.
;;;
;;;   ON THE CALL STACK, meanwhile, the discipline is the one you already know.
;;;   `print_str`, `print_int`, `print_dot` and `print_10digits` all begin with a
;;;   row of pushes and end with the matching pops in REVERSE order -- a function
;;;   being polite about the registers it clobbers, in a program where there is
;;;   no ABI to appeal to. Measure the nesting:
;;;       break print_int
;;;       c
;;;       bt                       print_int, print_float_10dec, _start
;;;       p $rsp
;;;   Three levels deep and perfectly flat -- no recursion anywhere in this file.
;;;
;;;   ONE LAST THING WORTH SEEING, because it is the only place the two stacks
;;;   meet: `fistp qword [tmp]` pops a value off the FPU stack and writes it into
;;;   ordinary memory, where `mov rax, [tmp]` picks it up as an integer. Step
;;;   those two instructions with `info float` and `x/1gd &tmp` after each, and
;;;   you are watching a value cross from the floating-point world into the
;;;   integer one. Everything after that point is plain integer arithmetic.
;;; ============================================================================

global _start
                                        ;   THE PROGRAM'S ENTRY POINT -- not `main`. No C library
                                        ;   at all, which is why every print routine below has to
                                        ;   be written by hand.

section .data
                                        ;   initialised, writable data
msg1:   db "Method 1 (2^(log2e)): ", 0
                                        ;   a C string: the trailing 0 is what print_str scans for
msg2:   db "Method 2 (Taylor):     ", 0
                                        ;   ...and the label for the Taylor result, which _start
                                        ;   currently does not print
nl:     db 10, 0
                                        ;   just a newline (byte 10)
dot:    db ".", 0
                                        ;   a one-character string, for the decimal point

x_val:  dq 1.0
                                        ;   THE EXPONENT. `dq 1.0` emits an 8-byte IEEE-754 double,
                                        ;   so this computes e^1 = e. Change it to 2.0 for e^2.
scale:  dq 10000000000.0                ; 10^10
                                        ;   10^10 as a double -- the scale factor that turns ten
                                        ;   decimal places into an integer problem. See the header.

section .bss
                                        ;   zero-filled at load time, no file space
res1:   resq 1
                                        ;   method 1's answer, as a double
res2:   resq 1
                                        ;   method 2's answer -- computed, but never printed
tmp:    resq 1
                                        ;   scratch, used to hand values between the FPU and the
                                        ;   integer registers
buf:    resb 64
                                        ;   the digit buffer, filled BACKWARDS from buf+63

section .text
                                        ;   the executable-code section

_start:
    call compute_method1
                                        ;   compute e by the change-of-base identity...
    call compute_method2
                                        ;   ...and again by the Taylor series. Both results are
                                        ;   stored; only the first is printed.

    mov rdi, msg1
                                        ;   print the label for method 1
    call print_str
    mov rdi, res1
                                        ;   print_float_10dec takes a POINTER to the double
    call print_float_10dec
    mov rdi, nl
    call print_str

                                        ;mov rdi, msg2
                                        ;   these six lines would print the Taylor result. Uncomment
                                        ;   them and rebuild to compare the two methods -- the
                                        ;   obvious first exercise with this file.
                                        ;call print_str
                                        ;mov rdi, res2
                                        ;call print_float_10dec
                                        ;mov rdi, nl
                                        ;call print_str

    mov rax, 60
                                        ;   sys_exit
    xor rdi, rdi
                                        ;   status 0 = success
    syscall
                                        ;   THE PROGRAM ENDS HERE. No `ret` -- the kernel started us
                                        ;   directly, so there is nobody to return to.

; -------------------------------------------------------
; compute_method1: e^x = 2^(x * log2(e))
;
;   y    = x * log2(e)
;   n    = round(y)          (integer exponent for fscale)
;   frac = y - n             (fraction for f2xm1)
;   e    = (2^frac - 1 + 1) * 2^n = (f2xm1+1) * 2^n
; -------------------------------------------------------
compute_method1:
    finit
                                        ;   FPU INIT: empty all eight slots and clear the status
                                        ;   word. Always start from a known state.
        fld qword [x_val]               ; st0 = x
                                        ;   push x.  stack:  x
    fldl2e                              ; st1 = log2(e)
                                        ;   push the built-in constant log2(e) = 1.4426950...
                                        ;   stack:  x   log2e     (log2e is on TOP)
    fmulp st1, st0                      ; st0 = y = 1.0 * log2(e)
                                        ;   st1 := st1 * st0, then POP.  stack:  y = x*log2e
                                        ;   The `p` suffix on any x87 arithmetic means "and pop".

    fld st0                             ; st0 = y, st1 = y
                                        ;   `fld st0` DUPLICATES the top -- the RPN way to say
                                        ;   "use this value twice".  stack:  y   y
    frndint                             ; st0 = n
                                        ;   round st0 to an integer, in place, using the current
                                        ;   rounding mode.  stack:  y   n
        fsub st1, st0                   ; st1 = frac = y - n,
                                        ;   st1 := st1 - st0 = y - n = the fraction. No pop.
                                        ;   stack:  frac   n     (n still on top)
    fxch                                ; st0 = frac,  st1 = n
                                        ;   swap st0 and st1.  stack:  n   frac     (frac on top),
                                        ;   which is what f2xm1 needs

    f2xm1                               ; st0 = 2^frac - 1
                                        ;   2^st0 - 1, in place. ONLY VALID FOR -1 <= st0 <= 1 --
                                        ;   which is guaranteed, because frac is a fraction.
                                        ;   stack:  n   2^frac - 1
    fld1
                                        ;   push the constant 1.0.  stack:  n   2^frac-1   1
    faddp st1, st0                      ; st0 = 2^frac
                                        ;   st1 := st1 + st0, then pop -- undoing f2xm1's `-1`.
                                        ;   stack:  n   2^frac
    fscale                              ; st0 = 2^frac * 2^n = e
                                        ;   st0 := st0 * 2^(integer part of st1), i.e. multiply by
                                        ;   2^n. Now st0 = 2^frac * 2^n = 2^y = e^x.
                                        ;   stack:  n   e
    fstp qword [res1]
                                        ;   pop the answer into memory.  stack:  n
        fstp                            ; pop n
                                        ;   pop n and discard it. HOUSEKEEPING, and not optional --
                                        ;   the FPU stack has only eight slots, and leaking one per
                                        ;   call would break the program on the eighth. Check with
                                        ;   `info float` after this line: the stack must be empty.

    ret
                                        ;   back to _start

; -------------------------------------------------------
; compute_method2: Taylor series  e = sum(1/k!, k=0..20)
; -------------------------------------------------------
compute_method2:
    finit
                                        ;   FPU INIT: empty the stack, clear the status word
    fld1                                ; st0 = sum = 1   (k=0 term)
                                        ;   push 1.0 as the running SUM -- the k = 0 term of the
                                        ;   series.  stack:  sum
    fld1                                ; st0 = term = 1
                                        ;   push 1.0 again as the current TERM.
                                        ;   stack:  sum   term

    mov rcx, 20
                                        ;   twenty terms. rcx is not a free choice: `loop` uses it.
    mov rbx, 1
                                        ;   k, the divisor for the first iteration
.taylor_loop:
                                        ;   one pass = one more term of the series
    mov [tmp], rbx
                                        ;   park k in memory, because `fild` loads from memory and
                                        ;   not from a register
    fild qword [tmp]                    ; st0 = k, st1 = term, st2 = sum
                                        ;   push k, CONVERTED from integer to floating point.
                                        ;   stack:  sum   term   k
    fdivp st1, st0                      ; st0 = term/k
                                        ;   st1 := st1 / st0 = term/k, then pop. THE NEW TERM: each
                                        ;   one is the previous divided by k, so no factorial is
                                        ;   ever computed and nothing overflows.
                                        ;   stack:  sum   term/k
    fadd st1, st0                       ; st1 = sum + term/k
                                        ;   st1 := st1 + st0 = sum + term. NO POP -- the new term
                                        ;   stays on top, ready for the next iteration.
                                        ;   stack:  sum'   term
    inc rbx
                                        ;   k for the next pass
    loop .taylor_loop
                                        ;   decrement rcx and repeat while non-zero

    fstp st0                            ; pop last term
                                        ;   pop the final term and discard it. Balancing the stack
                                        ;   again -- see the note in method 1.  stack:  sum
    fstp qword [res2]
                                        ;   pop the sum into memory.  stack: empty
    ret
                                        ;   back to _start

; -------------------------------------------------------
; print_float_10dec(rdi = pointer to qword float)
;   prints INTPART.FRACDIGITS  (10 decimal digits)
; -------------------------------------------------------
print_float_10dec:
                                        ;   THE VALUE ARRIVES AS A POINTER, not in a register:
                                        ;   doubles are not passed in general registers, and this
                                        ;   program has no ABI obligations anyway.
    fld qword [rdi]                     ; st0 = value
                                        ;   push the value.  stack:  v
    fld qword [scale]                   ; st0 = 1e10, st1 = value
                                        ;   push 10^10.  stack:  v   1e10
    fmulp st1, st0                      ; st0 = value * 1e10
                                        ;   st1 := st1 * st0, then pop.  stack:  v * 1e10
                                        ;   For e that is 27182818284.59...
    fistp qword [tmp]
                                        ;   convert to an INTEGER, round to nearest, pop into
                                        ;   memory. The float has now become an integer problem --
                                        ;   this is where the two worlds meet.

    mov rax, [tmp]
                                        ;   pick it up in an integer register
    mov rbx, 10000000000
                                        ;   10^10 again, this time as an integer divisor
    xor rdx, rdx
                                        ;   MANDATORY before `div`: rdx is the HIGH half of the
                                        ;   dividend
    div rbx                             ; rax = int part, rdx = frac digits
                                        ;   ONE INSTRUCTION, TWO ANSWERS: the quotient is the whole
                                        ;   part and the remainder is exactly the ten decimal
                                        ;   digits. That is the whole trick.

    mov rdi, rax
                                        ;   print the integer part...
    call print_int
    call print_dot
                                        ;   ...then the decimal point...
    mov rdi, rdx
                                        ;   ...then the fraction, PADDED TO TEN DIGITS. It must be
                                        ;   padded: 0.0000000005 has remainder 5, and printing "5"
                                        ;   would mean 0.5.
    call print_10digits
    ret
                                        ;   back to _start

; -------------------------------------------------------
print_str:
                                        ;   write a NUL-terminated string: strlen and write, by hand
    push rax
                                        ;   save what we are about to clobber -- this program has no
                                        ;   ABI to consult, so the house rule is "save everything"
    push rdi
    mov rax, 0
                                        ;   the running length
.ps_len:
    cmp byte [rdi+rax], 0
                                        ;   is this byte the terminator? `byte` is required -- the
                                        ;   brackets alone give no width
    je .ps_done
    inc rax
    jmp .ps_len
.ps_done:
    mov rdx, rax
                                        ;   write's argument 3: the byte COUNT
    pop rdi
                                        ;   recover the pointer
    mov rax, 1
                                        ;   sys_write
    mov rsi, rdi
                                        ;   argument 2: the bytes -- set BEFORE rdi is overwritten
    mov rdi, 1
                                        ;   argument 1: file descriptor 1 = stdout
    syscall
                                        ;   trap into the kernel; destroys rcx and r11
    pop rax
    ret

; -------------------------------------------------------
print_int:
                                        ;   integer to decimal, by hand
    push rax
    push rbx
    push rcx
    push rdx
    mov rax, rdi
                                        ;   `div` always divides RDX:RAX
    mov rbx, 10
                                        ;   the divisor -- `div` takes no immediate operand
    lea rdi, [buf+63]
                                        ;   start at the FAR END of the buffer and work backwards:
                                        ;   the digits come out least-significant first
    mov byte [rdi], 0
                                        ;   plant the NUL terminator
    cmp rax, 0
                                        ;   the special case: zero would produce no digits at all
    jne .pi_loop
    dec rdi
                                        ;   ...so write one by hand
    mov byte [rdi], '0'
    jmp .pi_done
.pi_loop:
    xor rdx, rdx
                                        ;   MANDATORY before `div`
    div rbx
                                        ;   rax := value/10 , rdx := value mod 10
    add dl, '0'
                                        ;   digit VALUE (0-9) -> CHARACTER ('0'-'9'), by adding 48
    dec rdi
                                        ;   one character to the LEFT...
    mov [rdi], dl
                                        ;   ...and store it
    cmp rax, 0
    jne .pi_loop
.pi_done:
    mov rsi, rdi
                                        ;   write's argument 2: the first digit
    mov rdx, buf+63
                                        ;   the end of the buffer...
    sub rdx, rdi
                                        ;   ...minus the start = THE LENGTH.
                                        ;   (powersys.asm in this folder has a stray `mov rdx, rdi`
                                        ;   here, which destroys this and breaks the program.)
    mov rax, 1
    mov rdi, 1
    syscall
    pop rdx
                                        ;   restore, in REVERSE order to the pushes
    pop rcx
    pop rbx
    pop rax
    ret

; -------------------------------------------------------
print_dot:
                                        ;   print a single '.' -- one write of one byte
    push rax
    push rdi
    push rsi
    push rdx
    mov rax, 1
    mov rdi, 1
    mov rsi, dot
    mov rdx, 1
    syscall
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; -------------------------------------------------------
; print_10digits: always prints exactly 10 digits (with leading zeros)
                                        ;   print exactly ten digits, WITH leading zeros. Separate
                                        ;   from print_int precisely because of those zeros.
; -------------------------------------------------------
print_10digits:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    mov rcx, 10
                                        ;   exactly ten digits, always
    mov rax, rdi
    lea rbx, [buf+63]
                                        ;   start at the far end and work backwards
    mov byte [rbx], 0

.p10_loop:
                                        ;   no early exit: the loop runs ten times whatever the
                                        ;   value, which is what produces the leading zeros
    xor rdx, rdx
                                        ;   MANDATORY before `div`
    mov rsi, 10
    div rsi
                                        ;   rax := value/10 , rdx := value mod 10
    add dl, '0'
                                        ;   digit value -> character
    dec rbx
    mov [rbx], dl
    loop .p10_loop
                                        ;   decrement rcx and repeat -- exactly ten passes

    mov rax, 1
                                        ;   sys_write
    mov rdi, 1
    mov rsi, rbx
    mov rdx, 10
                                        ;   exactly ten bytes, no terminator needed
    syscall

    pop rsi
                                        ;   restore, in reverse order
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret
