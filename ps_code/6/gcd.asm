;;; ============================================================================
;;; gcd.asm -- Euclid's algorithm, iteratively, with two registers
;;; Practice session 6                       (study annotations added)
;;; Original author's note: "Programmer: Oren"
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prompts, reads two integers, and prints their greatest common divisor.
;;;   (Verified: input `48 18` prints `The gcd(a,b) is 6`.)
;;;
;;;   THE ALGORITHM is Euclid's, and it is about 2300 years old:
;;;       gcd(a, 0) = a
;;;       gcd(a, b) = gcd(b, a mod b)
;;;   Each step replaces the pair with a smaller one, and the remainder shrinks
;;;   fast -- the number of iterations is O(log min(a,b)), so even enormous
;;;   inputs finish in a few dozen steps. Try 1000000007 and 998244353.
;;;
;;;   IT IS WRITTEN ITERATIVELY, and that is worth noticing. The recurrence
;;;   `gcd(a,b) = gcd(b, a mod b)` is a TAIL CALL -- the recursive result is
;;;   returned unchanged, with no work after it -- so it can be turned into a
;;;   loop with no stack growth at all. That is exactly what this file does:
;;;       mov rdi, rsi      ; a = b
;;;       mov rsi, rdx      ; b = a mod b
;;;       jmp .gcd_loop     ; ...instead of `call gcd`
;;;   Compare is_even.asm in ps_code/5, whose recursion is ALSO a tail call and
;;;   which does NOT do this -- and consequently overflows the stack for large n.
;;;   Same transformation, one file applies it and one does not.
;;;
;;;   THE INSTRUCTION AT THE CENTRE IS `div`:
;;;       xor rdx, rdx      ; clear the HIGH half of the dividend
;;;       div rsi           ; rax := (rdx:rax) / rsi ,  rdx := (rdx:rax) mod rsi
;;;   One operand, three hidden registers. It reads a 128-bit dividend spread
;;;   across RDX:RAX and writes the quotient to RAX and THE REMAINDER TO RDX.
;;;   Euclid needs only the remainder, so the quotient in rax is discarded --
;;;   which is fine, because you were going to compute it anyway.
;;;
;;;   *** rdx MUST BE CLEARED FIRST. *** `div` uses whatever is in rdx as the top
;;;   64 bits of the dividend. Junk there gives a wrong answer, or a #DE
;;;   exception that arrives as SIGFPE and kills the process. `xor rdx, rdx` is
;;;   the unsigned form; `cqo` is the signed form used before `idiv`.
;;;
;;;   `div` IS UNSIGNED, so this program is a gcd of NON-NEGATIVE integers.
;;;   Feed it a negative number and it will be read as a huge positive one --
;;;   try -12 and 18 and see what comes out. A signed version would use `idiv`
;;;   and `cqo`, and would need to think about the sign of the remainder.
;;;
;;;   NOTE THE SWAP IS FREE WHEN a < b. If you enter `18 48`, the first division
;;;   gives quotient 0 and remainder 18, so the pair becomes (48, 18) and the
;;;   algorithm carries on. No special case is needed -- one wasted iteration
;;;   sorts the arguments for you.
;;;
;;;   `enter 0,0` is `push rbp` + `mov rbp, rsp`; `leave` is `mov rsp, rbp` +
;;;   `pop rbp`. The familiar prologue and epilogue, one instruction each.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   echo "48 18"   | ./asm "ps_code/6/gcd.asm"        # 6
;;;   echo "1071 462"| ./asm "ps_code/6/gcd.asm"        # 21
;;;   echo "17 5"    | ./asm "ps_code/6/gcd.asm"        # 1 -- coprime
;;;   echo "12 0"    | ./asm "ps_code/6/gcd.asm"        # 12 -- the base case
;;;   echo "1000000007 998244353" | ./asm "ps_code/6/gcd.asm"
;;;   ./asm "ps_code/6/gcd.asm"                         # or type them yourself
;;;
;;;   Check a batch against the shell's own arithmetic:
;;;   for p in "48 18" "1071 462" "270 192" "17 5"; do
;;;       printf "%-10s -> " "$p"; echo "$p" | ./asm "ps_code/6/gcd.asm" | tail -1
;;;   done
;;;
;;; DEBUG IT
;;;   echo "48 18" | ./debug "ps_code/6/gcd.asm"
;;;
;;;   Useful session -- watch the pair shrink:
;;;     break gcd
;;;     c
;;;     info registers rdi rsi         48 and 18
;;;     break gcd.asm:NN               NN on the `div rsi` line
;;;     c
;;;     info registers rax rdx rsi     the dividend, the cleared high half, the divisor
;;;     si                             execute the div
;;;     p $rax                         2  -- the quotient, which we discard
;;;     p $rdx                         12 -- THE REMAINDER, which is the point
;;;     c                              round again: (18, 12), then (12, 6), then (6, 0)
;;;
;;;   Or let gdb narrate it for you:
;;;     break gcd
;;;     c
;;;     display/d $rdi
;;;     display/d $rsi
;;;     break gcd.asm:NN               NN on the `jmp .gcd_loop` line
;;;     c  c  c                        48/18, 18/12, 12/6, 6/0
;;;
;;;   Prove that clearing rdx matters:
;;;     break gcd.asm:NN               NN on the `div rsi` line
;;;     c
;;;     set $rdx = 1                   a non-zero high half makes the dividend enormous
;;;     si
;;;   The quotient no longer fits in 64 bits, so the CPU raises a divide error and
;;;   the program dies with SIGFPE. That is what `xor rdx, rdx` prevents.
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   `gcd` IS CALLED ONCE AND NEVER RECURSES, so `bt` inside it shows two frames
;;;   no matter how many iterations have run, and `p $rsp` never moves. Confirm
;;;   it:
;;;       break gcd.asm:NN     NN on the `div rsi` line
;;;       c
;;;       p $rsp               note it
;;;       bt
;;;       c   c   c
;;;       p $rsp               identical, every time
;;;       bt                   still two frames
;;;
;;;   THAT IS THE PAYOFF OF THE TAIL-CALL TRANSFORMATION, and it is worth being
;;;   able to spot the opportunity yourself. The test is simple: after the
;;;   recursive call returns, does the function do ANYTHING with the result
;;;   before returning it? If the answer is no, the call can become a jump and
;;;   the frame can be reused.
;;;       gcd(a,b) = gcd(b, a mod b)          nothing after -> loop  (this file)
;;;       is_even(n) = is_odd(n-1)            nothing after -> could be a loop,
;;;                                           but ps_code/5 does not do it, and
;;;                                           overflows the stack as a result
;;;       fact(n) = n * fact(n-1)             a MULTIPLY after -> genuinely needs
;;;                                           a frame per level (code-0010.asm)
;;;       fib(n) = fib(n-1) + fib(n-2)        two calls and an add -> needs frames,
;;;                                           and a spill besides (code-0013.asm)
;;;
;;;   Also notice that `gcd` builds NO FRAME OF ITS OWN -- no `push rbp`, no
;;;   locals. It does not need one: both its parameters arrive in registers, it
;;;   calls nothing, and it keeps its whole state in rdi, rsi, rax and rdx. The
;;;   only stack it uses is the 8-byte return address `call` pushed. That is a
;;;   LEAF FUNCTION, and it is the cheapest kind there is.
;;;
;;;   One last thing worth checking, because the source does not mention it:
;;;   `main` has no `and rsp, -16`, and it works out. `call main` left rsp at 8
;;;   mod 16, `enter 0,0` pushed rbp to make it 0, and each `call printf` pushes
;;;   8 more. Verify with `break printf` then `p $rsp % 16` -- it should be 8.
;;; ============================================================================

