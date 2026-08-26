;;; ============================================================================
;;; code-0021.asm -- Bubble Sort in x86/64
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Reads the numbers on the command line into a heap-allocated array, prints
;;;   it, bubble-sorts it in place, and prints it again.
;;;
;;;   THREE THINGS MAKE THIS THE MOST "REAL PROGRAM" FILE SO FAR:
;;;
;;;   1. IT CALLS malloc. Every array until now was a fixed-size `resq` in .bss.
;;;      Here the size is not known until run time, so:
;;;          shl rdi, 3        ; n * 8 bytes -- shifting left by 3 multiplies by 8
;;;          call malloc       ; void *malloc(size_t); pointer comes back in rax
;;;      That pointer is the array. Note there is no matching `free` -- the
;;;      program relies on process exit to reclaim it, which is fine for a
;;;      program this short and a habit to break for anything longer.
;;;
;;;   2. IT PASSES ARGUMENTS TO TWO DIFFERENT FUNCTIONS -- AND PUSHES THEM ONCE.
;;;      Look carefully at main:
;;;          push qword [array]
;;;          push qword [size]
;;;          call print_array        <- reads them at [rbp+8*2], [rbp+8*3]
;;;          call bubble_sort        <- reads the SAME two slots
;;;          ...
;;;          call print_array        <- and so does this one
;;;      Two pushes, three calls. Neither callee cleans up (both end in a plain
;;;      `ret`) and main never does `add rsp, 16` either -- the arguments simply
;;;      stay on the stack until `mov rsp, rbp` in the epilogue discards them
;;;      along with everything else. It works, and it is worth understanding
;;;      exactly why: see the call-stack section below. It is also fragile, and
;;;      you should not write it this way.
;;;
;;;   3. TWO-DIMENSIONAL ADDRESSING WITH A DISPLACEMENT:
;;;          mov r8, qword [rdx + 8*rax]          ; Array[i]
;;;          mov r9, qword [rdx + 8*rax + 8]      ; Array[i+1]
;;;      base + scale*index + displacement, all computed inside the addressing
;;;      mode for free. The `+ 8` is how you say "the next element" without a
;;;      second register or an extra add.
;;;
;;;   THE ALGORITHM is bubble sort with two standard refinements: a `changed`
;;;   flag so a sorted array costs one pass rather than n, and a shrinking upper
;;;   bound (`i1`), since after k passes the last k elements are already in
;;;   place. Worst case is still O(n^2) -- do not sort large inputs with it.
;;;
;;;   A BUG WORTH SPOTTING: rbx is used as scratch in both `main` and
;;;   `bubble_sort`, and rbx is CALLEE-SAVED. Neither function pushes it.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0021.asm" 5 3 9 1 7
;;;   ./asm "lectures code /code-0021.asm" 42
;;;   ./asm "lectures code /code-0021.asm" 9 8 7 6 5 4 3 2 1
;;;   ./asm "lectures code /code-0021.asm" 1 2 3 4 5      # already sorted
;;;   ./asm "lectures code /code-0021.asm" -3 10 -7 0
;;;   ./asm "lectures code /code-0021.asm"                # usage error
;;;
;;;   Sort 200 random numbers and check the result really is ordered:
;;;   ./asm "lectures code /code-0021.asm" $(seq 200 | sort -R | tr '\n' ' ') \
;;;       | tail -1 | tr ';' '\n' | grep -o '[0-9-]*$' | sort -c -n && echo SORTED
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0021.asm" 5 3 9 1 7
;;;
;;;   Useful session:
;;;     break malloc
;;;     c
;;;     p $rdi                              bytes requested: n * 8
;;;     finish
;;;     p/x $rax                            the heap pointer
;;;     break bubble_sort
;;;     c
;;;     x/5gd *(long*)($rbp+24)             the whole array, unsorted
;;;     finish
;;;     x/5gd (long*)array                  ...and now sorted
;;;
;;;   Watch a single swap happen:
;;;     break code-0021.asm:NN              NN on the `cmp r8, r9` line
;;;     c
;;;     info registers r8 r9                the pair being compared
;;;     x/1gd $rbp-16                       i2, the position
;;;     c                                   again, and again
;;;
;;;   Watch the early-exit flag do its job -- run with an already-sorted array:
;;;     ./debug "lectures code /code-0021.asm" 1 2 3 4 5
;;;     break code-0021.asm:NN              NN on `cmp qword [rbp - 8*3], 0`
;;;     c
;;;     x/1gd $rbp-24                       0 -- nothing moved, so stop now
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THE THING TO STUDY IN THIS FILE IS THE SHARED ARGUMENT BLOCK. Set a
;;;   breakpoint on `print_array` and on `bubble_sort`, then at each stop print
;;;   the two argument slots:
;;;       x/1gd $rbp+16          size
;;;       p/x *(long*)($rbp+24)  array
;;;   All three calls report the SAME two values, from the SAME two addresses,
;;;   even though main pushed them only once. Now check why nothing disturbs
;;;   them:
;;;       p $rsp                 at each stop -- identical
;;;   Every one of the three calls pushes a return address at the same place,
;;;   uses it, and pops it. The two quadwords sitting just above are never
;;;   touched. So "the arguments" are really a little block of memory in main's
;;;   frame that three callees happen to read.
;;;
;;;   NOW BREAK IT, because that is the instructive part. In gdb, at the moment
;;;   `print_array` returns the first time, do:
;;;       p $rsp
;;;       set $rsp = $rsp + 16     pretend main had cleaned up C-style
;;;       c
;;;   The subsequent `call bubble_sort` now reads whatever happens to be there
;;;   and the program misbehaves. The lesson is that this code depends on an
;;;   UNWRITTEN agreement: nobody cleans up, and main's `mov rsp, rbp` sweeps
;;;   everything at the end. Add one `add rsp, 16` in the wrong place, or make
;;;   one of the callees Pascal-style, and it collapses. That is precisely what
;;;   calling conventions exist to prevent -- and this file quietly has none.
;;;
;;;   THE SECOND THING TO NOTICE. `main`, `bubble_sort` and `print_array` all
;;;   have locals at negative offsets AND arguments at positive offsets, and the
;;;   three diagrams in the source show it. Print a whole frame at once:
;;;       x/8gx $rbp-32
;;;   and match the words against the diagram: three locals, saved rbp, return
;;;   address, size, array. Once you can read a frame dump against a diagram
;;;   without counting on your fingers, you can debug anything in this course.
;;;
;;;   Finally: `print_array` does `sub rsp, 8*2` but uses only one local. The
;;;   extra 8 bytes are harmless -- and a good illustration that the frame size
;;;   is whatever the prologue says, not something the machine verifies.
;;; ============================================================================

