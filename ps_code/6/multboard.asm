;;; ============================================================================
;;; multboard.asm -- a 10x10 multiplication table, with the counters in registers
;;; Practice session 6                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints the 10x10 multiplication table, right-aligned in columns four
;;;   characters wide.
;;;   (Verified: prints the same table as code-0018.asm in "lectures code ".)
;;;
;;;   *** READ IT SIDE BY SIDE WITH code-0018.asm. *** They produce byte-identical
;;;   output and take opposite approaches to the same problem -- what to do with
;;;   loop counters when printf is called from inside the loop:
;;;
;;;       code-0018.asm                    multboard.asm
;;;       ---------------------------      ---------------------------
;;;       i, j, p in STACK LOCALS          row, col in REGISTERS
;;;       sub rsp, 8*3 in the prologue     no locals at all
;;;       cmp qword [rbp-8*1], M           cmp rbx, 10
;;;       inc qword [rbp-8*1]              inc rbx
;;;       p += i  (strength reduction)     imul rax, r12  (a real multiply)
;;;
;;;   BOTH ARE CORRECT, and for the same underlying reason: the values that must
;;;   survive `call printf` are kept somewhere printf cannot touch. code-0018.asm
;;;   chooses memory; this file chooses CALLEE-SAVED REGISTERS.
;;;
;;;   THE REGISTERS ARE THE POINT. rbx and r12 are callee-saved, which means
;;;   printf is OBLIGED to hand them back unchanged. rax, rcx, rdx, rsi, rdi and
;;;   r8-r11 are not, and would be destroyed. So the choice of rbx and r12 here
;;;   is not arbitrary -- write the same loop with rcx and r13 and one of them
;;;   silently stops working.
;;;       callee-saved (safe across a call): rbx, rbp, r12, r13, r14, r15, rsp
;;;       caller-saved (destroyed by a call): everything else, xmm included
;;;
;;;   *** AND HERE IS THE BUG. *** rbx and r12 are callee-saved, which cuts both
;;;   ways: THIS function is equally obliged to give them back to ITS caller
;;;   unchanged, and it never saves them. The correct version is
;;;       main:  push rbx / push r12  ...  pop r12 / pop rbx / ret
;;;   Nothing downstream happens to care here, so the program runs -- but it is
;;;   the same latent defect as code-0012.asm and code-0021.asm, and it is the
;;;   reason printf_alignment_demo.asm in ps_code/5 pushes r12 before using it.
;;;
;;;   `imul rax, r12` is the SIGNED multiply in its friendly two-operand form:
;;;   rax := rax * r12, with no hidden registers. Contrast the one-operand
;;;   `mul rcx` in code-0009.asm, which commandeers both rdx and rax whether you
;;;   want it to or not. Prefer `imul` unless you actually need the 128-bit
;;;   product.
;;;
;;;   `%4ld` right-aligns in a field four characters wide -- which is the whole
;;;   difference between a table and a stream of numbers.
;;;
;;;   THE `<<< FIXED` COMMENTS in the original are someone's repair notes from
;;;   the practice session. They mark the lines where a first draft presumably
;;;   used the wrong register for the inner counter.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/6/multboard.asm"
;;;
;;;   Confirm it matches the lecture version exactly:
;;;   diff <(./asm "ps_code/6/multboard.asm") \
;;;        <(./asm "lectures code /code-0018.asm") && echo IDENTICAL
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/6/multboard.asm"
;;;
;;;   THE experiment for this file -- watch callee-saved registers survive:
;;;     break printf
;;;     c
;;;     info registers rbx r12         the row and column
;;;     p $rax                         0 -- the variadic count
;;;     finish                         let printf run to completion
;;;     info registers rbx r12         UNCHANGED. printf preserved them, exactly
;;;                                    as the ABI requires.
;;;     p $rax                         destroyed -- it now holds printf's
;;;                                    character count
;;;
;;;   Now do the same thing in code-0018.asm and compare:
;;;     ./debug "lectures code /code-0018.asm"
;;;     break printf
;;;     c
;;;     x/3gd $rbp-24                  i, j, p -- in MEMORY
;;;     finish
;;;     x/3gd $rbp-24                  also unchanged, for a different reason:
;;;                                    printf never touched that memory
;;;   Two mechanisms, one guarantee. Registers are faster; memory is unlimited.
;;;
;;;   Watch the table being built:
;;;     break multboard.asm:NN         NN on the `imul rax, r12` line
;;;     c
;;;     info registers rbx r12         row and column
;;;     si
;;;     p $rax                         their product
;;;     c                              next cell
;;;
;;;   And catch the bug in the act:
;;;     break main
;;;     p/x $rbx                       whatever the C library left there
;;;     p/x $r12
;;;     break multboard.asm:NN         NN on the `ret` line
;;;     c
;;;     p/x $rbx                       11 -- a promise has been broken
;;;     p/x $r12                       11
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE STACK IS ALMOST IDLE, AND THAT IS THE ACHIEVEMENT. `bt` shows two
;;;   frames whatever cell you stop in; `p $rsp` never moves after the prologue;
;;;   there are no locals and no pushes anywhere. One hundred and ten calls to
;;;   printf, and the program's own stack usage is sixteen bytes.
;;;
;;;   Compare that with code-0018.asm, which allocates 24 bytes of locals and
;;;   reads and writes memory on every compare and every increment. Both are
;;;   correct; this one is faster, and the reason is simply that registers are
;;;   faster than memory. The catch is that there are only six callee-saved
;;;   registers, so the technique does not scale -- a loop nest with ten live
;;;   variables must spill to the frame, and then you are back to code-0018.asm's
;;;   layout diagram whether you like it or not.
;;;
;;;   THAT IS REGISTER ALLOCATION, and it is most of what an optimising compiler
;;;   spends its time on: decide which values are hot enough to deserve a
;;;   register, put the rest in the frame, and insert the pushes and pops to keep
;;;   the ABI's promises. Here you are doing it by hand -- including, in this
;;;   file, forgetting the pushes.
;;;
;;;   One alignment note, since nothing in the source mentions it. There is no
;;;   `and rsp, -16` here, and it works out: `call main` left rsp at 8 mod 16,
;;;   `push rbp` made it 0, and `call printf` pushes 8 more, so printf sees the 8
;;;   mod 16 the ABI promises. Check it with `break printf` then `p $rsp % 16`.
;;;   Add the two missing `push`es for rbx and r12 and that arithmetic changes --
;;;   two more pushes leave rsp back at 0 mod 16, so it still works, but you
;;;   should verify rather than assume. This is exactly the trap
;;;   printf_alignment_demo.asm in ps_code/5 exists to demonstrate.
;;; ============================================================================

