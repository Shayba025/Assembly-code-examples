;;; ============================================================================
;;; logger.asm -- catching Ctrl+C: installing a signal handler by hand
;;; Practice session 7                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Installs a handler for SIGINT and then loops forever. Every time you press
;;;   Ctrl+C it prints "SIGINT received" and carries on instead of dying.
;;;   (Verified: sending SIGINT twice produces the message twice, and the process
;;;   keeps running.)
;;;
;;;   *** IT NEVER EXITS. *** `main` ends in `jmp .loop`, which is deliberate --
;;;   a program that catches SIGINT cannot be stopped by Ctrl+C. Kill it from
;;;   another terminal, or press Ctrl+\ (SIGQUIT), which this program does not
;;;   catch. Under the ./asm script, closing the terminal or `docker kill` also
;;;   works.
;;;
;;;   WHAT A SIGNAL IS. An ASYNCHRONOUS interruption delivered by the kernel.
;;;   Your program is running normally; the kernel suspends it wherever it
;;;   happens to be, runs your handler, and then resumes exactly where it left
;;;   off. Nothing in your code calls the handler -- that is what makes signals
;;;   different from every other function call in this course, and it is what the
;;;   stack notes below are about.
;;;
;;;   INSTALLING ONE MEANS FILLING IN A STRUCT. `rt_sigaction` (system call 13)
;;;   takes a pointer to a `struct sigaction`, which on x86-64 Linux is laid out
;;;   as:
;;;       offset 0    sa_handler    the address of your handler function
;;;       offset 8    sa_flags      bit flags
;;;       offset 16   sa_restorer   the address of the "trampoline" (see below)
;;;       offset 24   sa_mask       128 bytes: which signals to block meanwhile
;;;   The program builds that 152-byte structure in .bss field by field, which is
;;;   worth watching: a C `struct` is nothing but a set of agreed byte offsets,
;;;   and here you can see the agreement being honoured by hand.
;;;
;;;   THE ODDEST PART IS `sa_restorer`, and it is genuinely strange. When your
;;;   handler executes `ret`, it does NOT return to your program -- it returns to
;;;   a tiny "trampoline" whose only job is to invoke system call 15,
;;;   `rt_sigreturn`. That call tells the kernel "the handler is finished",
;;;   whereupon the kernel restores every register from the signal frame it saved
;;;   and resumes your interrupted code. Without a restorer the handler's `ret`
;;;   would jump into nothing. Normally the C library supplies this trampoline
;;;   invisibly; here there is no C library involvement, so the program provides
;;;   its own and sets SA_RESTORER (0x04000000) to say so.
;;;
;;;   WHY THE HANDLER USES `write` AND NOT `printf`. A handler can interrupt your
;;;   program ANYWHERE -- including in the middle of printf itself. Calling
;;;   printf again from inside would re-enter a function that is already
;;;   half-executed, with its internal buffers in an inconsistent state. Only
;;;   ASYNC-SIGNAL-SAFE functions may be called from a handler, and `write` is
;;;   one; `printf` and `malloc` emphatically are not. This is a real rule, not a
;;;   stylistic one, and the raw `syscall` here is the correct choice.
;;;
;;;   SIGNAL NUMBERS worth knowing: 2 = SIGINT (Ctrl+C), 3 = SIGQUIT (Ctrl+\),
;;;   9 = SIGKILL (cannot be caught -- that is the point of it), 11 = SIGSEGV,
;;;   15 = SIGTERM (what `kill` sends by default).
;;;
;;;   A NOTE ON `sigsetsize`: the fourth argument is 8, the number of BYTES of
;;;   sigset_t the kernel should look at. The struct reserves 128, and the kernel
;;;   only ever uses 8 on this platform. The comment in the original ("8 on your
;;;   system") is exactly right.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/7/logger.asm"
;;;   ...then press Ctrl+C a few times and watch it refuse to die.
;;;   To stop it: press Ctrl+\ , or from a second terminal run
;;;       docker ps            # find the container
;;;       docker kill <id>
;;;
;;;   Or drive it from a script, without any typing:
;;;   ./asm "ps_code/7/logger.asm" &
;;;   sleep 1; kill -INT %1; sleep 1; kill -INT %1; sleep 1; kill -9 %1
;;;
;;;   Prove SIGKILL cannot be caught:
;;;   ./asm "ps_code/7/logger.asm" &
;;;   sleep 1; kill -INT %1     # handled, message printed
;;;   sleep 1; kill -KILL %1    # dies instantly, no message
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/7/logger.asm"
;;;
;;;   Useful session -- watch the struct being built:
;;;     break main
;;;     c
;;;     x/19gx &sa                all 152 bytes, still zero
;;;     si si si                  fill sa_handler, sa_flags, sa_restorer
;;;     x/3gx &sa                 the three fields, now set
;;;     info symbol *(long*)&sa   gdb names your handler
;;;     info symbol *(long*)(&sa+16)
;;;                               ...and your restorer
;;;     p/x *(long*)((char*)&sa+8)  0x4000000 -- SA_RESTORER
;;;
;;;   Catch the system call that installs it:
;;;     break logger.asm:NN       NN on the `syscall` after `mov rax, 13`
;;;     c
;;;     info registers rax rdi rsi rdx r10
;;;                               13, 2 (SIGINT), &sa, 0 (no oldact), 8
;;;     si
;;;     p $rax                    0 means success; negative is -errno
;;;
;;;   And catch the handler being entered. From gdb this is easiest with:
;;;     break sigint_handler
;;;     c
;;;     # now, from another terminal: docker ps, then
;;;     #   docker exec <id> kill -INT 1
;;;     bt                        SEE THE CALL-STACK NOTES BELOW
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THIS IS THE ONLY PLACE IN THE COURSE WHERE SOMETHING OTHER THAN YOUR OWN
;;;   CODE PUSHES A FRAME ONTO YOUR STACK.
;;;
;;;   When SIGINT arrives, the kernel does something remarkable: it suspends your
;;;   program mid-instruction-stream, and then -- ON YOUR OWN STACK -- it builds
;;;   a SIGNAL FRAME containing every register you were using, the flags, and the
;;;   address you were about to execute next. Then it sets rip to your handler
;;;   and lets you run. Your handler executes on top of your own interrupted
;;;   code, with the whole of that saved state sitting just below it.
;;;
;;;   You can see it. Break on `sigint_handler`, send a SIGINT, and then:
;;;       bt                     gdb will show the handler, then a frame marked
;;;                              `<signal handler called>`, then the interrupted
;;;                              code in `.loop`
;;;       p $rsp                 note how far it has dropped -- the signal frame
;;;                              is several hundred bytes
;;;       info frame
;;;   That `<signal handler called>` marker is gdb telling you that the frame
;;;   below it was not created by a `call`. Nothing in your program invoked the
;;;   handler; the kernel injected it.
;;;
;;;   THREE CONSEQUENCES WORTH CARRYING AWAY:
;;;
;;;   1. A HANDLER CONSUMES STACK. If a signal arrives when your stack is nearly
;;;      full, the frame does not fit and the process dies. That is why
;;;      long-running programs sometimes install handlers on a separate stack
;;;      (`sigaltstack`) -- particularly handlers for SIGSEGV, which is precisely
;;;      the signal you get for overflowing the stack.
;;;
;;;   2. A HANDLER CAN INTERRUPT ANYTHING, including the middle of printf or
;;;      malloc. Re-entering those from the handler corrupts their internal
;;;      state. Hence the raw `write` in this file, and hence the whole concept
;;;      of async-signal-safe functions.
;;;
;;;   3. THE RETURN PATH IS NOT A `ret`. The handler's `ret` goes to the
;;;      restorer, which calls `rt_sigreturn`, which asks the KERNEL to pop the
;;;      signal frame and restore every register. Watch it:
;;;          break restorer
;;;          c
;;;          bt                  you are one level above the handler
;;;          si                  the syscall -- and control reappears in .loop
;;;                              with every register exactly as it was
;;;      Compare RETURN in ps_code/4's call_return_demo.asm, which is `pop rip`
;;;      by hand. This is the same idea at a higher privilege level: the kernel
;;;      restores not just rip but the entire machine state.
;;;
;;;   And notice what `main` does NOT do here: no prologue, no frame, no `and
;;;   rsp, -16`. It calls nothing, so it needs none of it -- which leaves the
;;;   stack clean and makes the signal frame easy to spot when it appears.
;;; ============================================================================

; logger.asm — print "SIGINT received" when Ctrl+C is pressed

section .data                           ; initialised, writable data
    msg:        db "SIGINT received", 10
                                        ; NO terminating 0 -- sys_write is given an
                                        ;   explicit length, so none is needed. 10 is
                                        ;   the newline.
    msg_len:    equ $ - msg             ; `$` is the address of THIS point, so this is
                                        ;   the byte count above -- computed by NASM at
                                        ;   assembly time, and self-correcting if you
                                        ;   edit the text

section .bss                            ; zero-filled at load time, no file space
                                        ; struct sigaction on x86-64:
                                        ; sa_handler  (8)
                                        ; sa_flags    (8)
                                        ; sa_restorer (8)
                                        ; sa_mask     (128)  ; sigset_t
    sa:         resb 8 + 8 + 8 + 128    ; 152 bytes
                                        ;   THE STRUCT, as raw bytes. A C `struct` is
                                        ;   nothing but a set of agreed offsets, and
                                        ;   here you fill them in by hand: 0, 8, 16, 24.

section .text                           ; the executable-code section
global main                             ; export `main` for the C library start-up

; --- restorer: used when handler returns ---
; kernel jumps here after your handler's 'ret'
; must call sys_rt_sigreturn (15)
;;; ----------------------------------------------------------------------------
;;; restorer -- the signal TRAMPOLINE. NEVER RETURNS.
;;;   Reached by  : the handler's `ret`, because the kernel arranged for its
;;;                 return address to point here
;;;   Does        : one system call, rt_sigreturn (15), which asks the kernel to
;;;                 pop the signal frame and restore every register
;;;   Returns     : it does not -- the kernel resumes the interrupted code
;;;                 instead, at whatever instruction was next when the signal
;;;                 arrived
;;;   Normally the C library provides this invisibly. With no libc in the loop,
;;;   the program must supply it and set SA_RESTORER to say so.
;;; ----------------------------------------------------------------------------
restorer:
    mov     rax, 15                     ; sys_rt_sigreturn
                                        ;   it takes no arguments: everything it needs
                                        ;   is already in the signal frame on the stack
    syscall                             ; does not return
                                        ;   the kernel restores rip, rsp, the flags and
                                        ;   every general register from the frame it
                                        ;   saved, and execution continues in `.loop`

; --- signal handler ---
;;; ----------------------------------------------------------------------------
;;; sigint_handler -- what runs when SIGINT is delivered.
;;;   Reached by  : THE KERNEL, not by any `call` in this program. It can
;;;                 interrupt the program at ANY instruction.
;;;   Receives    : rdi = the signal number (2), which this handler ignores
;;;   Returns     : via `ret` -- into `restorer`, not into the interrupted code
;;;   Clobbers    : rax, rdi, rsi, rdx -- safely, because the kernel saved every
;;;                 register in the signal frame before entering here
;;;   USES `write`, NOT `printf`, and that is required rather than stylistic: a
;;;   handler may interrupt printf itself, and re-entering it would corrupt its
;;;   internal state. Only async-signal-safe functions are legal here.
;;; ----------------------------------------------------------------------------
sigint_handler:
    mov     rax, 1                      ; sys_write
    mov     rdi, 1                      ; stdout
    mov     rsi, msg                    ; argument 2: the bytes
    mov     rdx, msg_len                ; argument 3: how many -- an explicit count
    syscall
    ret                                 ; return to kernel's signal frame
                                        ;   ...which really means "jump to sa_restorer",
                                        ;   because that is the return address the
                                        ;   kernel placed on the stack for us

;;; ----------------------------------------------------------------------------
;;; main -- install the handler, then loop forever.
;;;   Receives : nothing it uses
;;;   Returns  : NEVER -- the final `jmp .loop` is infinite, deliberately
;;;   Clobbers : rax, rcx, rdi, rsi, rdx, r10
;;;   No prologue, no frame, no `and rsp, -16` -- it calls no C function, so none
;;;   of that is needed. That also leaves the stack clean, which makes the signal
;;;   frame easy to see when one appears.
;;; ----------------------------------------------------------------------------
main:
                                        ; sa_handler = sigint_handler
    mov     qword [sa], sigint_handler  ; field at offset 0: the ADDRESS of the handler.
                                        ;   A bare label used as a value is its address.

                                        ; sa_flags = SA_RESTORER (0x04000000)
    mov     qword [sa+8], 0x04000000    ; field at offset 8. This flag tells the kernel
                                        ;   "I am supplying my own restorer at offset
                                        ;   16" -- without it, the handler's `ret` would
                                        ;   go nowhere.

                                        ; sa_restorer = restorer
    mov     qword [sa+16], restorer     ; field at offset 16: the trampoline's address

                                        ; sa_mask = 0 (128 bytes)
    lea     rdi, [sa+24]                ; field at offset 24: the 128-byte signal mask,
                                        ;   i.e. which signals to BLOCK while the
                                        ;   handler runs. Zero means block none.
    mov     rcx, 16                     ; 16 qwords = 128 bytes
                                        ;   rcx is not a free choice: `loop` uses it
    xor     rax, rax                    ; the value to write: zero
.zero_mask:
    mov     [rdi], rax                  ; clear one quadword
    add     rdi, 8                      ; advance by one quadword
    loop    .zero_mask                  ; decrement rcx and repeat while non-zero.
                                        ;   (.bss is already zero-filled at load time,
                                        ;   so this loop is belt-and-braces.)

                                        ; rt_sigaction(SIGINT, &sa, NULL, 8)
    mov     rax, 13                     ; sys_rt_sigaction
    mov     rdi, 2                      ; SIGINT
                                        ;   signal 2 is what Ctrl+C sends. 9 (SIGKILL)
                                        ;   cannot be caught at all -- try it.
    lea     rsi, [sa]                   ; &sa
                                        ;   argument 2: the struct we just filled in
    xor     rdx, rdx                    ; oldact = NULL
                                        ;   argument 3: we do not want the previous
                                        ;   handler back
    mov     r10, 8                      ; sigsetsize = 8 on your system
                                        ;   NOTE r10, NOT rcx. A system call's fourth
                                        ;   argument goes in r10, because `syscall`
                                        ;   itself destroys rcx (it stores the return
                                        ;   rip there). This is the one place the
                                        ;   syscall convention differs from the C one.
    syscall                             ; from this instant, Ctrl+C runs our handler
                                        ;   instead of killing the process

.loop:
    jmp     .loop                       ; infinite loop, waiting for signals
                                        ;   The program does nothing at all -- the
                                        ;   kernel interrupts this jump, runs the
                                        ;   handler, and resumes it. Deliberately never
                                        ;   exits; see the header for how to stop it.
