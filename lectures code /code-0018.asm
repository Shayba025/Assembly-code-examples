;;; ============================================================================
;;; code-0018.asm -- Printing a multiplication table
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints a 10x10 multiplication table, right-aligned in columns four
;;;   characters wide. No command-line argument, no error path -- this file is
;;;   about ONE thing: NESTED LOOPS WHOSE VARIABLES LIVE ENTIRELY IN THE FRAME.
;;;
;;;   Every earlier loop in this course kept its counter in a register and had
;;;   to fight to protect it across `call printf` -- by pushing it (code-0002),
;;;   by keeping it in .data (code-0003), or by copying it to a stack slot
;;;   before each call and back after (code-0015). This file takes the fourth
;;;   and cleanest option: THE VARIABLES NEVER LEAVE MEMORY AT ALL.
;;;
;;;       cmp qword [rbp - 8*1], M      ; compare a variable in place
;;;       inc qword [rbp - 8*1]         ; increment it in place
;;;       add qword [rbp - 8*3], rax    ; accumulate into it in place
;;;
;;;   x86 is a two-address, memory-operand architecture, so a variable in a
;;;   stack slot can be compared, incremented and added to without ever being
;;;   loaded. Nothing needs saving across a call, because nothing valuable is
;;;   in a register when the call happens. Read this next to code-0015 and the
;;;   contrast is the lesson.
;;;
;;;   THE OTHER NICE TRICK: there is no multiply anywhere in this program. The
;;;   inner loop keeps a running product p and does `p += i` each pass, so the
;;;   values printed on row i are i, 2i, 3i, ... That is STRENGTH REDUCTION --
;;;   replacing a multiplication by a repeated addition -- and it is one of the
;;;   oldest optimisations a compiler performs. Note that p is reset to 0 at the
;;;   top of each ROW, which is what makes each row start over at i.
;;;
;;;   `%4lld` right-aligns in a field of four characters. That is what turns a
;;;   stream of numbers into a table.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0018.asm"
;;;
;;;   To change the size, edit `M equ 10` at the top and re-run. Try 5 and 15,
;;;   and note that with M = 15 the columns start to touch -- the field width in
;;;   `%4lld` is a separate constant that does not track M.
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0018.asm"
;;;
;;;   Useful session -- the whole program is three variables, so watch all three:
;;;     break code-0018.asm:NN     put NN on the `add qword [rbp - 8*3], rax` line
;;;     c
;;;     x/1gd $rbp-8               i, the row
;;;     x/1gd $rbp-16              j, the column
;;;     x/1gd $rbp-24              p, the running product
;;;
;;;   Better, let gdb do it automatically after every stop:
;;;     display/d *(long*)($rbp-8)
;;;     display/d *(long*)($rbp-16)
;;;     display/d *(long*)($rbp-24)
;;;     c   c   c                  and watch p climb i, 2i, 3i...
;;;
;;;   See the whole locals block as memory:
;;;     x/3gd $rbp-24              p, j, i -- in ascending address order
;;;
;;;   And watch an instruction modify memory with no register involved:
;;;     break code-0018.asm:NN     NN on an `inc qword [rbp - 8*2]` line
;;;     x/1gd $rbp-16
;;;     si
;;;     x/1gd $rbp-16              one higher, and no register changed
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Start with the professor's diagram. `sub rsp, 8*3` in the prologue is the
;;;   whole of "declare three local variables":
;;;
;;;       [rbp + 8*1]   ret addr    <- the caller's business
;;;       [rbp + 8*0]   old rbp     <- pushed by the prologue
;;;       [rbp - 8*1]   i           <-.
;;;       [rbp - 8*2]   j            |  the 24 bytes claimed by `sub rsp, 8*3`
;;;       [rbp - 8*3]   p           <-'
;;;
;;;   In C that prologue is written `long i, j, p;` and the compiler picks the
;;;   offsets. Here you pick them. That is the entire difference.
;;;
;;;   THE EXPERIMENT THAT MAKES THE POINT. Break on `printf`, then:
;;;       bt                     two frames -- always, all 100 iterations
;;;       p $rbp                 identical at every stop
;;;       p $rsp                 identical at every stop
;;;       finish                 let printf return
;;;       info registers rax rsi rdi
;;;                              all three trashed by printf...
;;;       x/3gd $rbp-24          ...and i, j and p are all exactly as you left
;;;                              them
;;;   THAT is the payoff. There is no save/restore code anywhere in this program
;;;   -- not a single push around a call, not a single reload afterwards --
;;;   because no live value was ever in a register to begin with. Compare the
;;;   `mov qword [rbp - 8*1], rax` / `mov rax, qword [rbp - 8*1]` pair that
;;;   code-0015 needs around every printf.
;;;
;;;   THE COST, so you know the trade: memory operands are slower than
;;;   registers, and this loop touches memory on every compare and every
;;;   increment. A real compiler would keep i and j in CALLEE-SAVED registers
;;;   (rbx, r12, r13) -- pushed once in the prologue, popped once in the
;;;   epilogue, safe across every call in between, and fast throughout. That is
;;;   the third option, and it is why callee-saved registers exist at all. Look
;;;   for it in the ps_code exercises.
;;;
;;;   Last thing: notice the ORDER of `sub rsp, 8*3` and `and rsp, -16`. The sub
;;;   claims the space; the and then rounds rsp further down for the printf.
;;;   Doing them the other way round would let the alignment eat into your
;;;   locals. Space first, alignment second -- always.
;;; ============================================================================

        M equ 10                        ; `equ` = an assemble-time constant, substituted
                                        ;   before anything is assembled. The table is MxM.

