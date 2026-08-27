;;; ============================================================================
;;; asm_demo.asm -- stdin, stdout and stderr through raw system calls
;;; Practice session 5                       (study annotations added)
;;;
;;; WHAT THIS FILE IS
;;;   One function, `void asm_demo(void)`, and NO `main`. A C driver,
;;;   `asm_demo_test.c`, sits next to it; the ./asm and ./debug scripts link any
;;;   <name>_test.c automatically.
;;;   (Verified: writes a line to stdout, a line to stderr, then echoes back
;;;   whatever you type -- with no C library involved in any of it.)
;;;
;;;   WHAT IT DEMONSTRATES: the three standard file descriptors, and the fact
;;;   that they are just small integers.
;;;       0 = stdin      1 = stdout      2 = stderr
;;;   Every process starts with those three already open. `printf` writes to 1,
;;;   `fprintf(stderr, ...)` writes to 2, `scanf` reads from 0 -- and underneath,
;;;   all of them end up doing exactly what this file does directly.
;;;
;;;   THE TWO SYSTEM CALLS:
;;;       rax=1  write   ssize_t write(int fd, const void *buf, size_t count);
;;;       rax=0  read    ssize_t read (int fd, void *buf, size_t count);
;;;   Arguments go in rdi, rsi, rdx (a syscall's fourth argument would go in r10,
;;;   not rcx -- `syscall` destroys rcx and r11 as part of executing). The result
;;;   comes back in rax: the NUMBER OF BYTES actually transferred, or a negative
;;;   errno on failure.
;;;
;;;   THE NICEST LINE IN THE FILE is the one that connects the read to the write:
;;;       mov rdx, rax        ; print exactly what was read
;;;   `read` returned a byte count in rax, and that same count becomes `write`'s
;;;   third argument. So the echo prints exactly what arrived -- not the whole
;;;   50-byte buffer, and not up to some terminator. THIS IS THE COUNTED-BUFFER
;;;   MODEL, and it is fundamentally different from C strings: no '\0' is
;;;   involved anywhere, the data may contain zero bytes, and nothing scans for
;;;   an end. Compare code-0008.asm in "lectures code ", which makes the same
;;;   point with `equ $ - message`.
;;;
;;;   NOTE THE ORDER IN THE ECHO BLOCK. rax is set LAST:
;;;       mov rdi, 1 ; mov rsi, buffer ; mov rdx, rax ; mov rax, 1 ; syscall
;;;   It has to be. rax is simultaneously the read's RESULT and the write's CALL
;;;   NUMBER, so the result must be consumed (into rdx) before rax is overwritten
;;;   with 1. Getting this backwards is a real and easy mistake.
;;;
;;;   `msg_out_len equ $ - msg_out` measures the string at ASSEMBLY TIME. `$` is
;;;   "the address of this point", so the expression is the number of bytes
;;;   emitted since the label. Edit the text and the length corrects itself. This
;;;   is the same trick as code-0008.asm and code-0026.asm.
;;;
;;;   TWO BUGS WORTH SPOTTING:
;;;     * The return value of `read` is never checked for being negative. At
;;;       end-of-file it returns 0 (so the echo writes nothing -- harmless), but
;;;       a real error returns -errno, and passing a negative count to `write`
;;;       would be nonsense.
;;;     * The function's prologue is `push rbp / mov rbp, rsp` but its epilogue
;;;       is `leave` -- which is `mov rsp, rbp` + `pop rbp`. Those DO match, so
;;;       it is correct; it is only the asymmetric spelling that looks odd.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   echo hello | ./asm "ps_code/5/asm_demo.asm"
;;;   ./asm "ps_code/5/asm_demo.asm"           # then type something and press Enter
;;;
;;;   PROVE THE STREAMS ARE SEPARATE -- this is the experiment worth doing:
;;;   echo hi | ./asm "ps_code/5/asm_demo.asm" 2>/dev/null   # stderr thrown away
;;;   echo hi | ./asm "ps_code/5/asm_demo.asm" 1>/dev/null   # stdout thrown away
;;;   echo hi | ./asm "ps_code/5/asm_demo.asm" > out.txt ; cat out.txt
;;;   Only the message written to fd 1 lands in the file; the fd 2 message still
;;;   appears on your terminal. That is why every lecture file sends its usage
;;;   errors to stderr -- so that piping the real output somewhere does not
;;;   swallow them.
;;;
;;;   Feed it more than 50 bytes and watch it truncate:
;;;   python3 -c "print('x'*200)" | ./asm "ps_code/5/asm_demo.asm"
;;;
;;; DEBUG IT
;;;   echo hello | ./debug "ps_code/5/asm_demo.asm"
;;;
;;;   Useful session:
;;;     break asm_demo
;;;     c
;;;     si si                          the prologue
;;;     si si si si                    load rax, rdi, rsi, rdx for the first write
;;;     info registers rax rdi rsi rdx  1, 1, &msg_out, 22
;;;     p msg_out_len                  the assembler-computed length
;;;     x/s $rsi                       the text about to be written
;;;     si                             execute the syscall -- the line appears NOW
;;;     p $rax                         22: the number of bytes actually written
;;;     p/x $rcx                       clobbered by syscall (it holds the return rip)
;;;     p/x $r11                       clobbered too (the saved rflags)
;;;
;;;   Watch the read, which is the interesting one:
;;;     break asm_demo.asm:NN          NN on the `syscall` in the read block
;;;     c
;;;     info registers rax rdi rsi rdx  0, 0, &buffer, 50
;;;     x/50xb &buffer                 all zeros -- .bss starts clean
;;;     si                             the syscall BLOCKS here until input arrives
;;;     p $rax                         how many bytes came in (6 for "hello\n")
;;;     x/s &buffer                    what arrived
;;;     x/6xb &buffer                  ...as raw bytes, including the 0x0a newline
;;;
;;;   And confirm the count is carried across correctly:
;;;     si                             mov rdi, 1
;;;     si                             mov rsi, buffer
;;;     si                             mov rdx, rax    <- the count, saved just in time
;;;     p $rdx                         6
;;;     si                             mov rax, 1      <- rax destroyed, but too late
;;;                                    to matter
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   FIRST, WHAT DOES NOT HAPPEN. Break on any `syscall` in this file, note
;;;   `p $rsp` and `bt`, step over it with `si`, and check both again. Unchanged.
;;;   A system call does not touch your stack: control leaves for the kernel,
;;;   which has its own stack in its own address space that `bt` cannot walk. The
;;;   return address is kept in rcx and the flags in r11 by the hardware, which
;;;   is why rcx is never used to pass a syscall argument.
;;;
;;;   SECOND, WHY `buffer` IS IN .bss AND NOT ON THE STACK. It would be perfectly
;;;   legal to write
;;;       sub rsp, 64 ; mov rsi, rsp ; ... ; syscall
;;;   and read into a stack local instead -- code-0007.asm does exactly that for
;;;   scanf. The difference is lifetime: a .bss buffer persists after the
;;;   function returns, so you can inspect it afterwards in gdb, while a stack
;;;   buffer is released by the epilogue and may be overwritten by the next call.
;;;   Try it in this session:
;;;       finish                     let asm_demo return
;;;       x/s &buffer                still there
;;;   Then imagine the same command on an address below rsp, and you have the
;;;   dangling-pointer bug that code-0007.asm warns about.
;;;
;;;   THIRD -- and this is what the whole file is really for -- notice how much
;;;   OBLIGATION DISAPPEARS when you stop calling the C library. There is no
;;;   `and rsp, -16` here, because 16-byte alignment is a rule about `call`, not
;;;   about existing. There is no `xor eax, eax` variadic dance. There is no
;;;   `extern` and no linking against libc at all for the I/O. Four registers and
;;;   one instruction. Everything else you have been carefully maintaining since
;;;   code-0001.asm is the price of interoperating with C -- worth paying, but
;;;   worth knowing you are paying it.
;;; ============================================================================