section .data                           ; initialised, writable data
fmt_prompt_for_input: db 'Enter two integers a, b: ', 0
                                        ; single quotes do not expand escapes in NASM,
                                        ;   so the NUL terminator is written as 0. Note
                                        ;   there is no newline -- and no fflush either,
                                        ;   so the prompt may not appear until later.
                                        ;   Compare code-0019.asm, which calls fflush.
fmt_input:            db '%ld %ld', 0   ; scanf's format: two 64-bit decimals separated
                                        ;   by whitespace
fmt_output:           db 'The gcd(a,b) is %ld', 10, 0
                                        ; ...and the newline (10) written as a number

section .bss                            ; zero-filled at load time, no file space
a:  resq 1                              ; one quadword for scanf to write into
b:  resq 1                              ; and one for the second number

extern printf, scanf                    ; supplied by the C library
global main                             ; export `main` for the C library start-up

section .text                           ; the executable-code section
; ---------------------------------------------------------
; ------------------ EUCLID GCD FUNCTION ----------------------
; ---------------------------------------------------------
;;; ----------------------------------------------------------------------------
;;; gcd -- the greatest common divisor of two non-negative integers.
;;;   C signature : long gcd(long a, long b)
;;;   Receives    : rdi = a, rsi = b   (System V AMD64 ABI)
;;;   Returns     : rax = gcd(a, b)
;;;   Clobbers    : rax, rdx, rdi, rsi -- all caller-saved, so nothing needs saving
;;;   Stack use   : just the 8-byte return address. A LEAF FUNCTION with no frame.
;;;   Signedness  : `div` is UNSIGNED, so negative inputs are read as huge
;;;                 positive ones. See the header.
;;;
;;;   The loop is the tail-recursive definition gcd(a,b) = gcd(b, a mod b),
;;;   rewritten as a jump -- which is why it uses no stack at all.
;;; ----------------------------------------------------------------------------
gcd:
        .gcd_loop:                      ; a LOCAL label: names starting with '.' belong
                                        ;   to the nearest preceding non-local label, so
                                        ;   this is really `gcd.gcd_loop`
                cmp rsi, 0              ; while (b != 0)
                je .gcd_done            ; THE BASE CASE: gcd(a, 0) = a

                mov rax, rdi            ; rax = a
                                        ;   `div` always divides RDX:RAX, so the
                                        ;   dividend has to be moved into rax
                xor rdx, rdx            ; clear high part for division
                                        ;   MANDATORY: rdx is the top 64 bits of the
                                        ;   dividend. Junk here gives a wrong answer or
                                        ;   a divide-error exception.
                div rsi                 ; rax = a / b, rdx = a % b
                                        ;   ONE INSTRUCTION, TWO ANSWERS. Unsigned
                                        ;   divide: quotient to RAX, REMAINDER TO RDX.
                                        ;   Euclid wants only the remainder.

                mov rdi, rsi            ; a = b
                mov rsi, rdx            ; b = a % b
                                        ;   the pair shrinks; the remainder is always
                                        ;   smaller than the divisor, so this terminates
                jmp .gcd_loop           ; THE TAIL CALL, AS A JUMP. `gcd(b, a mod b)`
                                        ;   with the frame reused instead of a new one
                                        ;   pushed -- which is why this uses no stack.

        .gcd_done:
                mov rax, rdi            ; gcd result in rax
                                        ;   the ABI puts return values in rax
                ret                     ; pop the return address into rip