section .data                           ; initialised, writable data
fmt_product:
        db `%4lld\0`                    ; one 64-bit decimal, RIGHT-ALIGNED in a field 4
                                        ;   characters wide. The "4" is what makes the
                                        ;   output a table instead of a stream. No \n --
                                        ;   the whole row is printed on one line.
fmt_newline:
        db `\n\0`                       ; printed once per row, to end the line

extern printf                           ; supplied by the C library
global main                             ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- print an M x M multiplication table.
;;;   C equivalent:
;;;       int main(void) {
;;;           long i, j, p;
;;;           for (i = 1; i <= M; i++) {
;;;               for (j = 1, p = 0; j <= M; j++) { p += i; printf("%4lld", p); }
;;;               printf("\n");
;;;           }
;;;       }
;;;   Receives  : nothing
;;;   Returns   : rax = 0
;;;   Locals    : [rbp-8*1] = i (row), [rbp-8*2] = j (column),
;;;               [rbp-8*3] = p (the running product for this row)
;;;   How it works: two nested counted loops. The inner one adds i to p each
;;;               pass instead of multiplying -- strength reduction. Every
;;;               variable is compared, incremented and accumulated IN MEMORY,
;;;               so the calls to printf need no register protection at all.
;;; ----------------------------------------------------------------------------
main:
        push rbp                        ; saving the old fp (rbp is callee-saved)
        mov rbp, rsp                    ; setting the fp to the base of the new frame --
                                        ;   the anchor all three locals are measured from
        sub rsp, 8*3                    ; reserving 3 local variables. Moving rsp DOWN by
                                        ;   24 bytes claims that much stack. This one
                                        ;   instruction is the entire implementation of
                                        ;   `long i, j, p;`.
        and rsp, -16                    ; aligning the stack on 16 bytes for printf. Done
                                        ;   AFTER the sub, so the alignment padding is taken
                                        ;   from below the locals, never out of them.

;;; The Activation Frame:
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | i        | qword [rbp - 8*1] |
;;; |         | j        | qword [rbp - 8*2] |
;;; |         | p        | qword [rbp - 8*3] |
                                        ; Positive offsets = the caller's world; negative
                                        ;   offsets = your own locals. Memorise this shape.

        mov qword [rbp - 8*1], 1        ; initializing the outer loop: i = 1
                                        ;   A store straight to memory: `qword` says the
                                        ;   operand is 8 bytes wide, which NASM cannot
                                        ;   infer from the constant 1 alone.

.loop_1:                                ; printing rows -- the OUTER loop over i
        cmp qword [rbp - 8*1], M        ; when i > M we are done. Compares a memory
                                        ;   operand against an immediate; no register is
                                        ;   involved at all.
        jg .done                        ; `jg` = jump if greater (signed)

        mov qword [rbp - 8*2], 1        ; initialize the inner loop: j = 1
        mov qword [rbp - 8*3], 0        ; p (product) = 0 -- reset at the start of EVERY
                                        ;   row, which is what makes row i begin at i

.loop_2:                                ; the INNER loop over j
        cmp qword [rbp - 8*2], M        ; when j > M we are done with inner loop
        jg .exit_loop_2
        mov rax, qword [rbp - 8*1]      ; load i into a scratch register, only because
                                        ;   x86 cannot add one memory operand to another
        add qword [rbp - 8*3], rax      ; p += i to get the next product
                                        ;   READ-MODIFY-WRITE directly in memory. This is
                                        ;   STRENGTH REDUCTION: the table is built with
                                        ;   additions, and the program contains no multiply
                                        ;   instruction anywhere.

        mov rdi, fmt_product            ; format string for printing the product
        mov rsi, qword [rbp - 8*3]      ; p (printf argument 2), loaded fresh from the
                                        ;   frame -- and note nothing is saved before the
                                        ;   call, because nothing needs to be
        mov rax, 0                      ; no fp registers in use (the variadic rule)
        call printf
        inc qword [rbp - 8*2]           ; ++j -- increments the variable IN PLACE, with
                                        ;   no load and no store of our own
        jmp .loop_2                     ; round again

.exit_loop_2:                           ; we print a newline, and update
        mov rdi, fmt_newline            ; '\n'
        mov rax, 0                      ; no fp registers in use
        call printf
        inc qword [rbp - 8*1]           ; ++i -- again, straight to memory
        jmp .loop_1                     ; next row

.done:
        mov rax, 0                      ; status: OK
        mov rsp, rbp                    ; restore the stack pointer -- frees all three
                                        ;   locals and the alignment padding at once
        pop rbp                         ; restore the frame pointer
        ret                             ; pop the return address into rip

section .note.GNU-stack noalloc noexec  ; required Linux marker: stack is not exec
