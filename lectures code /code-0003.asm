;;; ============================================================================
;;; code-0003.asm -- Add the numbers on the command line and print the sum
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Treats every command-line argument as a number, adds them all up, and
;;;   prints the total. `./prog 1 2 3` prints "The sum of 3 number(s) is 6".
;;;
;;;   Two new ideas beyond code-0002:
;;;
;;;   1. CALLING A C FUNCTION THAT RETURNS A VALUE. `atoll` converts a string
;;;      to a long long:  long long atoll(const char *s);
;;;      One pointer argument in rdi, the answer comes back in rax. Every
;;;      integer-returning C function in this course works exactly this way.
;;;
;;;   2. ACCUMULATING IN MEMORY RATHER THAN A REGISTER. The loop keeps `i` and
;;;      `sum` in .data, not in registers, precisely because `call atoll` is
;;;      allowed to destroy every caller-saved register. `add qword [sum], rax`
;;;      is a read-modify-write straight to memory, so nothing needs protecting.
;;;      Compare code-0002, which chose the opposite tactic (push/pop around the
;;;      call). Both are correct; know when each is cheaper.
;;;
;;;   Note the deliberate off-by-one at the end: argc counts the executable
;;;   name, so the printed COUNT is decremented, while the SUM was computed from
;;;   i = 1 and so never included argv[0] in the first place.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0003.asm" 10 20 30
;;;   ./asm "lectures code /code-0003.asm" 5 -3 100 -2
;;;   ./asm "lectures code /code-0003.asm"            # no arguments: sum is 0
;;;
;;;   Try feeding it something that is not a number -- `./asm ... 12 abc 4` --
;;;   and note that atoll quietly returns 0 rather than complaining. code-0004
;;;   shows how to validate input properly.
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0003.asm" 10 20 30
;;;
;;;   Useful session:
;;;     break atoll             stop at every conversion
;;;     c                       continue to the first one
;;;     x/s $rdi                the string atoll is about to convert
;;;     finish                  run atoll to completion...
;;;     p $rax                  ...and here is the number it produced
;;;     p (long)sum             the running total, read from .data by name
;;;     p (long)i               the loop index
;;;     c                       round again
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Break on `atoll` and type `bt`:
;;;       #0  atoll (...)
;;;       #1  main () at code-0003.asm:NN
;;;   Continue and `bt` again -- still exactly two frames, every single time.
;;;   The stack does not grow with the number of arguments because a call that
;;;   RETURNS before the next one starts reuses the same stack space. Depth on
;;;   the stack measures nesting, never repetition.
;;;
;;;   The instructive experiment here is to see why `sum` lives in memory.
;;;   Break on the `call atoll` line, `p $rsi`, `finish`, `p $rsi` -- rsi has
;;;   been clobbered by the C library. Now do the same for the memory location:
;;;   `p (long)sum` before and after. Unchanged. Registers are borrowed across a
;;;   call; memory is owned. `info frame` will also show you the return address
;;;   pushed by `call atoll` sitting at the top of the stack -- that is the one
;;;   piece of state the callee must not disturb.
;;; ============================================================================

section .data                           ; initialised, writable memory
fmt_sum:
        db `The sum of %ld number(s) is %ld\n\0`
                                        ; `db` emits raw bytes; backquotes let \n and \0 be
                                        ;   real control characters. Two %ld conversions =
                                        ;   two 64-bit signed decimal arguments.
i:
        dq 1                            ; `dq` ("define quadword") emits 8 initialised
                                        ;   bytes. The loop index, starting at 1 so that
                                        ;   argv[0] (the program's own name) is skipped.
sum:
        dq 0                            ; the running total, initially zero

section .bss                            ; zero-filled at load time, no file space used
argc:
        resq 1                          ; `resq 1` reserves one 8-byte slot for argc
argv:
        resq 1                          ; ... and one for the argv pointer

extern atoll, printf                    ; both live in the C library; the linker binds them
global main                             ; export main so the C start-up code can call it

section .text
;;; ----------------------------------------------------------------------------
;;; main -- sum the command-line arguments.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0
;;;   How it works: stashes argc/argv in .bss, then loops i = 1 .. argc-1. Each
;;;                 pass converts argv[i] with atoll and folds the result into
;;;                 the memory variable `sum`. Because the accumulator and the
;;;                 index both live in memory, the call to atoll needs no
;;;                 register protection at all. Finally prints count and sum.
;;; ----------------------------------------------------------------------------
main:
        push rbp                        ; prologue 1/2: save the caller's frame pointer
                                        ;   (rbp is callee-saved -- we must return it intact)
        mov rbp, rsp                    ; prologue 2/2: anchor the frame at the current top
        and rsp, -16                    ; clear rsp's low 4 bits, rounding it DOWN to a
                                        ;   multiple of 16 as the ABI demands before `call`

                                        ; recall: int main(int argc, char *argv[]) { ... }
        mov qword [argc], rdi           ; save argc out of the volatile register rdi and
                                        ;   into memory, where no callee can touch it
        mov qword [argv], rsi           ; same for argv
.L:                                     ; the start of the loop (local label, scoped to main)
        mov rax, qword [i]              ; load the index i into a register so we can both
                                        ;   compare it and use it as a scale factor
        cmp rax, qword [argc]           ; compare i against argc: `cmp` subtracts and keeps
                                        ;   only the resulting flags
        je .done                        ; `je` (jump if equal) fires when i == argc, i.e.
                                        ;   we have consumed every argument

        mov rdi, qword [argv]           ; rdi = the address of the argv array
        mov rdi, qword [rdi + 8*rax]    ; dereference element i. The addressing mode
                                        ;   base + scale*index is computed by the CPU
                                        ;   at no extra cost; the scale is 8 because
                                        ;   each element is a 64-bit pointer. rdi now
                                        ;   holds argv[i] -- a char* -- which is
                                        ;   exactly atoll's one argument.
        call atoll                      ; recall: long long atoll(char *);
                                        ;   Result comes back in rax. atoll is free to
                                        ;   destroy rdi/rsi/rdx/rcx/r8-r11.
        add qword [sum], rax            ; `add dst, src` = dst := dst + src. With a memory
                                        ;   destination this is a read-modify-write in one
                                        ;   instruction: no register needs to survive.
        inc qword [i]                   ; `inc` adds 1 in place; advance to the next index
        jmp .L                          ; unconditional jump back to the top of the loop

.done:
        mov rdi, fmt_sum                ; printf argument 1: the format string's address
        mov rsi, qword [argc]           ; argument 2: number of arguments, incl the
                                        ;   executable name
        dec rsi                         ; `dec` subtracts 1 -- ...but we don't count the
                                        ;   executable name, so report argc - 1
        mov rdx, qword [sum]            ; argument 3: the accumulated sum
        mov rax, 0                      ; variadic rule: 0 vector registers carry arguments
        call printf

        mov rax, 0                      ; return 0 to the shell: OK

        mov rsp, rbp                    ; epilogue 1/2: discard everything this frame did
                                        ;   to rsp by restoring it from the anchor
        pop rbp                         ; epilogue 2/2: `pop` loads [rsp] and adds 8 --
                                        ;   the caller's rbp is back
        ret                             ; pop the return address into rip and resume there

section .note.GNU-stack noalloc noexec  ; required Linux marker: stack is not exec
