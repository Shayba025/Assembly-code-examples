;;; ============================================================================
;;; code-0022.asm -- A file-copying program using sys_read and sys_write
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   `cp`, in about a hundred instructions and with no C library involved in
;;;   the copying at all. It opens the source, opens (or creates) the
;;;   destination, and shuttles 1024-byte blocks between them until the source
;;;   runs out. printf is used only to report; the actual work is four system
;;;   calls: open, read, write, close.
;;;
;;;   THE FOUR SYSTEM CALLS, with their numbers and their C prototypes:
;;;       rax=2  open   int   open(const char *path, int flags, mode_t mode);
;;;       rax=0  read   ssize_t read(int fd, void *buf, size_t count);
;;;       rax=1  write  ssize_t write(int fd, const void *buf, size_t count);
;;;       rax=3  close  int   close(int fd);
;;;   Arguments go in rdi, rsi, rdx (then r10, r8, r9 -- NOT rcx, which `syscall`
;;;   destroys). The result comes back in rax, and A NEGATIVE rax MEANS AN ERROR:
;;;   the kernel returns -errno rather than setting a global. That is why every
;;;   syscall here is followed by `cmp rax, 0` / `jl <some error label>`.
;;;
;;;   THE MAGIC NUMBERS, decoded:
;;;       0      = O_RDONLY -- open for reading
;;;       0x241  = O_WRONLY | O_CREAT | O_TRUNC
;;;                (0x001 | 0x040 | 0x200) -- write, create if absent, and empty
;;;                it if present. This is exactly what `>` does in the shell.
;;;       0o644  = rw-r--r-- : owner may read and write, everyone else may read.
;;;                NASM's `0o` prefix is octal, and file permissions are
;;;                traditionally written in octal because each digit is exactly
;;;                one three-bit rwx group.
;;;   The mode argument is IGNORED unless O_CREAT is set, which is why the first
;;;   open passes 0 for it.
;;;
;;;   THE BUFFERING PATTERN -- read a block, write a block -- is the reason this
;;;   is fast. One syscall per 1024 bytes rather than one per byte. Change
;;;   `SIZE equ 1024` to 1 and time it on a large file to feel the difference.
;;;
;;;   HOW IT KNOWS IT IS FINISHED: `read` returns the number of bytes actually
;;;   read, which is less than SIZE only at the very end of the file (or 0 at
;;;   EOF). So `cmp rax, SIZE / jl .last` handles the final short block, writes
;;;   exactly that many bytes, and stops. Note the subtlety: if the file's size
;;;   is an exact multiple of SIZE, the loop performs one extra read that returns
;;;   0, falls into .last, and writes zero bytes. Correct, if slightly indirect.
;;;
;;;   A BUG WORTH SPOTTING: rbx is used to shuffle the two filenames and is
;;;   never saved, though it is CALLEE-SAVED. Also, if an error occurs after the
;;;   files are open, the program exits without closing them -- harmless here
;;;   because process exit closes everything, sloppy in anything longer-lived.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   IMPORTANT: the container can only see the folder the .asm file lives in,
;;;   so use filenames RELATIVE TO "lectures code ", not absolute paths.
;;;
;;;   printf 'hello world\nsecond line\n' > "lectures code /sample.txt"
;;;   ./asm "lectures code /code-0022.asm" sample.txt copy.txt
;;;   cat "lectures code /copy.txt"
;;;   cmp "lectures code /sample.txt" "lectures code /copy.txt" && echo IDENTICAL
;;;
;;;   Try the error paths:
;;;   ./asm "lectures code /code-0022.asm"                      # usage
;;;   ./asm "lectures code /code-0022.asm" nosuchfile out.txt   # cannot open
;;;
;;;   Copy something bigger than one block and check the byte count:
;;;   ./asm "lectures code /code-0022.asm" index.pdf copy.pdf
;;;   ls -l "lectures code /index.pdf" "lectures code /copy.pdf"
;;;
;;;   Then clean up:  rm -f "lectures code /"{sample,copy}.txt "lectures code /copy.pdf"
;;;
;;; DEBUG IT
;;;   printf 'hello\n' > "lectures code /sample.txt"
;;;   ./debug "lectures code /code-0022.asm" sample.txt copy.txt
;;;
;;;   Useful session:
;;;     break code-0022.asm:NN     put NN on the first `syscall` (the open)
;;;     c
;;;     info registers rax rdi rsi rdx
;;;                                2, &path, O_RDONLY, 0
;;;     x/s $rdi                   the filename being opened
;;;     si                         execute the syscall
;;;     p $rax                     the file descriptor -- 3, if it worked, or a
;;;                                small negative number (-errno) if it did not
;;;
;;;   Watch a block move:
;;;     break code-0022.asm:NN     NN on the `syscall` inside .loop (the read)
;;;     c
;;;     si
;;;     p $rax                     bytes actually read
;;;     x/s &buffer                what landed in the buffer
;;;     x/16xb &buffer             the same bytes, raw
;;;
;;;   And see -errno for yourself:
;;;     ./debug "lectures code /code-0022.asm" nosuchfile out.txt
;;;     break code-0022.asm:NN     NN on the first syscall
;;;     c
;;;     si
;;;     p $rax                     -2, which is -ENOENT: "no such file"
;;;     p (int)-$rax               2
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   FIRST, THE THING THAT IS NOT THERE. Break on any `syscall` in this file,
;;;   note `p $rsp` and `bt`, step over it with `si`, and check both again.
;;;   Unchanged. A system call does not touch your stack: control leaves for the
;;;   kernel, which has its own stack in its own address space that `bt` cannot
;;;   walk. The return address is kept in rcx and the flags in r11 -- print them
;;;   after any `syscall` here and you are looking at the return mechanism
;;;   directly. This is why rcx is never used to pass a syscall argument.
;;;
;;;   SECOND, THE FRAME AS A NAMED RECORD. Five locals, and the diagram in the
;;;   prologue names all of them. Dump the whole thing at once and read it:
;;;       x/5gx $rbp-40
;;;   That is file_in, file_out, fd_in, fd_out and the byte total, in ascending
;;;   address order -- the diagram upside down, because the diagram lists them
;;;   going DOWN in memory. Two of the five hold POINTERS into argv, two hold
;;;   small integers from the kernel, one is an accumulator. Confirm it:
;;;       x/s *(char**)($rbp-8)      the source filename
;;;       x/s *(char**)($rbp-16)     the destination filename
;;;       x/1gd $rbp-24              fd_in  -- probably 3
;;;       x/1gd $rbp-32              fd_out -- probably 4
;;;       x/1gd $rbp-40              bytes copied so far
;;;   Being able to look at a raw frame dump and say which word is which is the
;;;   whole skill this course is teaching.
;;;
;;;   THIRD, THE ERROR-HANDLING SHAPE, which is worth copying. Five different
;;;   failures each load a different message into rsi and jump to ONE shared
;;;   `.print_and_exit` tail:
;;;       .usage:                 mov rsi, fmt_usage ; jmp .print_and_exit
;;;       .cannot_open_for_read:  mov rsi, ...       ; jmp .print_and_exit
;;;       ...
;;;       .cannot_write:          mov rsi, ...       ; (falls through)
;;;       .print_and_exit:        mov rdi, [stderr] ; call fprintf ; exit
;;;   One exit, five entries -- exactly the pattern code-0005 used for its
;;;   answers, and the same reason: the common part is written once. Notice the
;;;   last one has no `jmp`, because `.print_and_exit` is the next line and
;;;   control simply falls into it.
;;;
;;;   And notice that `.print_and_exit` never returns, so it needs no epilogue.
;;;   Its frame is simply abandoned when `exit` tears the process down. A
;;;   function that does not return does not have to leave the stack tidy.
;;; ============================================================================

        SIZE equ 1024                       ; `equ` = an assemble-time constant: the
                                            ;   size of one transfer block. Bigger =
                                            ;   fewer system calls = faster.

