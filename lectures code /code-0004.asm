;;; ============================================================================
;;; code-0004.asm -- Print every binary pattern of n bits (n from the cmd line)
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   `./prog 3` prints all 2^3 = 8 strings of three binary digits, in order:
;;;   000, 001, 010, 011, 100, 101, 110, 111.
;;;
;;;   This is the first RECURSIVE program in the series, and the first one that
;;;   validates its input. Three ideas to take away:
;;;
;;;   1. RECURSION WITH BACKTRACKING. `bin` fills one character of a shared
;;;      buffer, recurses to fill the rest, then UNDOES its change and tries the
;;;      other digit. The pattern "do / recurse / undo" is the heart of every
;;;      exhaustive-search algorithm you will ever write.
;;;
;;;   2. A SENTINEL-TERMINATED BUFFER. The buffer is written once at start-up
;;;      with a '\0' at position n, and never again. Every recursive call
;;;      rewrites only characters 0..n-1, so the string is always valid for %s.
;;;
;;;   3. ERROR HANDLING THE C WAY. Bad usage goes to `stderr` (not stdout) via
;;;      fprintf, and the program leaves through `exit` with a non-zero status.
;;;      Note that stderr is a `FILE *` VARIABLE, so you need TWO loads:
;;;      `mov rdi, qword [stderr]` fetches the pointer stored in that variable.
;;;
;;;   A NOTE ON THIS PROGRAM'S OWN EXIT STATUS: on the success path `main` never
;;;   sets rax before `ret`, so the shell receives whatever `bin` happened to
;;;   leave behind rather than 0. Compare with code-0000..0003, which all end
;;;   with an explicit `mov rax, 0`. Run `./asm "..." 2 ; echo $?` and see.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0004.asm" 3
;;;   ./asm "lectures code /code-0004.asm" 4
;;;   ./asm "lectures code /code-0004.asm" 0      # one empty line: the base case
;;;   ./asm "lectures code /code-0004.asm"        # no argument -> usage error
;;;   ./asm "lectures code /code-0004.asm" -1     # negative      -> usage error
;;;   ./asm "lectures code /code-0004.asm" 200    # too big       -> usage error
;;;
;;;   Careful: the work doubles with every bit. 20 is already a million lines.
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0004.asm" 3
;;;
;;;   Useful session:
;;;     break bin              stop on every entry to the recursive function
;;;     c                      continue to the first one
;;;     bt                     THE point of this example -- see below
;;;     p (long)i              how deep into the buffer we are
;;;     x/s &buffer            the partial string built so far
;;;     finish                 run this whole recursive call to completion
;;;     delete 1               drop the breakpoint when it gets tiresome
;;;     tbreak bin             a ONE-SHOT breakpoint instead
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   This is the file to study the stack in. Run it with 3, break on `bin`,
;;;   and hit `c` a few times, typing `bt` after each. You will watch the stack
;;;   grow:
;;;       #0  bin () at code-0004.asm:NN
;;;       #1  0x... in bin () at code-0004.asm:NN     <-- bin called by bin
;;;       #2  0x... in bin () at code-0004.asm:NN
;;;       #3  0x... in main () at code-0004.asm:NN
;;;   Each level is one more character decided. The stack depth IS the value of
;;;   `i`; check that with `p (long)i` and compare.
;;;
;;;   Now the crucial observation. Nothing in this program stores the partial
;;;   answer per level -- `buffer` and `i` are single shared globals. What the
;;;   stack holds is the RETURN ADDRESSES: each frame remembers "when the callee
;;;   finishes, resume me at the line after MY call". That is what makes the
;;;   second `call bin` (the '1' branch) happen at every level automatically.
;;;   Try:
;;;       x/4gx $rsp        the return addresses stacked up, one per level
;;;       info frame        this frame's return address, spelled out
;;;       frame 2           move the "you are here" cursor up two levels
;;;       info line         see exactly which source line frame 2 will resume at
;;;       frame 0           come back down
;;;   Notice that frame 1 and frame 2 will show DIFFERENT resume lines -- one is
;;;   mid-way through the '0' branch, the other through the '1' branch. That is
;;;   the entire bookkeeping of the search, and it costs you no data structure:
;;;   the call stack is the data structure.
;;;
;;;   Second experiment: `finish` from a deep frame and immediately `p (long)i`.
;;;   You will see i one lower than before. That is the `dec qword [i]` in the
;;;   epilogue -- the "undo" half of backtracking -- and it is the reason the
;;;   caller can reuse position i for the '1' digit.
;;;
;;;   Third: notice `bin` has NO `push rbp` / `mov rbp, rsp` prologue. It is a
;;;   leaf-ish helper that keeps all its state in globals, so it needs no frame
;;;   of its own -- only the 8 bytes of return address that `call` pushes. That
;;;   is why `bt` still works: gdb reads the debug info, not rbp. Compare with
;;;   `main` above, which does build a frame.
;;; ============================================================================

