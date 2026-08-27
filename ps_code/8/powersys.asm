;;; ============================================================================
;;; powersys.asm -- 3^5 by recursion, printed with system calls. AND A REAL BUG.
;;; Practice session 8                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   It is meant to compute 3^5 = 243 recursively and print "3^5 = 243".
;;;   *** IT PRINTS "3^5 = " AND THEN NOTHING. *** The number is computed
;;;   correctly and then thrown away by a one-line bug in `print_int`.
;;;   (Verified: the output really is just `3^5 = ` followed by a newline.)
;;;
;;;   FIND IT BEFORE YOU READ ON. Look at the end of `print_int`:
;;;
;;;       mov rsi, rdi            ; rsi := the address of the first digit
;;;       mov rdx, buf+31         ; rdx := the end of the buffer
;;;       sub rdx,  rdi           ; rdx := how many digits  <- the LENGTH
;;;       mov rax, 1              ; sys_write
;;;       mov rdx, rdi            ; *** THIS LINE ***
;;;       mov rdi, 1              ; stdout
;;;       syscall
;;;
;;;   `mov rdx, rdi` overwrites the carefully computed LENGTH with the buffer
;;;   POINTER. write() is then asked to output some enormous number of bytes
;;;   starting at rsi, the kernel refuses with -EFAULT, and nothing appears. The
;;;   line is a leftover -- delete it and the program works.
;;;
;;;   Compare the IDENTICAL function in ackermann_safe.asm in this same folder,
;;;   which does not have the extra line and prints correctly. Diffing the two is
;;;   the fastest way to see it:
;;;       diff <(sed -n '/^print_int/,/^ *ret/p' originals/ps_code/8/powersys.asm) \
;;;            <(sed -n '/^print_int/,/^ *ret/p' originals/ps_code/8/ackermann_safe.asm)
;;;
;;;   THE REST OF THE FILE IS WORTH READING, because it builds from scratch two
;;;   things the C library normally hands you:
;;;
;;;   1. `print_str` -- strlen and write, by hand. It walks the bytes counting
;;;      until it finds a 0, then issues one `write` with that count. That is
;;;      literally what `printf("%s", p)` does underneath.
;;;
;;;   2. `print_int` -- integer-to-decimal conversion, by hand. Repeatedly divide
;;;      by 10; each remainder is the next digit, produced LEAST significant
;;;      first. Since you need them in the opposite order, the digits are written
;;;      BACKWARDS into a buffer, starting from the end:
;;;          lea rdi, [buf+31]      ; start at the far end
;;;          mov byte [rdi], 0      ; the terminator
;;;          ... dec rdi ; mov [rdi], dl ...
;;;      When the loop finishes, rdi points at the first digit and
;;;      `buf+31 - rdi` is the length. That "fill a buffer backwards" idiom is
;;;      how every itoa in the world is written.
;;;
;;;   `add dl, '0'` converts a digit VALUE (0-9) into a CHARACTER ('0'-'9') by
;;;   adding 48. The inverse of the `- '0'` you saw in code-0016.asm.
;;;
;;;   IT DEFINES `_start`, NOT `main`, so there is no C library at all. The
;;;   ./asm and ./debug scripts notice the `global _start` and link it with plain
;;;   `ld`. That is also why the program must end with the exit system call
;;;   rather than a `ret` -- there is nobody to return to.
;;;
;;;   A SECOND, HARMLESS ODDITY: `pow` pushes its arguments and then does
;;;   `add rsp, 16` after the call, in the C calling-convention style of
;;;   code-0010.asm -- but the callee reads its arguments from rdi and rsi, not
;;;   from the stack, so the pushes are never read. Four wasted instructions.
;;;   Delete them and nothing changes.
;;;
;;;   AND A LATENT ONE: `mul rdi` is the ONE-OPERAND unsigned multiply, so it
;;;   silently writes rdx as well as rax. Here rdx is dead, so it does not
;;;   matter -- but `imul rax, rdi` would have been the right instruction.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/8/powersys.asm" ; echo "exit status = $?"
;;;
;;;   Then FIX IT: delete the `mov rdx, rdi` line near the end of print_int,
;;;   re-run, and you should get `3^5 = 243`.
;;;
;;;   To change the numbers, edit `mov rdi, 3` and `mov rsi, 5` in `_start` (and
;;;   the msg_pow string). Careful: `pow` recurses once per unit of the exponent,
;;;   and there is no overflow check -- 3^41 already exceeds 64 bits.
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/8/powersys.asm"
;;;
;;;   gdb stops at `main` by default and there is no `main`, so:
;;;     break _start
;;;     c
;;;
;;;   PROVE THE ANSWER IS COMPUTED CORRECTLY, and only the printing is broken:
;;;     break print_int
;;;     c
;;;     p $rdi                    243 -- the value arrives intact
;;;
;;;   Then catch the bug in the act:
;;;     break powersys.asm:NN     NN on the `sub rdx,  rdi` line
;;;     c
;;;     si
;;;     p $rdx                    3 -- the correct length, three digits
;;;     si                        mov rax, 1
;;;     si                        mov rdx, rdi   <- the bad line
;;;     p/x $rdx                  an ADDRESS, not a length. The bug, on screen.
;;;     si si                     mov rdi, 1 ; syscall
;;;     p $rax                    a negative number: -EFAULT. write() refused.
;;;
;;;   And inspect the backwards-filled buffer:
;;;     break powersys.asm:NN     NN on the `.pi_done` label
;;;     c
;;;     x/s $rdi                  "243"
;;;     p (char*)&buf+31 - $rdi   3, the length that SHOULD have been used
;;;     x/32xb &buf               the whole buffer: mostly zero, digits at the end
;;;
;;;   Watch the digits being produced in reverse:
;;;     break powersys.asm:NN     NN on the `div rbx` line
;;;     c
;;;     p $rax                    243
;;;     si
;;;     p $rax                    24  -- the quotient
;;;     p $rdx                    3   -- the remainder, i.e. the LAST digit first
;;;     c                         then 4, then 2
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   TWO DIFFERENT DISCIPLINES ARE ON DISPLAY, and comparing them is the lesson.
;;;
;;;   `print_str`, `print_int` and `print_dot` all begin with a row of pushes and
;;;   end with the matching pops in REVERSE ORDER:
;;;       push rax / push rbx / push rcx / push rdx ... pop rdx / pop rcx / pop rbx / pop rax
;;;   That is a function being POLITE: it saves everything it is about to
;;;   clobber, whether the ABI requires it or not. In a freestanding program with
;;;   no C library there is no ABI to appeal to, so saving everything is a
;;;   reasonable house rule. The reversal is not stylistic -- the stack is
;;;   last-in first-out, so the pops must mirror the pushes exactly or rsp ends
;;;   up pointing at the wrong quadword.
;;;
;;;   `pow`, by contrast, builds a frame (`push rbp / mov rbp, rsp` ... `mov rsp,
;;;   rbp / pop rbp`) and additionally pushes two arguments it never reads. Watch
;;;   the cost:
;;;       break pow
;;;       c
;;;       p $rsp                  note it
;;;       c
;;;       p $rsp                  32 bytes lower per level -- 8 return address,
;;;                               8 saved rbp, and 16 of pushes that do nothing
;;;       bt                      one frame per level of the exponent
;;;   Five levels for 3^5, so 160 bytes, of which 80 are pure waste. Delete the
;;;   `push rdi / push rsi / add rsp, 16` and measure again.
;;;
;;;   THE THIRD THING TO NOTICE is where the recursion actually does its work.
;;;   `mul rdi` happens AFTER the recursive call returns, so the multiplications
;;;   run on the way OUT: 1, 3, 9, 27, 81, 243. Step it with repeated `finish`
;;;   and print rax each time. That is the same shape as `fact` in code-0010.asm,
;;;   and the reason a frame per level is genuinely needed -- unlike gcd.asm in
;;;   ps_code/6, whose recursion has nothing after the call and can be a loop.
;;; ============================================================================