section .data                               ; initialised, writable data
fmt_cp_report:
        db `Copying \"%s\" to \"%s\"...\n\0`
                                            ; \" is an escaped quote, so the filenames
                                            ;   print inside real quote marks
fmt_bytes:
        db `Copied %llu bytes\n\0`          ; %llu = unsigned 64-bit decimal
fmt_usage:
        db `Usage: program source-file destination-file\n\0`
fmt_cannot_open_for_read:
        db `Cannot open file for reading\n\0`
fmt_cannot_open_for_write:
        db `Cannot open file for writing\n\0`
fmt_cannot_read:
        db `Cannot read from the input file\n\0`
fmt_cannot_write:
        db `Cannot write to the output file\n\0`

section .bss                                ; zero-filled at load time, no file space
buffer:
        resb SIZE                           ; `resb k` reserves k BYTES. The transfer
                                            ;   buffer -- the only memory the copy
                                            ;   itself needs.

extern printf, fprintf, stderr, exit        ; the C library, used ONLY for reporting
global main                                 ; export main for the C library start-up
section .text
;;; ----------------------------------------------------------------------------
;;; main -- copy argv[1] to argv[2], block by block.
;;;   C signature : int main(int argc, char *argv[])
;;;   Receives    : rdi = argc, rsi = argv
;;;   Returns     : rax = 0, or exits with -1 on any failure
;;;   Locals      : [rbp-8*1] file_in   (char*, the source name)
;;;                 [rbp-8*2] file_out  (char*, the destination name)
;;;                 [rbp-8*3] fd_in     (the source's file descriptor)
;;;                 [rbp-8*4] fd_out    (the destination's file descriptor)
;;;                 [rbp-8*5] total     (bytes copied so far)
;;;   How it works: open both files, then loop { read a block; write it } until
;;;                 a read comes back short, which means end of file. Every
;;;                 system call is checked for a negative result, and each
;;;                 distinct failure jumps to a shared reporting tail.
;;; ----------------------------------------------------------------------------
main:
        push rbp                            ; save the old frame-pointer (callee-saved)
        mov rbp, rsp                        ; anchor this frame
        sub rsp, 8*5                        ; reserve five local variables (40 bytes)
        and rsp, -16                        ; align for printf, AFTER the sub

;;; The activation frame:
;;; |         | ret addr    | qword [rbp + 8*1] |
;;; | rbp --> | old rbp     | qword [rbp]       |
;;; |         | file_in     | qword [rbp - 8*1] |
;;; |         | file_out    | qword [rbp - 8*2] |
;;; |         | fd_in       | qword [rbp - 8*3] |
;;; |         | fd_out      | qword [rbp - 8*4] |
;;; |         | total bytes | qword [rbp - 8*5] |

        cmp qword rdi, 3                    ; argc == 3: program + 2 filenames
        jne .usage

        mov rbx, qword [rsi + 8*1]          ; argv[1] -- base + 8*index into argv.
                                            ;   (rbx is callee-saved and unsaved: bug.)
        mov qword [rbp - 8*1], rbx          ; file_in
        mov rbx, qword [rsi + 8*2]          ; argv[2]
        mov qword [rbp - 8*2], rbx          ; file_out
                                            ;   Copied into the frame at once, because
                                            ;   rsi is caller-saved and printf is about
                                            ;   to be called.

        mov rdi, fmt_cp_report              ; printf argument 1: the format string
        mov rsi, qword [rbp - 8*1]          ; argument 2: the source name
        mov rdx, qword [rbp - 8*2]          ; argument 3: the destination name
        mov rax, 0                          ; 0 floating-point registers in use
        call printf

        mov rax, 2                          ; sys_open
        mov rdi, qword [rbp - 8*1]          ; file_in
                                            ;   argument 1: the path
        mov rsi, 0                          ; O_RDONLY
                                            ;   argument 2: the flags. 0 = read only.
        mov rdx, 0                          ; mode is irrelevant for read
                                            ;   argument 3: only consulted when the
                                            ;   file is being CREATED.
        syscall                             ; trap into the kernel. Destroys rcx and
                                            ;   r11; the file descriptor -- or -errno --
                                            ;   comes back in rax.

        cmp rax, 0                          ; did it fail?
        jl .cannot_open_for_read            ; a NEGATIVE result is -errno. The kernel
                                            ;   has no `errno` global; the sign of the
                                            ;   return value carries the error.

        mov qword [rbp - 8*3], rax          ; fd_in

        mov rax, 2                          ; sys_open
        mov rdi, qword [rbp - 8*2]          ; file_out
        mov rsi, 0x241                      ; O_WRONLY | O_CREAT | O_TRUNC
                                            ;   0x001 | 0x040 | 0x200. Write; create it
                                            ;   if it does not exist; empty it if it
                                            ;   does. Exactly the shell's `>`.
        mov rdx, 0o644                      ; user: read/write, else: read
                                            ;   NASM's `0o` prefix is octal, which is how
                                            ;   permissions are always written: one
                                            ;   digit per rwx group. Used only because
                                            ;   O_CREAT is set.
        syscall

        cmp rax, 0                          ; did it fail?
        jl .cannot_open_for_write

        mov qword [rbp - 8*4], rax          ; fd_out

        mov qword [rbp - 8*5], 0            ; total # of character

.loop:                                      ; copy one full block per iteration
        mov rax, 0                          ; sys_read
        mov rdi, qword [rbp - 8*3]          ; argument 1: fd_in
        mov rsi, buffer                     ; argument 2: where to put the bytes
        mov rdx, SIZE                       ; argument 3: how many to ask for
        syscall                             ; rax = how many were ACTUALLY read

        cmp rax, 0                          ; negative?
        jl .cannot_read                     ; a real I/O error
        cmp rax, SIZE                       ; a short read?
        jl .last                            ; fewer bytes than asked for means the file
                                            ;   is exhausted: handle the tail and stop.
                                            ;   (A read of exactly 0 also lands here.)

        mov rax, 1                          ; sys_write
        mov rdi, qword [rbp - 8*4]          ; argument 1: fd_out
        mov rsi, buffer                     ; argument 2: the bytes to write
        mov rdx, SIZE                       ; argument 3: a full block
        syscall

        cmp rax, 0                          ; negative?
        jl .cannot_write

        add qword [rbp - 8*5], SIZE         ; running total
        jmp .loop                           ; next block

.last:                                      ; the final, short block
        mov rdx, rax                        ; argument 3: however many bytes the last
                                            ;   read produced -- NOT SIZE
        mov r9, rax                         ; keep a copy: rax is about to become the
                                            ;   syscall number, and we still need the
                                            ;   count for the running total
        mov rax, 1                          ; sys_write
        mov rdi, qword [rbp - 8*4]          ; argument 1: fd_out
        mov rsi, buffer                     ; argument 2: the buffer
        syscall                             ; rdx was set first, above

        cmp rax, 0                          ; negative?
        jl .cannot_write

        add qword [rbp - 8*5], r9           ; add the last partial block to the total

        mov rax, 3                          ; sys_close
        mov rdi, [rbp - 8*3]                ; fd_in
        syscall                             ; releasing a descriptor is a kindness to
                                            ;   the kernel, and mandatory in any program
                                            ;   that opens files in a loop

        mov rax, 3                          ; sys_close
        mov rdi, [rbp - 8*4]                ; fd_out
        syscall

        mov rdi, fmt_bytes                  ; printf argument 1
        mov rsi, qword [rbp - 8*5]          ; argument 2: the byte total
        mov rax, 0                          ; 0 floating-point registers in use
        call printf

        mov rax, 0                          ; status OK for the OS

        mov rsp, rbp                        ; restore rsp -- frees all five locals
        pop rbp                             ; restore the caller's frame-pointer
        ret                                 ; pop the return address into rip

;;; ----------------------------------------------------------------------------
;;; The error paths. FIVE ENTRY POINTS, ONE EXIT.
;;;   Each label loads its own message into rsi and jumps to the shared tail;
;;;   the last one simply falls through into it. `.print_and_exit` writes to
;;;   stderr and terminates the process, so none of these ever returns and none
;;;   of them needs an epilogue.
;;;   This is the same many-in/one-out shape as code-0005's answer labels, and
;;;   it is the standard way to write error handling in assembly.
;;; ----------------------------------------------------------------------------
.usage:
        mov rsi, fmt_usage                  ; wrong number of command-line arguments
        jmp .print_and_exit
.cannot_open_for_read:
        mov rsi, fmt_cannot_open_for_read   ; the source does not exist, or is unreadable
        jmp .print_and_exit
.cannot_open_for_write:
        mov rsi, fmt_cannot_open_for_write  ; the destination could not be created
        jmp .print_and_exit
.cannot_read:
        mov rsi, fmt_cannot_read            ; an I/O error part-way through
        jmp .print_and_exit
.cannot_write:
        mov rsi, fmt_cannot_write           ; disk full, or a broken pipe.
                                            ;   NO `jmp` here: .print_and_exit is the
                                            ;   next line, so control falls through.
.print_and_exit:
        mov rdi, qword [stderr]             ; FILE *stderr -- brackets, because `stderr`
                                            ;   is a VARIABLE holding a FILE*
        mov rax, 0                          ; 0 floating-point registers in use
        call fprintf                        ; fprintf(stderr, <whichever message>)

        mov rax, -1                         ; non-zero status for the shell
        call exit                           ; terminate. Never returns, so the frame is
                                            ;   simply abandoned -- no epilogue needed.

section .note.GNU-stack noalloc noexec      ; required Linux marker: stack is not exec
