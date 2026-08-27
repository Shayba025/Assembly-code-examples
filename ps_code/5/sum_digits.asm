;;; ============================================================================
;;; sum_digits.asm -- recursion, integer division, and a spill to the stack
;;; Practice session 5                       (study annotations added)
;;;
;;; WHAT THIS FILE IS
;;;   One function, `long sum_digits(long n)`, and NO `main`. A C driver,
;;;   `sum_digits_test.c`, sits next to it; the ./asm and ./debug scripts link
;;;   any <name>_test.c automatically.
;;;   (Verified: sum_digits(98765) = 35, and it agrees with C for every n in
;;;   0..9999.)
;;;
;;;   THE DEFINITION:
;;;       sum_digits(n) = n                              if n < 10
;;;       sum_digits(n) = sum_digits(n/10) + (n mod 10)  otherwise
;;;   Each level peels off the last digit and recurses on what remains, so the
;;;   depth is the number of digits -- 19 at most for a 64-bit value. That is a
;;;   sensible use of recursion, unlike is_even.asm in this folder.
;;;
;;;   THE INSTRUCTION AT THE CENTRE OF IT IS `div`:
;;;       xor rdx, rdx      ; clear the HIGH half of the dividend
;;;       mov rcx, 10       ; the divisor
;;;       div rcx           ; rax := (rdx:rax) / rcx  ,  rdx := (rdx:rax) mod rcx
;;;   `div` is a ONE-OPERAND instruction with THREE hidden registers. It reads a
;;;   128-bit dividend spread across RDX:RAX, and it writes the quotient to RAX
;;;   and THE REMAINDER TO RDX. So one instruction gives you both n/10 and
;;;   n mod 10 -- which is exactly what this algorithm needs, and why the
;;;   comment on the `xor rdx, rdx` line says rdx will hold the digit.
;;;
;;;   *** YOU MUST CLEAR rdx FIRST. *** `div` uses whatever is in rdx as the top
;;;   64 bits of the dividend. Leave junk there and you either get a wrong answer
;;;   or a #DE (divide error) exception, which on Linux arrives as SIGFPE and
;;;   kills the process. `xor rdx, rdx` is the unsigned form; `cqo` is the signed
;;;   form used before `idiv`. Confusing the two is a common bug -- see
;;;   code-0020.asm in "lectures code ", which uses `cqo` before an unsigned
;;;   `div` and gets away with it only because its values are positive.
;;;
;;;   THE STACK DISCIPLINE IS THE OTHER HALF OF THE FILE. Between the division
;;;   and the recursive call, TWO values must survive:
;;;       push rdi          ; the original n
;;;       push rdx          ; the last digit
;;;       ... call sum_digits ...
;;;       pop rdx           ; the digit, recovered
;;;       pop rdi           ; n, recovered
;;;   Both rdi and rdx are CALLER-SAVED, and the recursive call destroys them --
;;;   it uses rdi as its own parameter and rdx for its own division. So they are
;;;   SPILLED to the stack and recovered afterwards. Note the pops come back in
;;;   REVERSE ORDER, because the stack is last-in first-out.
;;;
;;;   IS THE `push rdi` NEEDED? The comment says it is "in order to clean stack",
;;;   and that is the honest reason: n itself is never used again after the
;;;   recursion. The push exists so that the matching pop restores rsp. You could
;;;   equally write `add rsp, 8` -- or not push it at all. Worth trying both.
;;;
;;;   COMPARE code-0013.asm in "lectures code ", whose `fib` spills its first
;;;   result across its second recursive call for exactly the same reason. Same
;;;   problem, same idiom, different algorithm.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/5/sum_digits.asm"            # checks 0..9999 against C
;;;   ./asm "ps_code/5/sum_digits.asm" 98765      # 35
;;;   ./asm "ps_code/5/sum_digits.asm" 999999999  # 81
;;;   ./asm "ps_code/5/sum_digits.asm" 7          # 7 -- the base case
;;;   ./asm "ps_code/5/sum_digits.asm" 0          # 0
;;;
;;;   Try a negative number and see what happens. `div` is UNSIGNED, so -1 is
;;;   read as 18446744073709551615 -- and `cmp rdi, 10 / jl` is a SIGNED
;;;   comparison, so the base case fires immediately and it returns the negative
;;;   number unchanged. Two different signedness assumptions in one function.
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/5/sum_digits.asm" 98765
;;;
;;;   Useful session -- watch one digit being peeled off:
;;;     break sum_digits
;;;     c
;;;     p $rdi                    98765
;;;     break sum_digits.asm:NN   NN on the `div rcx` line
;;;     c
;;;     info registers rax rdx rcx    98765, 0, 10 -- the dividend and divisor
;;;     si                        execute the div
;;;     p $rax                    9876 -- the quotient
;;;     p $rdx                    5    -- THE REMAINDER, free of charge
;;;
;;;   Watch the recursion and the spill together:
;;;     break sum_digits
;;;     c c c                     descend three levels
;;;     bt                        one frame per digit
;;;     x/2gd $rsp                the two spilled values at this level
;;;     p $rsp                    note it, then `c` again and subtract: 32 bytes
;;;                               per level (return address, rbp, and two pushes)
;;;
;;;   And watch the sum being assembled on the way OUT:
;;;     break sum_digits.asm:NN   NN on the `add rax, rdx` line
;;;     c
;;;     p $rax                    the sum of the digits ABOVE this one
;;;     p $rdx                    this level's digit
;;;     si
;;;     p $rax                    the running total
;;;     c                         and again, one level further out
;;;
;;;   Prove that clearing rdx matters:
;;;     break sum_digits.asm:NN   NN on the `div rcx` line
;;;     c
;;;     set $rdx = 1              a non-zero high half makes the dividend enormous
;;;     si
;;;   The quotient no longer fits in 64 bits, so the CPU raises a divide error
;;;   and the program dies with SIGFPE. That is what `xor rdx, rdx` prevents.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE INTERESTING THING IS WHERE THE WORK HAPPENS. In is_even.asm the answer
;;;   was decided at the bottom and simply carried up. Here it is the opposite:
;;;   every level contributes on the way OUT, at the `add rax, rdx`. The
;;;   recursion descends doing nothing but dividing, and the sum is assembled
;;;   during the unwind.
;;;
;;;   Watch that directly:
;;;       break sum_digits.asm:NN     NN on the `add rax, rdx` line
;;;       c
;;;       p $rax                      the base case's value, on the first stop
;;;       c   c   c                   and it grows at every level as you continue
;;;   THIS IS WHY THE FRAMES HAVE TO EXIST. Each level's digit must be remembered
;;;   while the levels below it run, and there is exactly one rdx. The stack is
;;;   the only place with room for all of them at once -- and it holds them in
;;;   precisely the right order, because the last digit pushed is the first one
;;;   popped.
;;;
;;;   Contrast the iterative version, which the C driver contains:
;;;       while (n > 0) { s += n % 10; n /= 10; }
;;;   Same answer, one frame, no pushes. The recursion buys nothing here except
;;;   clarity -- and this is exactly the trade you met in code-0009.asm versus
;;;   code-0010.asm, and code-0012.asm versus code-0013.asm. By now you should be
;;;   able to predict the shape of the backtrace before you type `bt`.
;;;
;;;   One last measurement worth taking, since it makes the depth concrete:
;;;       ./debug "ps_code/5/sum_digits.asm" 1234567890123456789
;;;       break sum_digits
;;;       ignore 1 100
;;;       c
;;;       info breakpoints           the hit count is the number of digits
;;;   Nineteen frames for a nineteen-digit number, and no more however large the
;;;   value -- because the depth is logarithmic in n, not linear. That is the
;;;   difference between this file and is_even.asm, and it is the whole reason
;;;   one of them can be used in practice and the other cannot.
;;; ============================================================================