; power_syscall.asm — compute 3^5 recursively and print result using syscalls

global _start                           ; THE PROGRAM'S ENTRY POINT -- not `main`. The
                                        ;   kernel jumps straight here, with no C
                                        ;   library involved at all.

section .data                           ; initialised, writable data
msg_pow:    db "3^5 = ", 0              ; a C string: the trailing 0 is what print_str
                                        ;   scans for
msg_nl:     db 10, 0                    ; just a newline (byte 10)

section .bss                            ; zero-filled at load time, no file space
buf:        resb 32                     ; buffer for integer to string
                                        ;   filled BACKWARDS, from buf+31 downward --
                                        ;   see the header

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
;;;                 ONE `write` with that count. This is exactly what
;;;                 printf("%s") does underneath.
;;; ----------------------------------------------------------------------------
print_str:
    push rax                            ; save the registers we are about to use -- this
    push rdi                            ;   function is being polite, since there is no
                                        ;   ABI to consult in a freestanding program
    mov rax, 0                          ; the running length
.len_loop:
    cmp byte [rdi+rax], 0               ; is this byte the terminator? `byte` is required
                                        ;   -- the brackets alone do not give a width
    je .len_done
    inc rax                             ; one more character
    jmp .len_loop
.len_done:
    mov rdx, rax                        ; len
                                        ;   write's argument 3: the byte COUNT
    pop rdi                             ; restore pointer
                                        ;   recovered from the stack, since the scan used rdi as a base
    mov rax, 1                          ; sys_write
    mov rsi, rdi                        ; argument 2: the bytes to write
    mov rdi, 1                          ; stdout
                                        ;   argument 1: file descriptor 1. Note this OVERWRITES rdi,
                                        ;   which is why rsi had to be set first.
    syscall                             ; trap into the kernel; destroys rcx and r11
    pop rax                             ; restore the caller's rax
    ret                                 ; pop the return address into rip

