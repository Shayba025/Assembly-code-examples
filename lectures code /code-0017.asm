;;; ============================================================================
;;; code-0017.asm -- The Towers of Hanoi in assembly
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints the sequence of moves that solves the Towers of Hanoi for n disks:
;;;       hanoi(n, from, via, to):
;;;           if n == 0: do nothing
;;;           hanoi(n-1, from, to, via)     ; get the top n-1 out of the way
;;;           print "move a disk from `from` to `via`"
;;;           hanoi(n-1, to, via, from)     ; ...and bring them back on top
;;;   2^n - 1 moves, and every one of them forced.
;;;
;;;   WHY THIS FILE MATTERS MORE THAN THE FACTORIALS: it is the first function
;;;   with FOUR stack arguments, and the recursive calls PERMUTE them. Look at
;;;   the two call sites and compare the push order:
;;;
;;;       first  call:   push [rbp+8*5]   push [rbp+8*3]   push [rbp+8*4]   push n-1
;;;       second call:   push [rbp+8*3]   push [rbp+8*4]   push [rbp+8*5]   push n-1
;;;
;;;   Same three peg pointers, three different orders. That permutation IS the
;;;   Hanoi algorithm. Everything else is bookkeeping.
;;;
;;;   READING THE FRAME. Arguments are pushed in order a, b, c, n -- so n, being
;;;   pushed LAST, ends up at the LOWEST address, closest to the return address:
;;;
;;;       [rbp + 8*5]   peg a       <- pushed 1st, highest
;;;       [rbp + 8*4]   peg b
;;;       [rbp + 8*3]   peg c
;;;       [rbp + 8*2]   n           <- pushed 4th, lowest
;;;       [rbp + 8*1]   ret addr    <- pushed by `call`
;;;       [rbp + 8*0]   old rbp     <- pushed by the prologue
;;;
;;;   Read that table before trying to follow any single line of `hanoi`. Every
;;;   `qword [rbp + 8*k]` in the body is just a lookup in it.
;;;
;;;   IT IS PASCAL-STYLE, and here the convention finally earns its keep. Four
;;;   arguments, three call sites -- the C convention would need `add rsp, 8*4`
;;;   after every one of them. Instead there is a single `ret 8*4` at the
;;;   bottom. One operand cleans up 32 bytes on every one of the 2^n returns.
;;;
;;;   WHY THE PEGS ARE POINTERS, NOT LETTERS: peg_a, peg_b and peg_c are
;;;   addresses of one-character C strings, so they can be handed straight to
;;;   printf's %s. Passing the addresses around rather than the characters means
;;;   the permutation is just moving 8-byte values, with no conversion anywhere.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0017.asm" 3        # 7 moves
;;;   ./asm "lectures code /code-0017.asm" 1        # 1 move
;;;   ./asm "lectures code /code-0017.asm" 0        # nothing at all
;;;   ./asm "lectures code /code-0017.asm" 4        # 15 moves
;;;   ./asm "lectures code /code-0017.asm" -1       # usage error
;;;
;;;   Confirm the move count really is 2^n - 1:
;;;   for n in $(seq 0 12); do
;;;       printf "n=%-3d moves=%s\n" $n \
;;;           "$(./asm "lectures code /code-0017.asm" $n | wc -l)"
;;;   done
;;;
;;;   Do NOT try n = 40 -- that is a trillion lines of output.
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0017.asm" 3
;;;
;;;   Useful session:
;;;     break hanoi
;;;     c c c                  descend into the recursion
;;;     bt                     the path from the root call to here
;;;     x/1gd $rbp+16          this frame's n
;;;     x/s *(char**)($rbp+40) this frame's peg a  (offset 8*5)
;;;     x/s *(char**)($rbp+32) this frame's peg b  (offset 8*4)
;;;     x/s *(char**)($rbp+24) this frame's peg c  (offset 8*3)
;;;     up                     step out one level and read the same four slots
;;;     down
;;;
;;;   To see the whole frame at once:
;;;     x/6gx $rbp             six quadwords upward from the anchor: old rbp,
;;;                            ret addr, n, peg c, peg b, peg a -- exactly the
;;;                            table above, in memory
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THIS IS THE BEST FILE IN THE COURSE FOR SEEING WHY FRAMES EXIST. `hanoi`
;;;   has no local variables, uses essentially no registers, and yet each
;;;   activation must remember four values across two recursive calls that both
;;;   destroy every register in sight. Those four values live in the frame, and
;;;   each of the 2^n activations has its own private copy.
;;;
;;;   Do this with n = 3. Break on `hanoi`, hit `c` three times to reach a leaf,
;;;   then walk outward printing each level's pegs:
;;;       frame 0   x/s *(char**)($rbp+40)
;;;       up        x/s *(char**)($rbp+40)
;;;       up        x/s *(char**)($rbp+40)
;;;   You will see A, A, A or A, C, B or similar -- DIFFERENT AT EVERY LEVEL,
;;;   from identical instructions. That is what "each activation has its own
;;;   frame" actually means, and no amount of reading about it substitutes for
;;;   seeing three different answers come out of the same `x/s` command.
;;;
;;;   MEASURE THE FRAME. `p $rsp` at two adjacent levels and subtract: 56 bytes
;;;   (4 arguments + return address + saved rbp, plus alignment). Multiply by
;;;   the depth to get the true memory cost -- and note that the depth is n,
;;;   not 2^n: the stack holds one root-to-leaf path, never the whole tree.
;;;   With n = 20 that is about 1 KB of stack for a million moves.
;;;
;;;   THE PASCAL CONVENTION, MADE VISIBLE. Put a breakpoint on the `ret 8*4`:
;;;       p $rsp
;;;       si
;;;       p $rsp        FORTY bytes higher: 8 for the popped return address
;;;                     plus 32 for the four discarded arguments
;;;   One instruction undoes four pushes and a call. Then look at what is NOT
;;;   after either `call hanoi` in the body: no cleanup at all. In the C style
;;;   there would be an `add rsp, 8*4` in three separate places.
;;;
;;;   ONE ODDITY TO NOTICE: `hanoi` does `and rsp, -16` after its prologue, and
;;;   the professor's diagram marks a possible alignment gap below rbp. That gap
;;;   is why arguments must be addressed from rbp and never from rsp -- rsp may
;;;   have been rounded down by 0 or 8 bytes, and you cannot tell which.
;;; ============================================================================

