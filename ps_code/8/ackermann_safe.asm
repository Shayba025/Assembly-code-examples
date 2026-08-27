;;; ============================================================================
;;; ackermann_safe.asm -- A(2, n) by recursion, with hand-written I/O
;;; Practice session 8                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints "Ackermann A(2,4) = 11".
;;;   (Verified: it really does print 11.)
;;;
;;;   WHY "SAFE". The Ackermann function is the standard example of a
;;;   computable function that is not primitive recursive, and it grows
;;;   ferociously:
;;;       A(0, n) = n + 1
;;;       A(m, 0) = A(m-1, 1)
;;;       A(m, n) = A(m-1, A(m, n-1))
;;;   The general form recurses on BOTH arguments and its stack depth explodes --
;;;   A(4, 2) has 19729 decimal digits and no computer will ever evaluate it.
;;;   This file cheats safely by hard-coding the closed form of the m = 2 row:
;;;       A(2, 0) = 3
;;;       A(2, n) = A(2, n-1) + 2      so   A(2, n) = 2n + 3
;;;   That recursion is linear in n, one frame per level, and perfectly tame.
;;;   Check the answer: 2*4 + 3 = 11.
;;;
;;;   TRY THE REAL THING as an exercise. Implement the full two-argument version
;;;   and run A(2,3), then A(3,3) = 61, then A(3,5) = 253 -- and watch the
;;;   backtrace depth in gdb grow past anything you have seen so far. A(3,10) may
;;;   well exhaust your stack. That is the point of the function.
;;;
;;;   THE REST OF THE FILE IS A MINIATURE C LIBRARY, written from nothing:
;;;
;;;   1. `print_str` -- strlen and write by hand: walk the bytes counting until a
;;;      0 turns up, then one `write` with that count.
;;;
;;;   2. `print_int` -- integer to decimal by hand. Repeatedly divide by 10; each
;;;      remainder is the next digit, produced LEAST significant first. Since you
;;;      need them the other way round, the digits are written BACKWARDS into a
;;;      buffer from the far end:
;;;          lea rdi, [buf+31]     ; start at the end
;;;          mov byte [rdi], 0     ; the terminator
;;;          ... dec rdi ; mov [rdi], dl ...
;;;      When the loop finishes, rdi points at the first digit and
;;;      `buf+31 - rdi` is the length. Every itoa ever written works this way.
;;;
;;;   *** COMPARE print_int WITH THE ONE IN powersys.asm IN THIS SAME FOLDER. ***
;;;   They are the same function, except that powersys.asm has one extra line --
;;;   `mov rdx, rdi` -- which destroys the computed length and makes it print
;;;   nothing at all. Diff them:
;;;       diff <(sed -n '/^print_int/,/^ *ret/p' originals/ps_code/8/ackermann_safe.asm) \
;;;            <(sed -n '/^print_int/,/^ *ret/p' originals/ps_code/8/powersys.asm)
;;;   THIS file's version is the correct one. Reading the pair is the cheapest
;;;   possible lesson in why "it compiles" means nothing.
;;;
;;;   IT DEFINES `_start`, NOT `main`, so there is no C library at all -- which
;;;   is exactly why print_str and print_int have to exist. The ./asm and ./debug
;;;   scripts spot the `global _start` and link with plain `ld`. It also means
;;;   the program must end with the exit system call rather than a `ret`.
;;;
;;;   AN ODDITY WORTH NOTICING: `ack2` does `push rdi` before the recursive call
;;;   and `add rsp, 8` after it, in the C calling-convention style of
;;;   code-0010.asm -- but the callee reads its argument from rdi, not from the
;;;   stack, so the pushed value is never read. Two wasted instructions per
;;;   level. Delete both and nothing changes.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/8/ackermann_safe.asm" ; echo "exit status = $?"
;;;
;;;   Change `mov rdi, 4` in `_start` to try other values, and check them against
;;;   the closed form 2n+3:
;;;       n = 0 -> 3     n = 1 -> 5     n = 4 -> 11     n = 10 -> 23
;;;
;;;   And see how small a program with no C library is:
;;;   ls -l ps_code/8/ackermann_safe
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/8/ackermann_safe.asm"
;;;
;;;   gdb stops at `main` by default and there is no `main`, so:
;;;     break _start
;;;     c
;;;
;;;   Useful session -- watch the recursion descend and the additions happen on
;;;   the way back out:
;;;     break ack2
;;;     c  c  c                   descend three levels
;;;     bt                        one frame per level
;;;     p $rdi                    n at this level, one smaller each time
;;;     c  c                      down to the base case
;;;     p $rax                    3
;;;     finish                    unwind one level
;;;     p $rax                    5, then 7, then 9, then 11
;;;
;;;   Watch the digits being produced in reverse:
;;;     break ackermann_safe.asm:NN     NN on the `div rbx` line in print_int
;;;     c
;;;     p $rax                    11
;;;     si
;;;     p $rax                    1  -- the quotient
;;;     p $rdx                    1  -- the remainder, i.e. the LAST digit first
;;;     x/s &buf                  and after the second pass, "11"
;;;
;;;   And confirm the length is computed correctly here (unlike powersys.asm):
;;;     break ackermann_safe.asm:NN     NN on the `mov rax, 1` after `.ps_done`-style
;;;                                     length computation in print_int
;;;     p (char*)&buf+31 - $rdi   the number of digits
;;;     p $rdx                    the same number -- as it should be
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THIS FILE SHOWS TWO DIFFERENT REASONS TO PUSH THINGS, and telling them
;;;   apart is the skill worth taking away.
;;;
;;;   1. SAVING REGISTERS. `print_str` and `print_int` both begin with a row of
;;;      pushes and end with the matching pops in REVERSE order. That is a
;;;      function being polite about the registers it is going to clobber. In a
;;;      freestanding program there is no ABI to consult, so "save everything" is
;;;      a reasonable house rule. The reversal is not stylistic: the stack is
;;;      last-in first-out, so the pops must mirror the pushes exactly.
;;;
;;;   2. REMEMBERING WHERE TO COME BACK TO. Every `call` pushes 8 bytes whether
;;;      you like it or not, and `ack2` adds a frame pointer on top. Measure it:
;;;          break ack2
;;;          c
;;;          p $rsp                 note it
;;;          c
;;;          p $rsp                 24 bytes lower per level -- 8 return address,
;;;                                 8 saved rbp, 8 for the push that is never read
;;;
;;;   THE THIRD KIND OF PUSH IS THE ONE THAT IS NOT HERE, and its absence is the
;;;   interesting part. `ack2` does the addition AFTER the recursive call:
;;;       call ack2 ; add rsp, 8 ; add rax, 2
;;;   but it needs nothing except rax to do so. There is no value to SPILL. Put
;;;   that beside code-0013.asm, whose `fib` must `push rax` between its two
;;;   recursive calls because the second one would destroy the first's result,
;;;   and beside sum_digits.asm in ps_code/5, which spills the current digit.
;;;   The rule is always the same: A VALUE THAT MUST OUTLIVE A CALL CANNOT LIVE
;;;   IN A CALLER-SAVED REGISTER -- and here there simply is no such value.
;;;
;;;   Finally, notice that the recursion in `ack2` is ALMOST a tail call. If the
;;;   `add rax, 2` came before the call instead of after it, the frame could be
;;;   reused and the whole thing would collapse into a loop with no stack growth,
;;;   exactly as gcd.asm in ps_code/6 does. Try rewriting it that way: pass the
;;;   running total as a second argument in rsi, and finish with `jmp ack2`.
;;; ============================================================================