section .data                           ; initialised, writable data
fmt_int:     db '%4ld', 0               ; one 64-bit decimal, RIGHT-ALIGNED in a field
                                        ;   four characters wide. Single quotes do not
                                        ;   expand escapes in NASM, so the terminator
                                        ;   is written as the number 0.
fmt_newline: db 10, 0                   ; just a newline (byte 10) and a NUL -- printed
                                        ;   once per row

extern printf                           ; supplied by the C library
global main                             ; export `main` for the C library start-up

section .text                           ; the executable-code section
;;; ----------------------------------------------------------------------------
;;; main -- print a 10x10 multiplication table.
;;;   C equivalent : for (row = 1; row <= 10; row++) {
;;;                      for (col = 1; col <= 10; col++) printf("%4ld", row*col);
;;;                      printf("\n");
;;;                  }
;;;   Receives : nothing
;;;   Returns  : rax = printf's character count (never reset to 0)
;;;   Registers: rbx = the row, r12 = the column -- BOTH CALLEE-SAVED, which is
;;;              exactly why they survive the printf calls inside the loop
;;;   BUG      : rbx and r12 are never pushed or popped, so this function breaks
;;;              the promise it relies on printf keeping. See the header.
;;; ----------------------------------------------------------------------------
main:
    push rbp                            ; prologue: save the caller's frame pointer.
                                        ;   Also takes rsp from 8 mod 16 to 0 mod 16,
                                        ;   which is what makes the printf calls legal.
    mov rbp, rsp                        ; anchor the frame. No `sub rsp` -- there are no
                                        ;   locals, because the counters live in
                                        ;   registers.

    mov rbx, 1                          ; row = 1
                                        ;   rbx is CALLEE-SAVED, so printf must give it
                                        ;   back unchanged. That is the whole reason
                                        ;   this register and not, say, rcx.

row_loop:
    cmp rbx, 10                         ; have we finished all ten rows?
    jg done                             ; `jg` = jump if greater, signed

    mov r12, 1                          ; col = 1   <<< FIXED
                                        ;   r12 is also callee-saved. Reset at the top
                                        ;   of every row.

col_loop:
    cmp r12, 10                         ;           <<< FIXED
    jg end_row                          ; the row is complete

    mov rax, rbx                        ; rax := row
    imul rax, r12                       ; rax = row * col   <<< FIXED
                                        ;   the two-operand SIGNED multiply: rax :=
                                        ;   rax * r12, with no hidden registers.
                                        ;   Contrast the one-operand `mul`, which
                                        ;   always writes RDX:RAX.

    mov rdi, fmt_int                    ; printf argument 1: the format string
    mov rsi, rax                        ; argument 2: the product
    xor rax, rax                        ; THE VARIADIC RULE: rax = the number of VECTOR
                                        ;   registers carrying arguments. No floats, so 0.
    call printf                         ; rbx and r12 sail through untouched

    inc r12                             ;           <<< FIXED
                                        ;   next column -- the register still holds the
                                        ;   right value because printf preserved it
    jmp col_loop

end_row:
    mov rdi, fmt_newline                ; end the line
    xor rax, rax                        ; 0 vector registers in use
    call printf

    inc rbx                             ; next row
    jmp row_loop

done:
    mov rsp, rbp                        ; epilogue: restore rsp from the anchor
    pop rbp                             ; restore the caller's frame pointer.
                                        ;   NOTE: rbx and r12 are NOT restored -- see
                                        ;   the bug described in the header.
    ret                                 ; pop the return address into rip
