;;; ============================================================================
;;; code-0008.asm -- The sys_write system call: talking to the kernel directly
;;; Programmer: Mayer Goldberg, 2026        (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Prints the same question in English, Hebrew, Arabic and Russian -- WITHOUT
;;;   the C library. No printf, no `extern` anything. It asks the operating
;;;   system to write bytes to a file descriptor, and that is the whole program.
;;;
;;;   FOUR IDEAS, one per bullet in the professor's original header:
;;;
;;;   1. THE `syscall` INSTRUCTION. Everything so far went through the C library.
;;;      Underneath, the C library eventually does this: load a system-call
;;;      NUMBER into rax, load the arguments into registers, and execute
;;;      `syscall`, which traps into the kernel. When the kernel is done it
;;;      returns to the instruction after `syscall` with a result in rax.
;;;
;;;   2. THE SYSCALL ARGUMENT REGISTERS ARE NOT THE C ONES. Close, but not the
;;;      same, and the difference bites people:
;;;          C ABI      : rdi rsi rdx rcx r8  r9
;;;          Linux sysc.: rdi rsi rdx r10 r8  r9      + rax = call number
;;;      rcx and r11 are DESTROYED by `syscall` itself (the CPU stores rip in
;;;      rcx and rflags in r11), which is exactly why argument 4 moved to r10.
;;;      sys_write only needs three, so it does not show here -- but remember it.
;;;
;;;      sys_write is call number 1, and its C prototype is
;;;          ssize_t write(int fd, const void *buf, size_t count);
;;;      so:  rax=1, rdi=fd, rsi=buffer address, rdx=byte count.
;;;      File descriptor 0 is stdin, 1 is stdout, 2 is stderr.
;;;
;;;   3. `$` MEANS "THE ADDRESS OF THIS POINT". The line
;;;          message_length equ $ - message
;;;      is arithmetic done BY THE ASSEMBLER, at assembly time: "current
;;;      position minus where `message` started" = the number of bytes emitted
;;;      in between. Nothing is computed at run time, and you never have to
;;;      count the bytes yourself -- which matters a great deal below.
;;;
;;;   4. THESE ARE NOT C STRINGS. sys_write is given an explicit LENGTH, so no
;;;      terminator is needed and none is present. That is a genuinely different
;;;      model from printf/%s, which scans for a '\0'. A counted buffer can
;;;      contain zero bytes; a C string cannot.
;;;
;;;   AND THE PUNCHLINE ABOUT UNICODE: the four lines are stored as UTF-8, which
;;;   means one "character" may occupy 2, 3 or more bytes. This program does not
;;;   know that and does not care. It hands the kernel a start address and a
;;;   byte count; the terminal does the decoding. Note how `equ $ - message`
;;;   quietly gets the byte count right even though the character count is
;;;   something else entirely -- try counting the letters and comparing.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "lectures code /code-0008.asm"
;;;
;;;   Compare bytes with characters:
;;;   ./asm "lectures code /code-0008.asm" | wc -c   # bytes  -- == message_length
;;;   ./asm "lectures code /code-0008.asm" | wc -m   # chars  -- a smaller number
;;;
;;;   Send it to stderr instead by changing rdi to 2, rebuild, and try
;;;   `./asm ... > /dev/null` -- the text still appears.
;;;
;;; DEBUG IT
;;;   ./debug "lectures code /code-0008.asm"
;;;
;;;   Useful session:
;;;     si si                  through the prologue
;;;     si si si si            load rax, rdi, rsi, rdx
;;;     info registers rax rdi rsi rdx
;;;                            1, 1, &message, message_length -- the whole call
;;;     p message_length       ask gdb for the assembler-computed constant
;;;     x/16xb $rsi            the first 16 raw bytes. The ASCII ones are one
;;;                            byte each; the Hebrew ones start with 0xD7...
;;;     x/s $rsi               gdb stops at the first newline
;;;     si                     execute the `syscall` -- the text appears NOW
;;;     p $rax                 the kernel's answer: bytes actually written
;;;     p $rcx                 clobbered by syscall (it holds the return rip)
;;;     p/x $r11               clobbered too (it holds the saved rflags)
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   `syscall` is NOT a `call`. Break just before it, note `p $rsp` and `bt`,
;;;   step over it with `si`, and check both again: rsp is unchanged and the
;;;   backtrace is unchanged. Nothing was pushed onto your stack, because
;;;   control did not go to another function in your address space -- it went to
;;;   the kernel, which has its OWN stack, in its own address space, that you
;;;   cannot see and `bt` cannot walk.
;;;
;;;   So how does it get back? Not via a stack slot: the CPU stashed the return
;;;   address in rcx and the flags in r11 as part of executing the instruction.
;;;   Print them right after the syscall and you are looking at the return
;;;   mechanism, in registers, exactly as in the BALR discussion in code-0005 --
;;;   only this time it is the hardware doing it rather than your code.
;;;
;;;   The second thing worth noticing is what this file does NOT need. There is
;;;   no `and rsp, -16`, because the 16-byte alignment rule is a C ABI rule for
;;;   `call`, and there is no call here. There is no `extern` and no `rax = 0`
;;;   variadic dance either. Every one of those obligations came from the C
;;;   library, not from the machine. Strip the library away and the raw machine
;;;   is startlingly small: set four registers, execute one instruction.
;;;
;;;   Finally: the prologue and epilogue (`push rbp` ... `pop rbp` ... `ret`) are
;;;   still here, and still necessary, because `main` itself WAS reached by a
;;;   `call` from the C library's start-up code. `x/1gx $rbp+8` shows that return
;;;   address. The program talks to the kernel directly but is still, itself, an
;;;   ordinary C-called function.
;;; ============================================================================

section .data                           ; initialised, writable data
message:                                ; the label marks the FIRST byte; `$ - message`
                                        ;   below will measure everything emitted after it
        db `Isn't assembly-language fun??\n`
                                        ; `db` emits raw bytes. Backquotes make \n a real
                                        ;   newline (byte 10). NOTE: NO \0 -- this is not a
                                        ;   C string. sys_write is told how many bytes to
                                        ;   write, so a terminator would just be printed.
        db `נָכוֹן שֶׁאֶסְמְבֵּלִי זֶה כֵּיף??\n`
                                        ; the same question in Hebrew, stored as UTF-8. Each
                                        ;   Hebrew letter is 2 bytes and each vowel point is
                                        ;   another 2, so this line is far longer in BYTES
                                        ;   than it looks in characters -- and bytes are all
                                        ;   sys_write deals in.
        db `هَلْ أَلَيْسَتِ اللُّغَةُ التَّجْمِيعِيَّةُ مُمْتِعَةً؟؟\n`
                                        ; ... and in Arabic. Also UTF-8, also multi-byte, also
                                        ;   completely invisible to this program.
        db `Разве язык ассемблера не увлекателен?\n`
                                        ; ... and in Russian. Cyrillic is 2 bytes per letter in
                                        ;   UTF-8. The terminal decodes; the program never does.
        message_length equ $ - message
                                        ; `equ` defines an ASSEMBLE-TIME constant. `$` is
                                        ;   "the address of this very point", so this is
                                        ;   (end of the four strings) - (start) = the exact
                                        ;   number of BYTES above. It costs nothing at run
                                        ;   time and cannot drift when you edit the text.
                                        ;   In UTF-8 this is larger than the number of
                                        ;   characters -- which is precisely the count
                                        ;   sys_write wants.

global main                             ; export main for the C library start-up. Note
                                        ;   there is no `extern` line at all: this program
                                        ;   calls no library function.
section .text
;;; ----------------------------------------------------------------------------
;;; main -- write a fixed block of bytes to stdout with one system call.
;;;   C equivalent : write(1, message, message_length);
;;;   Receives     : nothing it uses
;;;   Returns      : rax = 0
;;;   How it works : loads the four sys_write registers and traps to the kernel.
;;;                  No stack alignment and no variadic bookkeeping are needed,
;;;                  because no C function is called.
;;; ----------------------------------------------------------------------------
main:
        push rbp                        ; save the caller's frame pointer (rbp is
                                        ;   callee-saved). Still required: the C library
                                        ;   start-up called US with a `call`.
        mov rbp, rsp                    ; anchor this frame at the current stack top

        mov rax, 1                      ; sys_write. For a system call, rax selects WHICH
                                        ;   kernel service you want; 1 is write on x86-64
                                        ;   Linux. (For a C call, rax means something
                                        ;   completely different -- the float count. Same
                                        ;   register, two unrelated conventions.)
        mov rdi, 1                      ; fd out = 1. Argument 1: the file descriptor.
                                        ;   0 = stdin, 1 = stdout, 2 = stderr.
        mov rsi, message                ; the text to be printed. Argument 2: the ADDRESS
                                        ;   of the first byte (a bare label is its address).
        mov rdx, message_length         ; # of bytes: no need for '\0' at the end!
                                        ;   Argument 3: an exact count, computed by the
                                        ;   assembler with `equ $ - message` above.
        syscall                         ; trap into the kernel. The CPU saves rip into rcx
                                        ;   and rflags into r11 (so BOTH are destroyed),
                                        ;   switches to kernel mode, runs the service, and
                                        ;   returns here with the result in rax -- the
                                        ;   number of bytes written, or a negative errno.

        mov rax, 0                      ; return value: OK. This overwrites whatever
                                        ;   sys_write returned; the program ignores it.

        mov rsp, rbp                    ; restore the stack pointer from the anchor
        pop rbp                         ; restore the caller's frame pointer
        ret                             ; pop the return address into rip, back to the
                                        ;   C library, which then calls exit(0)

section .note.GNU-stack noalloc noexec  ; required Linux marker: stack is not exec