section .data                            ; initialised, writable data
fmt_usage:
        db `Usage: program num₁ num₂ ⋯ numₙ, where n ≥ 1\n\0`
                                         ;   the usage message. The subscripts and
                                         ;   the >= sign are UTF-8; printf copies
                                         ;   the bytes through without decoding.
fmt_pre_sort:
        db `Before sorting the array:\n\0`
fmt_post_sort:
        db `After sorting the array:\n\0`
fmt_array_element:
        db `Arr[%lld] == %lld; \0`       ; index and value, no newline -- the whole
                                         ;   array prints on one line
fmt_newline:
        db `\n\0`                        ; used once, to end that line

section .bss                             ; zero-filled at load time, no file space
size:
        resq 1                           ; how many numbers there are
array:
        resq 1                           ; the POINTER malloc returned (not the
                                         ;   array itself -- that lives on the heap)

extern printf, stderr, fprintf, exit, malloc, atoll
                                         ; all from the C library. `malloc` is new:
                                         ;   void *malloc(size_t), size in rdi,
                                         ;   pointer back in rax.
global main                              ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- build the array from argv, print it, sort it, print it again.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 if given no numbers
;;;   Locals      : [rbp-8*1] = source, a walking pointer into argv
;;;                 [rbp-8*2] = dest,   a walking pointer into the new array
;;;                 [rbp-8*3] = index,  how many numbers are left to convert
;;;   How it works: allocates 8*n bytes, then walks argv and the array in step,
;;;                 converting each string with atoll. Afterwards it pushes the
;;;                 (array, size) pair ONCE and lets all three subsequent calls
;;;                 read it -- see the header.
;;; ----------------------------------------------------------------------------
main:
        push rbp                         ; save the old frame-pointer (callee-saved)
        mov rbp, rsp                     ; anchor this frame
        sub rsp, 8*3                     ; reserve three local variables (24 bytes)
        and rsp, -16                     ; align for the library calls, AFTER the
                                         ;   sub so the padding never eats a local