; -------------------------
; print_int(rdi = value)
; -------------------------
;;; ----------------------------------------------------------------------------
;;; print_int -- print an unsigned integer in decimal. *** CONTAINS THE BUG. ***
;;;   Receives : rdi = the value
;;;   Returns  : nothing
;;;   Clobbers : nothing visible -- rax, rbx, rcx, rdx are pushed and restored
;;;   How it works: repeatedly divide by 10. Each remainder is the next digit,
;;;                 produced LEAST significant first, so the digits are written
;;;                 BACKWARDS into the buffer from buf+31 downward. When the loop
;;;                 ends, rdi points at the first digit.
;;;   THE BUG: the `mov rdx, rdi` below overwrites the computed LENGTH with the
;;;   buffer POINTER, so write() is given a nonsense count and prints nothing.
;;;   Compare the identical function in ackermann_safe.asm, which lacks that line.
;;; ----------------------------------------------------------------------------
print_int:
    push rax                            ; save everything this function touches
    push rbx
    push rcx
    push rdx
    mov rax, rdi                        ; `div` always divides RDX:RAX, so the value has
                                        ;   to be in rax
    mov rbx, 10                         ; the divisor. `div` takes no immediate operand.
    lea rdi, [buf+31]                   ; start at the FAR END of the buffer and work
                                        ;   backwards -- the digits come out in reverse
    mov byte [rdi], 0                   ; plant the NUL terminator
    cmp rax, 0                          ; the special case: zero has no digits by this
    jne .pi_loop                        ;   algorithm, because the loop would not run
    dec rdi
    mov byte [rdi], '0'                 ; ...so write one by hand
    jmp .pi_done
.pi_loop:
    xor rdx, rdx                        ; MANDATORY before `div`: rdx is the HIGH 64 bits
                                        ;   of the dividend. Junk there gives a wrong
                                        ;   answer or a divide-error exception.
    div rbx                             ; rax := value/10 , rdx := value mod 10.
                                        ;   ONE INSTRUCTION, TWO ANSWERS -- the remainder
                                        ;   is the next digit.
    add dl, '0'                         ; convert the digit VALUE (0-9) into a CHARACTER
                                        ;   ('0'-'9') by adding 48. `dl` is the low byte
                                        ;   of rdx. The inverse of code-0016.asm's `- '0'`.
    dec rdi                             ; move one character to the LEFT...
    mov [rdi], dl                       ; ...and store the digit there
    cmp rax, 0                          ; anything left of the number?
    jne .pi_loop