section .text                           ; the executable-code section
global sum_digits                       ; export it for the C driver. NOTE: no
                                        ;   `global main` -- this file has no main().

;long sum_digits (long n)
; argument : rdi
; return : rax = sum of digits

;;; ----------------------------------------------------------------------------
;;; sum_digits -- the sum of the decimal digits of n.
;;;   C signature : long sum_digits(long n)
;;;   Receives    : rdi = n   (System V: the first argument is in rdi)
;;;   Returns     : rax = the digit sum
;;;   Clobbers    : rax, rcx, rdx, rdi
;;;   Frame       : 32 bytes per level -- return address, saved rbp, and the two
;;;                 spilled values (n and the current digit)
;;;   Depth       : the number of digits, so at most 19 for a 64-bit value
;;;   Signedness  : `cmp rdi, 10 / jl` is SIGNED, but `div` is UNSIGNED. Fine for
;;;                 non-negative n; see the header for what happens otherwise.
;;; ----------------------------------------------------------------------------
sum_digits:
   push rbp                             ; prologue: save the caller's frame pointer
   mov rbp, rsp                         ; anchor this activation

                                        ;base case : n< 10 so return n
  cmp rdi, 10                           ; subtract 10 from n, keeping only the flags
  jl .base_case                         ; `jl` = jump if less, SIGNED. A single-digit
                                        ;   number IS its own digit sum.

                                        ;recursive case : sum_digits(n/10) + n%10

                                        ;save n
  push rdi                              ; SPILL n. rdi is caller-saved and the recursive
                                        ;   call will use it as its own parameter.
                                        ;   (Strictly, n is not needed again -- this
                                        ;   push exists mainly so the matching pop
                                        ;   restores rsp. See the header.)

                                        ;compute n/10
  mov rax, rdi                          ; `div` always divides RDX:RAX, so the dividend
                                        ;   must be moved into rax
  xor rdx, rdx                          ; clean rdx since later rdx stores the digit
                                        ;   MANDATORY: rdx is the HIGH 64 bits of the
                                        ;   dividend. Junk here gives a wrong answer or
                                        ;   a divide-error exception. (`xor r, r` is
                                        ;   the idiomatic zeroing; `cqo` is the SIGNED
                                        ;   equivalent, for `idiv`.)
  mov rcx, 10                           ; the divisor. `div` takes no immediate operand,
                                        ;   so the 10 has to go in a register.
  div rcx                               ; rax = n/10  rdx = n%10
                                        ;   ONE INSTRUCTION, TWO ANSWERS: unsigned
                                        ;   divide, quotient to RAX and REMAINDER TO
                                        ;   RDX. Exactly what this algorithm needs.

  push rdx                              ; [rsp]=last digit
                                        ;   SPILL the digit. rdx is caller-saved, and
                                        ;   the recursive call is about to do its own
                                        ;   division and destroy it.

  mov rdi, rax                          ; the argument for the next level: n/10
   call sum_digits                      ; rax = sum_digits(n/10)
                                        ;restore n
  pop rdx                               ; rdx=last digit
                                        ;   recovered from the stack, untouched by the
                                        ;   recursion
  pop rdi                               ; restore original n  in order to clean stack
                                        ;   NOTE THE ORDER: the pops mirror the pushes
                                        ;   in reverse, because the stack is last-in
                                        ;   first-out.

                                        ;add last_digit n%10
add rax, rdx                            ; THE WORK HAPPENS HERE, ON THE WAY OUT: this
                                        ;   level's digit is added to the sum of all
                                        ;   the digits above it.

  jmp .done                             ; skip the base-case assignment
.base_case:
    mov rax, rdi                        ; return n
                                        ;   a single-digit number is its own digit sum
.done:
   leave                                ; epilogue: `mov rsp, rbp` + `pop rbp`
    ret                                 ; pop the return address into rip