;;; The activation frame:
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | source   | qword [rbp - 8*1] |
;;; |         | dest     | qword [rbp - 8*2] |
;;; |         | index    | qword [rbp - 8*3] |

        cmp rdi, 2                       ; argc >= 2? i.e. at least one number
        jl .usage                        ; `jl` = jump if less (signed)
        add rsi, 8                       ; skip argv[0]: advance the argv pointer by
                                         ;   one element, so it now points at argv[1]
        mov qword [rbp - 8*1], rsi       ; source := &argv[1]
        dec rdi                          ; n = argc - 1: the count of actual numbers
        mov qword [size], rdi            ; publish it as a global, for the callees
        mov qword [rbp - 8*3], rdi       ; index := n, the countdown for the loop
        shl rdi, 3                       ; rdi *= 8
                                         ;   `shl x, k` shifts left k bits, which
                                         ;   multiplies by 2^k. Here 8 bytes per
                                         ;   quadword. One cycle, versus a multiply.
                                         ;   rdi is now malloc's argument.
        call malloc                      ; void *malloc(size_t) -> pointer in rax.
                                         ;   (A robust program would check for NULL.)
        mov qword [array], rax           ; publish the pointer as a global
        mov qword [rbp - 8*2], rax       ; dest := the start of the new array

.loop:                                   ; convert argv[1..n] into array[0..n-1]
        cmp qword [rbp - 8*3], 0         ; any numbers left?
        jz .done
        mov rdi, qword [rbp - 8*1]       ; source -- the address of the argv slot
        mov rdi, qword [rdi]             ; dereference it: the char* it holds.
                                         ;   Two loads, because argv is an array OF
                                         ;   POINTERS.
        call atoll                       ; long long atoll(const char*) -> rax
        mov rbx, qword [rbp - 8*2]       ; dest -- where this number goes.
                                         ;   (rbx is callee-saved and unsaved: bug.)
        mov qword [rbx], rax             ; store the converted value
        dec qword [rbp - 8*3]            ; one fewer to do
        add qword [rbp - 8*1], 8*1       ; advance source by one pointer
        add qword [rbp - 8*2], 8*1       ; advance dest by one quadword
        jmp .loop

.done:
        mov rdi, fmt_pre_sort            ; "Before sorting the array:"
        mov rax, 0                       ; 0 floating-point registers in use
        call printf

        push qword [array]               ; argument 1 for the callees -> [rbp+8*3]
        push qword [size]                ; argument 2 -> [rbp+8*2]
                                         ;   PUSHED ONCE, READ BY THREE CALLS. Nobody
                                         ;   cleans them up until main's epilogue --
                                         ;   see the header and the call-stack notes.
        call print_array                 ; show the unsorted array
        call bubble_sort                 ; sort it in place, reading the SAME two slots

        mov rdi, fmt_post_sort           ; "After sorting the array:"
        mov rax, 0                       ; 0 floating-point registers in use
        call printf

        call print_array                 ; and again -- still the same two slots

        mov rax, 0                       ; status OK for the OS
        mov rsp, rbp                     ; restore rsp: this is what finally discards
                                         ;   the two pushed arguments, the three
                                         ;   locals and the alignment padding
        pop rbp                          ; restore the caller's frame-pointer
        ret                              ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; main.usage -- no numbers on the command line. NEVER RETURNS.