; ackermann_safe.asm — safe Ackermann A(2, n) using syscalls only

global _start                           ; THE PROGRAM'S ENTRY POINT -- not `main`. There
                                        ;   is no C library, which is why print_str and
                                        ;   print_int have to be written by hand.

section .data                           ; initialised, writable data
msg: db "Ackermann A(2,4) = ", 0        ; a C string: the trailing 0 is what print_str
                                        ;   scans for
nl:  db 10, 0                           ; just a newline (byte 10)

section .bss                            ; zero-filled at load time, no file space
buf: resb 32                            ; the digit buffer, filled BACKWARDS from buf+31

section .text                           ; the executable-code section

; -------------------------
; print_str(rdi = address)
; -------------------------
;;; ----------------------------------------------------------------------------
;;; print_str -- write a NUL-terminated string to stdout. strlen + write by hand.
;;;   Receives : rdi = the address of the string
;;;   Returns  : nothing
;;;   Clobbers : nothing visible -- rax and rdi are pushed and restored
;;;   How it works: scan forward counting bytes until a 0 turns up, then issue
;;;                 ONE `write` with that count. Exactly what printf("%s") does.
;;; ----------------------------------------------------------------------------
print_str:
    push rax                            ; save what we are about to clobber
    push rdi
    mov rax, 0                          ; the running length
.ps_len:
    cmp byte [rdi+rax], 0               ; is this byte the terminator? `byte` is required
                                        ;   -- the brackets alone give no width
    je .ps_done
    inc rax                             ; one more character
    jmp .ps_len
.ps_done:
    mov rdx, rax                        ; write's argument 3: the byte COUNT
    pop rdi                             ; recover the pointer
    mov rax, 1                          ; sys_write
    mov rsi, rdi                        ; argument 2: the bytes -- set BEFORE rdi is
                                        ;   overwritten on the next line
    mov rdi, 1                          ; argument 1: file descriptor 1 = stdout
    syscall                             ; trap into the kernel; destroys rcx and r11
    pop rax                             ; restore the caller's rax
    ret