section .data                                        ; initialised, writable data
fmt_usage:
        db `Usage: ./code-0017 n, where n >= 0\n\0`  ; the error message
fmt_move:
        db `Move a disk from peg %s to peg %s\n\0`
                                                     ; TWO %s conversions, so two POINTERS to strings
peg_a:
        db `A\0`                                     ; a one-character C string. What gets passed
peg_b:                                               ;   around is the ADDRESS of this byte, which is
        db `B\0`                                     ;   why the pegs can be shuffled with plain
peg_c:                                               ;   8-byte moves and handed straight to %s.
        db `C\0`

extern printf, fprintf, atoll, exit, stderr          ; supplied by the C library
global main                                          ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- validate n and start the recursion.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 on bad input
;;;   How it works: pushes the four arguments in the order a, b, c, n and calls
;;;                 hanoi. No cleanup follows, because hanoi is Pascal-style.
;;; ----------------------------------------------------------------------------
main:
        push rbp                                     ; save the old frame-pointer (rbp is callee-saved)
        mov rbp, rsp                                 ; anchor this frame at the current stack top.
                                                     ;   No `and rsp, -16` here -- `hanoi` aligns for
                                                     ;   itself, and main calls nothing else that needs it
                                                     ;   before that point.

        cmp rdi, 2                                   ; argc == 2? `cmp` subtracts, keeps only flags
        jne .usage                                   ; wrong number of arguments
        mov rdi, qword [rsi + 8*1]                   ; argv[1]: rsi is argv, base+8*1 is element 1
        call atoll                                   ; convert the string to a 64-bit integer -> rax
        cmp rax, 0                                   ; is n negative?
        jl .usage                                    ; `jl` = jump if less, SIGNED

        push peg_a                                   ; argument 1 -- pushed FIRST, so it ends up at the
                                                     ;   HIGHEST address: [rbp + 8*5] inside hanoi
        push peg_b                                   ; argument 2 -> [rbp + 8*4]
        push peg_c                                   ; argument 3 -> [rbp + 8*3]
        push rax                                     ; argument 4, n -- pushed LAST, so it sits at the
                                                     ;   LOWEST address, [rbp + 8*2], right above the
                                                     ;   return address
        call hanoi                                   ; solve. `call` pushes the return address, which
                                                     ;   is what makes the offsets above come out at 8*2
                                                     ;   through 8*5.
                                                     ;   NO `add rsp, 8*4` follows: hanoi is Pascal-style
                                                     ;   and cleans up its own arguments.

        mov rax, 0                                   ; status OK for the OS

        mov rsp, rbp                                 ; restore the stack pointer from the anchor
        pop rbp                                      ; restore the caller's frame pointer
        ret                                          ; pop the return address into rip