;;; ----------------------------------------------------------------------------
.usage:
        mov rdi, qword [stderr]          ; FILE *stderr -- brackets, because `stderr`
                                         ;   is a VARIABLE holding a FILE*
        mov rsi, fmt_usage               ; the message (fprintf's argument 2)
        mov rax, 0                       ; 0 floating-point registers in use
        and rsp, -16                     ; re-align, in case we jumped here from a
                                         ;   point where rsp had drifted
        call fprintf                     ; diagnostics go to stderr, not stdout

        mov rax, -1                      ; non-zero status for the shell
        call exit                        ; terminate. Never returns.

;;; ----------------------------------------------------------------------------
;;; bubble_sort -- sort the array in place, ascending.
;;;   Pseudo-C   : void bubble_sort(long *a, long n)
;;;   Receives   : [rbp + 8*3] = array pointer, [rbp + 8*2] = size
;;;                (the block main pushed; this function does not clean it up)
;;;   Returns    : nothing -- the array is modified in place
;;;   Clobbers   : rax, rbx (CALLEE-SAVED and unsaved -- see header), rdx, r8, r9
;;;   Locals     : [rbp-8*1] = i1, the shrinking upper bound
;;;                [rbp-8*2] = i2, the position within the current pass
;;;                [rbp-8*3] = changed, the early-exit flag
;;;
;;;   How it works: repeated passes. Each pass walks i2 from 0 to i1, comparing
;;;   neighbours and swapping any that are out of order, and sets `changed` if it
;;;   swapped anything. After a pass, i1 shrinks by one -- the largest remaining
;;;   element has bubbled to the top and never needs looking at again -- and the
;;;   whole thing stops early if a pass made no swaps at all.
;;;
;;;   Note: no `and rsp, -16` in the prologue, because this function calls
;;;   nothing. Alignment is a rule about `call`, not about existing.
;;; ----------------------------------------------------------------------------
bubble_sort:
        push rbp                         ; save the caller's frame-pointer
        mov rbp, rsp                     ; anchor this frame
        sub rsp, 8*3                     ; reserve three local variables

;;; The activation frame:
;;; |         | array    | qword [rbp + 8*3] |
;;; |         | size     | qword [rbp + 8*2] |
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | i1       | qword [rbp - 8*1] |
;;; |         | i2       | qword [rbp - 8*2] |
;;; |         | changed  | qword [rbp - 8*3] |

        mov rax, qword [rbp + 8*2]       ; size, from the shared argument block
        dec rax                          ; the highest valid index
        mov qword [rbp - 8*1], rax       ; max index
.loop1:                                  ; one iteration = one full pass
        cmp qword [rbp - 8*1], 0         ; nothing left to compare?
        jz .done
        mov qword [rbp - 8*2], 0         ; i2 := 0, start of the pass
        mov qword [rbp - 8*3], 0         ; changed := 0, nothing swapped yet
.loop2:                                  ; walk one pass
        mov rax, qword [rbp - 8*2]       ; i2
        mov rbx, qword [rbp - 8*1]       ; i1, the current upper bound
        cmp rbx, 0                       ; degenerate array (size <= 1)?
        jz .done
        cmp rax, rbx                     ; reached the end of this pass?
        je .done2
        mov rdx, qword [rbp + 8*3]       ; the array pointer
        mov r8, qword [rdx + 8*rax]      ; Array[i2]
        mov r9, qword [rdx + 8*rax + 8]  ; Array[i2 + 1]
                                         ;   base + scale*index + DISPLACEMENT. The
                                         ;   `+ 8` reaches the next element without
                                         ;   a second register or an extra add.
        cmp r8, r9                       ; out of order?
        jg .swap                         ; `jg` = signed greater: yes, swap them
        inc qword [rbp - 8*2]            ; ++i2
        jmp .loop2
.swap:
        mov qword [rdx + 8*rax], r9      ; write the smaller one first...
        mov qword [rdx + 8*rax + 8], r8  ; ...and the larger one second. No temporary
                                         ;   is needed: both values are already in
                                         ;   registers.
        mov qword [rbp - 8*3], 1         ; changed := 1, so we must do another pass
        inc qword [rbp - 8*2]            ; ++i2
        jmp .loop2

.done2:                                  ; end of one pass
        cmp qword [rbp - 8*3], 0         ; did this pass change anything?
        jz .done                         ; no -- the array is sorted, stop early
        mov qword [rbp - 8*3], 0         ; reset the flag for the next pass
        dec qword [rbp - 8*1]            ; shrink the bound: the top element is final
        jmp .loop1

.done:
        mov rsp, rbp                     ; restore rsp -- frees the three locals
        pop rbp                          ; restore the caller's frame-pointer
        ret                              ; PLAIN ret: the two arguments stay on the
                                         ;   stack for the next caller to reuse

;;; ----------------------------------------------------------------------------
;;; print_array -- print every element as `Arr[i] == v; ` on one line.
;;;   Pseudo-C   : void print_array(long *a, long n)
;;;   Receives   : [rbp + 8*3] = array pointer, [rbp + 8*2] = size
;;;   Returns    : nothing
;;;   Clobbers   : rax and the printf argument registers
;;;   Locals     : [rbp-8*1] = index (a second slot is reserved and unused)
;;;   How it works: a counted loop with the index kept in the frame, so the
;;;                 printf calls need no register protection -- the same idiom as
;;;                 code-0018. Ends with a single newline.
;;; ----------------------------------------------------------------------------
print_array:
        push rbp                         ; save the caller's frame-pointer
        mov rbp, rsp                     ; anchor this frame
        sub rsp, 8*2                     ; reserve two locals -- though only one is
                                         ;   used. Harmless: the frame is whatever
                                         ;   the prologue says it is.
        and rsp, -16                     ; align the stack for printf

;;; The activation frame:
;;; |         | array    | qword [rbp + 8*3] |
;;; |         | size     | qword [rbp + 8*2] |
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | index    | qword [rbp - 8*1] |

        mov qword [rbp - 8*1], 0         ; index := 0
.loop:
        mov rax, qword [rbp - 8*1]       ; index
        cmp rax, qword [rbp + 8*2]       ; compare against size, from the argument
                                         ;   block main pushed
        je .done
        mov rdi, fmt_array_element       ; printf argument 1: the format string
        mov rsi, rax                     ; argument 2: the index
        mov rdx, qword [rbp + 8*3]       ; the array pointer...
        mov rdx, qword [rdx + 8*rax]     ; ...dereferenced at the index: argument 3.
                                         ;   base + 8*index is the array idiom.
        mov rax, 0                       ; 0 floating-point registers in use
        call printf
        inc qword [rbp - 8*1]            ; ++index, in memory, so printf cannot
                                         ;   disturb it
        jmp .loop

.done:
        mov rdi, fmt_newline             ; end the line
        mov rax, 0                       ; 0 floating-point registers in use
        call printf

        mov rsp, rbp                     ; restore rsp -- frees the locals and the
                                         ;   alignment padding
        pop rbp                          ; restore the caller's frame-pointer
        ret                              ; PLAIN ret: the arguments stay put, ready
                                         ;   for the next call

section .note.GNU-stack noalloc noexec   ; required Linux marker: stack is not exec