; -------------------------
; print_int(rdi = value)
; -------------------------
;;; ----------------------------------------------------------------------------
;;; print_int -- print an unsigned integer in decimal. THE CORRECT VERSION.
;;;   Receives : rdi = the value
;;;   Returns  : nothing
;;;   Clobbers : nothing visible -- rax, rbx, rcx, rdx are pushed and restored
;;;   How it works: repeatedly divide by 10. Each remainder is the next digit,
;;;                 produced least significant first, so the digits are written
;;;                 BACKWARDS into the buffer from buf+31 downward. When the loop
;;;                 ends, rdi points at the first digit and `buf+31 - rdi` is the
;;;                 length.
;;;   Compare powersys.asm in this folder, whose copy has one extra line and
;;;   therefore prints nothing at all.
;;; ----------------------------------------------------------------------------
print_int:
    push rax                            ; save everything this function touches
    push rbx
    push rcx
    push rdx
    mov rax, rdi                        ; `div` always divides RDX:RAX
    mov rbx, 10                         ; the divisor -- `div` takes no immediate
    lea rdi, [buf+31]                   ; start at the FAR END and work backwards
    mov byte [rdi], 0                   ; plant the NUL terminator
    cmp rax, 0                          ; the special case: zero would produce no digits
    jne .pi_loop
    dec rdi
    mov byte [rdi], '0'                 ; ...so write one by hand
    jmp .pi_done
.pi_loop:
    xor rdx, rdx                        ; MANDATORY before `div`: rdx is the HIGH half of
                                        ;   the dividend. Junk there gives a wrong answer
                                        ;   or a divide-error exception.
    div rbx                             ; rax := value/10 , rdx := value mod 10.
                                        ;   ONE INSTRUCTION, TWO ANSWERS.
    add dl, '0'                         ; digit VALUE (0-9) -> CHARACTER ('0'-'9'), by
                                        ;   adding 48. `dl` is the low byte of rdx.
    dec rdi                             ; one character to the LEFT...
    mov [rdi], dl                       ; ...and store it
    cmp rax, 0                          ; anything left of the number?
    jne .pi_loop
.pi_done:
    mov rsi, rdi                        ; write's argument 2: the first digit
    mov rdx, buf+31                     ; the end of the buffer...
    sub rdx, rdi                        ; ...minus the start = THE LENGTH.
                                        ;   NOTE what does NOT follow: powersys.asm has
                                        ;   a stray `mov rdx, rdi` here, which destroys
                                        ;   this length and breaks the whole program.
    mov rax, 1                          ; sys_write
    mov rdi, 1                          ; stdout
    syscall
    pop rdx                             ; restore, in REVERSE order to the pushes
    pop rcx
    pop rbx
    pop rax
    ret

; -------------------------
; ackermann2(n) = A(2, n)
; -------------------------
;;; ----------------------------------------------------------------------------
;;; ack2 -- the m = 2 row of the Ackermann function: A(2, n) = 2n + 3.
;;;   Receives : rdi = n
;;;   Returns  : rax = A(2, n)
;;;   Clobbers : rax, rdi
;;;   Frame    : 24 bytes per level -- return address, saved rbp, and a push that
;;;              is never read (see the header)
;;;   Recursion: A(2, 0) = 3, A(2, n) = A(2, n-1) + 2. The addition happens AFTER
;;;              the call, on the way out -- but it needs nothing but rax, so no
;;;              value has to be spilled.
;;; ----------------------------------------------------------------------------
ack2:
    push rbp                            ; prologue: save the caller's frame pointer
    mov rbp, rsp                        ; anchor this activation

    cmp rdi, 0                          ; n == 0?
    jne .rec
    mov rax, 3                          ; THE BASE CASE: A(2, 0) = 3
    jmp .out

.rec:
    dec rdi                             ; the argument for the next level: n-1
    push rdi                            ; pushed in the C calling-convention style of
                                        ;   code-0010.asm -- but the callee reads rdi
                                        ;   directly, so THIS IS NEVER READ
    call ack2                           ; rax := A(2, n-1)
    add rsp, 8                          ; caller cleans the stack, undoing that push
    add rax, 2                          ; A(2, n) = A(2, n-1) + 2. Done on the way OUT.
    jmp .out

.out:
    mov rsp, rbp                        ; epilogue: restore rsp from the anchor
    pop rbp                             ; restore the caller's frame pointer
    ret                                 ; pop the return address into rip

; -------------------------
; _start
; -------------------------
;;; ----------------------------------------------------------------------------
;;; _start -- the program entry point. NEVER RETURNS.
;;;   Receives : nothing in registers. argc and argv are on the stack, laid out by
;;;              the kernel; this program ignores them.
;;;   Ends with the exit system call, because there is nobody to return to.
;;; ----------------------------------------------------------------------------
_start:
    mov rdi, msg                        ; print the label
    call print_str

    mov rdi, 4                          ; n = 4. Edit this to try other values, and check
                                        ;   against the closed form 2n+3.
    call ack2                           ; rax := A(2, 4) = 11

    mov rdi, rax                        ; print_int's one argument
    call print_int

    mov rdi, nl                         ; end the line
    call print_str

    mov rax, 60                         ; sys_exit
    xor rdi, rdi                        ; status 0 = success
    syscall                             ; THE PROGRAM ENDS HERE. No `ret` -- the kernel
                                        ;   started us directly.