;;; ----------------------------------------------------------------------------
;;; main.usage -- wrong argument count or a negative n. NEVER RETURNS.
;;; ----------------------------------------------------------------------------
.usage:
        mov rdi, qword [stderr]                      ; FILE *stderr. Brackets: `stderr` is a VARIABLE
                                                     ;   holding a FILE*, so load its contents.
        mov rsi, fmt_usage                           ; the message (fprintf's argument 2)
        mov rax, 0                                   ; 0 floating-point registers in use
        call fprintf                                 ; diagnostics go to stderr, not stdout
        mov rax, -1                                  ; non-zero status for the shell
        call exit                                    ; terminate. Never returns.

;;; ----------------------------------------------------------------------------
;;; hanoi -- print the moves that transfer n disks, Pascal-style convention.
;;;   Pseudo-C   : void hanoi(char *a, char *b, char *c, long n)
;;;                {
;;;                    if (n == 0) return;
;;;                    hanoi(a, c, b, n-1);      /* note: b and c swapped */
;;;                    printf("Move a disk from peg %s to peg %s\n", a, b);
;;;                    hanoi(c, b, a, n-1);      /* note: a and c swapped */
;;;                }
;;;   Receives   : four arguments on the STACK --
;;;                    [rbp + 8*5] peg a   (the source of this level's move)
;;;                    [rbp + 8*4] peg b   (the destination of this level's move)
;;;                    [rbp + 8*3] peg c   (the spare peg)
;;;                    [rbp + 8*2] n       (how many disks)
;;;   Returns    : nothing; the output is the side effect
;;;   Clobbers   : rax, and the printf argument registers
;;;   Cleanup    : ITS OWN, via `ret 8*4` -- 32 bytes of arguments discarded on
;;;                the way out. Call sites must NOT add anything to rsp.
;;;   Stack cost : ~56 bytes per level, and the depth is n (NOT 2^n): the stack
;;;                holds one root-to-leaf path at a time.
;;;
;;;   How it works: the base case n == 0 does nothing. Otherwise it makes two
;;;   recursive calls with the pegs PERMUTED -- and the permutation, not the
;;;   arithmetic, is the algorithm. Every value it needs is re-read from its own
;;;   frame each time, because both recursive calls destroy the registers.
;;; ----------------------------------------------------------------------------
hanoi:
        push rbp                                     ; save the caller's frame-pointer
        mov rbp, rsp                                 ; anchor this activation. From here the offsets in
                                                     ;   the diagram below are fixed for this call, no
                                                     ;   matter what rsp does afterwards.
        and rsp, -16                                 ; align the stack for the printf below. This may
                                                     ;   move rsp down by 0 or 8 bytes -- which is
                                                     ;   exactly why every argument access uses rbp.

;;; The Activation Frame:
;;; |         | peg a    | qword [rbp + 8*5]  |
;;; |         | peg b    | qword [rbp + 8*4]  |
;;; |         | peg c    | qword [rbp + 8*3]  |
;;; |         | n        | qword [rbp + 8*2]  |
;;; |         | ret addr | qword [rbp + 8*1]  |
;;; | rbp --> | old rbp  | qword [rbp]        |
;;; |         | ???      | possible alignment |
                                                     ; Arguments were pushed a, b, c, n -- so the FIRST
                                                     ;   pushed is the HIGHEST, and n, pushed last, is
                                                     ;   nearest the return address. The "???" is the 0
                                                     ;   or 8 bytes that `and rsp, -16` may have eaten.

        cmp qword [rbp + 8*2], 0                     ; n == 0?
        jz .done                                     ; the BASE CASE: zero disks, nothing to move.
                                                     ;   Note it jumps straight to the epilogue, so
                                                     ;   even doing nothing goes out via `ret 8*4`.

                                                     ;; --- first recursive call: hanoi(a, c, b, n-1) ---
                                                     ;; move the top n-1 disks OFF the destination peg, using b as the spare
        push qword [rbp + 8*5]                       ; argument 1 = our peg a  (unchanged)
        push qword [rbp + 8*3]                       ; argument 2 = our peg c  <-- swapped in
        push qword [rbp + 8*4]                       ; argument 3 = our peg b  <-- swapped in
                                                     ;   THIS PERMUTATION IS THE ALGORITHM: the spare
                                                     ;   peg becomes the destination for the sub-problem.
        mov rax, qword [rbp + 8*2]                   ; re-read n from the frame -- no register copy
                                                     ;   could have survived to here
        dec rax                                      ; n - 1
        push rax                                     ; argument 4 = n-1
        call hanoi                                   ; recurse. On return, rsp is already correct --
                                                     ;   `ret 8*4` inside removed all four arguments.

                                                     ;; --- the one move this level is responsible for: a -> b ---
        mov rdi, fmt_move                            ; printf argument 1: the format string
        mov rsi, qword [rbp + 8*5]                   ; argument 2: peg a, the source. Re-read from
                                                     ;   the frame; the recursive call destroyed rsi.
        mov rdx, qword [rbp + 8*4]                   ; argument 3: peg b, the destination
        mov rax, 0                                   ; 0 floating-point registers in use
        call printf

                                                     ;; --- second recursive call: hanoi(c, b, a, n-1) ---
                                                     ;; bring those n-1 disks back, on top, using a as the spare
        push qword [rbp + 8*3]                       ; argument 1 = our peg c  <-- swapped in
        push qword [rbp + 8*4]                       ; argument 2 = our peg b  (unchanged)
        push qword [rbp + 8*5]                       ; argument 3 = our peg a  <-- swapped in
                                                     ;   A DIFFERENT permutation from the first call.
                                                     ;   Compare the two blocks line by line.
        mov rax, qword [rbp + 8*2]                   ; re-read n yet again
        dec rax                                      ; n - 1
        push rax                                     ; argument 4 = n-1
        call hanoi                                   ; recurse
.done:
        mov rsp, rbp                                 ; restore rsp from the anchor -- discards the
                                                     ;   alignment gap and anything still pushed
        pop rbp                                      ; restore the caller's frame-pointer
        ret 8*4                                      ; Pascal-style: the CALLEE cleans the stack. Pops
                                                     ;   the return address into rip, then adds 32 to
                                                     ;   rsp to discard all four arguments. In gdb this
                                                     ;   is a 40-byte jump in rsp in one step.

section .note.GNU-stack noalloc noexec               ; required Linux marker: stack is not exec