.pi_done:
    mov rsi, rdi                        ; write's argument 2: the first digit
    mov rdx, buf+31                     ; the end of the buffer...
    sub rdx,  rdi                       ; ...minus the start = THE LENGTH. Correct here.
    mov rax, 1                          ; sys_write
        mov rdx, rdi                    ; *** THE BUG. *** This destroys the length
                                        ;   computed two lines above, replacing it with
                                        ;   the buffer POINTER. write() is then asked
                                        ;   for an absurd number of bytes and fails with
                                        ;   -EFAULT, printing nothing at all.
                                        ;   DELETE THIS LINE AND THE PROGRAM WORKS.
    mov rdi, 1                          ; stdout
    syscall                             ; ...and returns a negative errno. Check it with
                                        ;   `p $rax` in gdb.
    pop rdx                             ; restore, in REVERSE order to the pushes --
    pop rcx                             ;   the stack is last-in first-out
    pop rbx
    pop rax
    ret

; -------------------------
; pow(base, exp) -> rax
; base in rdi, exp in rsi
; -------------------------
;;; ----------------------------------------------------------------------------
;;; pow -- base^exp by recursion.
;;;   Receives : rdi = base, rsi = exponent
;;;   Returns  : rax = base^exp
;;;   Clobbers : rax, rdx (written by `mul`), rsi
;;;   Frame    : 32 bytes per level -- return address, saved rbp, and two pushed
;;;              arguments THAT ARE NEVER READ (see the header)
;;;   Recursion: pow(b, 0) = 1, pow(b, e) = b * pow(b, e-1). The multiply happens
;;;              AFTER the recursive call, on the way out -- which is why a frame
;;;              per level is genuinely needed.
;;;   No overflow check: 3^41 already exceeds 64 bits.
;;; ----------------------------------------------------------------------------
pow:
    push rbp                            ; prologue: save the caller's frame pointer
    mov rbp, rsp                        ; anchor this activation

    cmp rsi, 0                          ; exponent zero?
    jne .recurse
    mov rax, 1                          ; THE BASE CASE: anything to the power 0 is 1
    jmp .out

.recurse:
    dec rsi                             ; the argument for the next level: exp-1
    push rdi                            ; pushed in the C calling-convention style of
    push rsi                            ;   code-0010.asm -- but the callee reads rdi and
                                        ;   rsi directly, so THESE ARE NEVER READ. Four
                                        ;   wasted instructions; delete them and the two
                                        ;   below and nothing changes.
    call pow                            ; rax := base^(exp-1)
    add rsp, 16                         ; caller cleans the stack -- undoing the two
                                        ;   pushes above
    mul rdi                             ; RDX:RAX := RAX * rdi = base^(exp-1) * base.
                                        ;   The ONE-OPERAND unsigned multiply, so it
                                        ;   silently writes rdx too. `imul rax, rdi`
                                        ;   would have been the tidier choice.
                                        ;   rdi survived the recursion because nothing
                                        ;   in `pow` writes it.

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
;;;   Ends with the exit system call, because there is no caller to return to.
;;; ----------------------------------------------------------------------------
_start:
    mov rdi, msg_pow                    ; print the label
    call print_str

    mov rdi, 3                          ; base
    mov rsi, 5                          ; exponent
    call pow                            ; rax = 3^5
                                        ;   the answer, 243, is correct at this point -- verify with
                                        ;   `break print_int` and `p $rdi`

    mov rdi, rax                        ; print_int's one argument
    call print_int                      ; ...which silently prints nothing. See the bug.

    mov rdi, msg_nl                     ; end the line
    call print_str

    mov rax, 60                         ; sys_exit
    xor rdi, rdi                        ; status 0 = success
    syscall                             ; THE PROGRAM ENDS HERE. No `ret` -- the kernel
                                        ;   started us directly, so there is nobody to
                                        ;   return to.