;;; ----------------------------------------------------------------------------
;;; main -- prompt, read two integers, print their gcd.
;;;   Receives : nothing
;;;   Returns  : rax = printf's character count (never reset to 0)
;;;   How it works: three C library calls and one call to gcd. The two numbers go
;;;                 to .bss rather than the stack, so scanf can be handed their
;;;                 addresses directly.
;;; ----------------------------------------------------------------------------
main:
    enter 0,0                           ; create stack frame
                                        ;   one instruction for `push rbp` +
                                        ;   `mov rbp, rsp`. Also takes rsp from 8 mod 16
                                        ;   to 0 mod 16, which is what makes the calls
                                        ;   below legal without an `and rsp, -16`.

                                        ; ----------------------------------------------------
                                        ; Print prompt
                                        ; ----------------------------------------------------
    mov rdi, fmt_prompt_for_input       ; printf argument 1: the format string
    xor rax, rax                        ; THE VARIADIC RULE: 0 vector registers in use
    call printf

                                        ; ----------------------------------------------------
                                        ; Read a and b
                                        ; ----------------------------------------------------
    mov rdi, fmt_input                  ; scanf argument 1: the format string
    mov rsi, a                          ; argument 2: the ADDRESS of a -- scanf must
                                        ;   write into it, so it needs a pointer
    mov rdx, b                          ; argument 3: the address of b
    xor rax, rax                        ; 0 vector registers in use
    call scanf                          ; (its return value -- how many items were
                                        ;   converted -- is not checked here. Compare
                                        ;   code-0023.asm, which does check.)

                                        ; ----------------------------------------------------
                                        ; Load a and b into registers and call gcd
                                        ; ----------------------------------------------------
    mov rdi, [a]                        ; rdi = a
                                        ;   BRACKETS: load the CONTENTS, not the address
    mov rsi, [b]                        ; rsi = b
        call gcd                        ; rax = gcd(a, b)

                                        ; ----------------------------------------------------
                                        ; Print result
                                        ; ----------------------------------------------------
        mov rdi, fmt_output             ; printf argument 1
        mov rsi, rax                    ; argument 2: the answer, straight out of rax
        xor rax, rax                    ; 0 vector registers in use
        call printf


    leave                               ; epilogue: `mov rsp, rbp` + `pop rbp`
    ret                                 ; pop the return address into rip. NOTE rax is
                                        ;   not reset first, so the exit status is
                                        ;   printf's character count.