%define MAX_BITS 128                        ; one-line macro. `%define` is a pure TEXT
                                            ;   substitution done by NASM's preprocessor before
                                            ;   assembly: every later MAX_BITS becomes 128.
                                            ;   It generates no code and occupies no memory.

section .data                               ; initialised, writable data
i:                                          ; the index into the string
        dq 0                                ; `dq` emits 8 initialised bytes. This is both the
                                            ;   position of the next character to decide AND
                                            ;   the current recursion depth.
fmt_binary_pattern:
        db `%s\n\0`                         ; printf format: one string, then a newline
fmt_error_incorrect_usage:
        db `Usage: code-0004 <n>, where n in [0, ... , %ld]\n\0`
                                            ; the message shown on bad input; %ld will receive
                                            ;   the upper bound.

section .bss                                ; zero-filled at load time, no space in the file
n:
        resq 1                              ; the total number of bits -- one quadword
buffer:                                     ; the one string we need
        resb MAX_BITS + 1                   ; `resb k` reserves k BYTES. One byte per digit
                                            ;   character, plus one for the '\0' terminator.
                                            ;   A single shared buffer is enough because the
                                            ;   recursion overwrites it in place.

extern atoi, printf, fprintf, stderr, exit
                                            ; all from the C library. Note `stderr` is not a
                                            ;   function but a global VARIABLE of type FILE*.
global main                                 ; export main for the C library start-up

section .text
;;; ----------------------------------------------------------------------------
;;; main -- validate the command line, prepare the buffer, start the recursion.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : falls out of `bin` without setting rax (see the note above)
;;;   How it works: demands exactly one argument, converts it with atoi, rejects
;;;                 anything outside [0, MAX_BITS), plants the NUL terminator at
;;;                 buffer[n], and calls `bin` once. All error paths jump to
;;;                 .error_incorrect_usage, which never returns.
;;; ----------------------------------------------------------------------------
main:
        push rbp                            ; prologue 1/2: save the caller's frame pointer
        mov rbp, rsp                        ; prologue 2/2: anchor this frame
        and rsp, -16                        ; round rsp down to a multiple of 16 (clear the low
                                            ;   4 bits) -- the alignment every `call` requires

        cmp rdi, 2                          ; |argc| == 2: exec name + argument. `cmp`
                                            ;   subtracts and keeps only the flags.
        jne .error_incorrect_usage          ; `jne` = jump if not equal. Wrong number of
                                            ;   arguments -> print to stderr and exit!

        mov rdi, qword [rsi + 8*1]          ; the argv[1] string. rsi still holds argv, and
                                            ;   8*1 selects element 1; the CPU does base +
                                            ;   scale*index inside the addressing mode.
        call atoi                           ; RAX <--- atoi(argv[i]).  int atoi(const char*)
                                            ;   -- one pointer in rdi, an int back in rax.
        mov qword [n], rax                  ; the number of bits, saved to memory where no
                                            ;   later call can clobber it
        cmp rax, 0                          ; if negative
        jl .error_incorrect_usage           ; `jl` = jump if less (SIGNED). ...complain and
                                            ;   exit! Using the signed form matters: atoi can
                                            ;   return a negative number.
        cmp rax, MAX_BITS                   ; if n > MAX_BITS (too big!) -- MAX_BITS was
                                            ;   textually replaced by 128 before assembly
        jge .error_incorrect_usage          ; `jge` = jump if greater or equal (signed).
                                            ;   ...complain and exit! Rejecting n == MAX_BITS
                                            ;   too leaves room for the terminator byte.

        mov rdi, buffer                     ; load the buffer -- a bare label is its ADDRESS
        mov rax, qword [n]                  ; load n
        mov byte [rdi + 1*rax], 0           ; buffer[n] is the sentinel! '\0'
                                            ;   `byte` makes this a 1-byte store; scale 1
                                            ;   because characters are one byte each. Written
                                            ;   ONCE, here, and never disturbed again -- so the
                                            ;   buffer is a valid C string at every moment.

        call bin                            ; print all binary combinations. This one call
                                            ;   unfolds into the entire 2^n-leaf search tree.

        mov rsp, rbp                        ; epilogue 1/2: restore rsp from the anchor
        pop rbp                             ; epilogue 2/2: restore the caller's rbp
        ret                                 ; return to the C library (with rax NOT reset -- see
                                            ;   the note in the header)