section .text                           ; the executable-code section
global asm_demo                         ; export it for the C driver. NOTE: no
                                        ;   `global main` -- this file has no main().

;;; ----------------------------------------------------------------------------
;;; asm_demo -- write to stdout, write to stderr, read stdin, echo it back.
;;;   C signature : void asm_demo(void)
;;;   Receives    : nothing
;;;   Returns     : nothing (rax is left holding the last write's byte count)
;;;   Clobbers    : rax, rdi, rsi, rdx -- and rcx and r11, destroyed by `syscall`
;;;   Stack use   : just the frame it builds; no locals, no alignment needed,
;;;                 because it calls no C function.
;;;   Four system calls, in four blocks. The last two are joined by rax: `read`
;;;   returns a byte count which becomes `write`'s third argument.
;;; ----------------------------------------------------------------------------
asm_demo:
   push rbp                             ; prologue: save the caller's frame pointer
   mov rbp, rsp                         ; anchor the frame. (No `and rsp, -16` -- that
                                        ;   rule applies to `call`, and there is none.)

                                        ;--------------------;
                                        ;  write to stdout (fd=1)
                                        ;-----------------------

    mov rax, 1                          ; sys_write
                                        ;   for a SYSTEM call, rax selects the service.
                                        ;   (For a C call, rax means the float count --
                                        ;   the same register, two unrelated rules.)
    mov rdi, 1                          ; stdout
                                        ;   argument 1: the file descriptor
    mov rsi, msg_out                    ; argument 2: the ADDRESS of the bytes
    mov rdx, msg_out_len                ; argument 3: HOW MANY bytes. A count, not a
                                        ;   terminator -- these are not C strings.
    syscall                             ; trap into the kernel. Destroys rcx (saved rip)
                                        ;   and r11 (saved rflags); returns the number
                                        ;   of bytes written in rax.

                                        ;--------------------;
                                        ;  write to stdout (fd=2)
                                        ;-----------------------

    mov rax, 1                          ; sys_write
    mov rdi, 2                          ; stderr
                                        ;   THE ONLY DIFFERENCE from the block above is
                                        ;   this number. stdout and stderr are two
                                        ;   integers, nothing more -- which is why they
                                        ;   can be redirected independently by the shell.
    mov rsi, msg_err                    ; a different message...
    mov rdx, msg_err_len                ; ...and its own assembler-computed length
    syscall

                                        ;--------------------;
                                        ;  read from stdin  (fd=0)
                                        ;-----------------------

    mov rax, 0                          ; sys_read
    mov rdi, 0                          ; stdin
    mov rsi, buffer                     ; argument 2: WHERE to put the bytes
    mov rdx, 50                         ; argument 3: at most this many. The buffer is
                                        ;   50 bytes, so asking for more would let the
                                        ;   kernel write past the end.
    syscall                             ; rax = number of read bytes
                                        ;   THIS BLOCKS until input arrives. At
                                        ;   end-of-file it returns 0; on error, -errno,
                                        ;   which this code does not check.

                                        ;--------------------;
                                        ;  echo input  to  stdout
                                        ;-----------------------

    mov rdi, 1                          ; stdout
    mov rsi, buffer                     ; the bytes that just arrived
    mov rdx, rax                        ; print exactly what was read
                                        ;   THE KEY LINE: the read's RESULT becomes the
                                        ;   write's COUNT. Not the whole buffer, not up
                                        ;   to a terminator -- exactly what came in.
    mov rax, 1                          ; sys write
                                        ;   set LAST, because rax held the byte count
                                        ;   until the line above consumed it
    syscall

   leave                                ; epilogue: `mov rsp, rbp` + `pop rbp`
   ret                                  ; pop the return address into rip

section .data                           ; initialised, writable data
   msg_out: db "ASM:writing to stdout", 10
                                        ; NO terminating 0 -- sys_write is given a
                                        ;   length, so none is needed. 10 is the newline.
   msg_out_len  equ $ - msg_out         ; `$` is the address of THIS point, so this is
                                        ;   the byte count above. Computed by NASM at
                                        ;   assembly time; edit the text and it follows.
   msg_err : db "ASM:writing to stderr", 10
   msg_err_len  equ $ - msg_err         ; likewise for the second message

  section .bss                          ; zero-filled at load time, no file space
 buffer: resb 50                        ; `resb 50` reserves fifty BYTES. In .bss rather
                                        ;   than on the stack, so it survives after the
                                        ;   function returns -- see the call-stack notes.