;;; ----------------------------------------------------------------------------
;;; main.error_incorrect_usage -- the bad-input exit path. NEVER RETURNS.
;;;   Receives    : nothing
;;;   Returns     : it doesn't; `exit` terminates the process
;;;   How it works: fprintf(stderr, fmt, MAX_BITS - 1), then exit(-1).
;;;                 Diagnostics belong on stderr so that piping the program's
;;;                 real output somewhere does not swallow the error message.
;;; ----------------------------------------------------------------------------
.error_incorrect_usage:
        mov rdi, qword [stderr]             ; load the address of FILE *stderr structure.
                                            ;   TWO levels: `stderr` is a variable, and the
                                            ;   brackets fetch the FILE* stored inside it.
                                            ;   Writing `mov rdi, stderr` would pass the
                                            ;   address OF THE VARIABLE and is a classic bug.
        mov rsi, fmt_error_incorrect_usage  ; then the format string (argument 2 --
                                            ;   with fprintf the stream takes slot 1, so
                                            ;   everything shifts one register right)
        mov rdx, MAX_BITS - 1               ; then limit. NASM evaluates 128-1 at
                                            ;   assembly time; no arithmetic happens at run time.
        mov rax, 0                          ; 0 floating-point registers -- required for every
                                            ;   variadic call
        call fprintf                        ; fprintf when using a FILE * like stderr!
        mov rax, -1                         ; return to shell with a non-zero value...
        call exit                           ; ...indicating an error.
                                            ;   BUT NOTE: exit's argument goes in rdi, not rax.
                                            ;   As written, exit receives whatever fprintf left
                                            ;   in rdi. The intent is clear; the mechanism to
                                            ;   check in gdb is `p $rdi` just before this call.
                                            ;   `exit` never returns, so no epilogue follows.

;;; ----------------------------------------------------------------------------
;;; bin -- recursively enumerate every binary string of length n.
;;;   C equivalent:
;;;       void bin(void) {
;;;           if (i == n) { printf("%s\n", buffer); i--; return; }
;;;           buffer[i++] = '0';  bin();
;;;           buffer[i++] = '1';  bin();
;;;           i--;
;;;       }
;;;   Receives    : nothing in registers -- it reads the globals `i` and `n`
;;;   Clobbers    : rax, and the globals `i` and `buffer`
;;;   Returns     : nothing, but with `i` DECREMENTED BY ONE relative to entry
;;;   How it works: at depth i it owns exactly buffer[i]. It writes '0' there,
;;;                 lets the recursion fill positions i+1..n-1 in every possible
;;;                 way, then writes '1' and repeats. The base case i == n means
;;;                 all positions are decided, so it prints.
;;;
;;;                 THE INVARIANT that makes it work: every call returns with i
;;;                 one SMALLER than it was on entry. So after `call bin`, i is
;;;                 back at this level's own position and the reload/rewrite for
;;;                 the '1' branch is correct. Both the base case and the general
;;;                 case end with a `dec qword [i]` to maintain this.
;;;
;;;                 No `push rbp` prologue: all state is global, so the only
;;;                 stack usage is the 8-byte return address `call` pushes.
;;; ----------------------------------------------------------------------------
bin:
        mov rax, qword [i]                  ; load i -- the position this call is responsible
                                            ;   for, and equally the current recursion depth
        cmp rax, qword [n]                  ; if i == n
        je .print_line                      ; ...we print the line and backtrack. This is the
                                            ;   BASE CASE: every character has been decided.

        mov byte [buffer + 1*rax], '0'      ; set the i-th char to be '0'. A character
                                            ;   literal in single quotes is just its ASCII code
                                            ;   (48 here); `byte` makes it a 1-byte store.
        inc qword [i]                       ; point to the next char -- hand position
                                            ;   i+1 to the callee
        call bin                            ; recurse! Pushes a return address pointing
                                            ;   at the very next line, which is how we come
                                            ;   back to try '1'.
        mov rax, qword [i]                  ; reload i -- it is back at OUR position
                                            ;   thanks to the callee's closing `dec`
        mov byte [buffer + 1*rax], '1'      ; set the i-th char to be '1' -- the second
                                            ;   half of this level's choice
        inc qword [i]                       ; point to the next char
        call bin                            ; recurse!
        dec qword [i]                       ; decrement i for backtracking! This is what
                                            ;   maintains the invariant for OUR caller.
        ret                                 ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; bin.print_line -- the base case: emit the completed pattern and back out.
;;;   Reached when i == n, i.e. buffer[0..n-1] are all decided.
;;; ----------------------------------------------------------------------------
.print_line:
        mov rdi, fmt_binary_pattern         ; load the format for printing a string
        mov rsi, buffer                     ; load the address of the string. It is already
                                            ;   NUL-terminated -- main planted the sentinel at
                                            ;   buffer[n] before any of this started.
        mov rax, 0                          ; 0 floating-point registers used
        call printf
        dec qword [i]                       ; decrement i for backtracking! -- the same
                                            ;   invariant the general case maintains
        ret                                 ; return to whichever `call bin` got us here

section .note.GNU-stack noalloc noexec      ; required Linux marker: stack is not exec
