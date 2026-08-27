;;; ============================================================================
;;; push_pop_demo.asm -- what `push` and `pop` actually are
;;; Practice session 4                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Puts 42 in rax, saves it, destroys rax, restores it. The answer is 42
;;;   again -- which is the least interesting part of the file. What matters is
;;;   that it does NOT use `push` and `pop`. It uses two macros that spell out
;;;   what those instructions really do:
;;;
;;;       push rax          is exactly       sub rsp, 8
;;;                                          mov [rsp], rax
;;;
;;;       pop rax           is exactly       mov rax, [rsp]
;;;                                          add rsp, 8
;;;
;;;   THAT IS THE ENTIRE MECHANISM. There is no hidden stack object anywhere in
;;;   the machine. "The stack" is a region of ordinary memory, and rsp is an
;;;   ordinary register that happens to point into it. `push` is a subtract and
;;;   a store; `pop` is a load and an add. Nothing else.
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` ends in
;;;   `nop` with no `ret`.
;;;
;;;   NOTE THE ORDER, because it is the only subtle thing here. `push`
;;;   DECREMENTS FIRST and then stores, so the value lands AT the new rsp. `pop`
;;;   LOADS FIRST and then increments. That is why the stack "grows downward":
;;;   each push moves rsp to a lower address. It also explains something you met
;;;   in code-0007a.asm -- the chunk pushed LAST ends up at the LOWEST address,
;;;   which is why a string assembled by pushing must be pushed tail-first.
;;;
;;;   %macro AND %endmacro are NASM's macro facility, expanded by the
;;;   preprocessor BEFORE assembly. `%1` is the first argument. So the two lines
;;;   `PUSH64 rax` and `POP64 rax` become four instructions in the object file --
;;;   check with `objdump` or with `x/8i $rip` in gdb, and you will find no
;;;   `push` instruction at all.
;;;
;;;   WHY THE REAL INSTRUCTIONS STILL EXIST: `push rax` is ONE byte, while the
;;;   sub-and-store pair is eight. On a machine where every function prologue
;;;   pushes registers, that adds up. The macros are here to demystify, not to
;;;   replace.
;;;
;;;   READ THIS TOGETHER WITH call_return_demo.asm in the same folder, which does
;;;   the same trick for `call` and `ret` and is the natural sequel.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   `main` has no `ret`, so running it is unreliable. To watch what happens:
;;;   ./asm "ps_code/4/push_pop_demo.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/4/push_pop_demo.asm"
;;;
;;;   THE session for this file -- watch rsp and memory together:
;;;     display/x $rsp
;;;     display/d $rax
;;;     si                        mov rax, 42
;;;     si                        sub rsp, 8   <- rsp drops. NOTHING is stored yet.
;;;     x/1gx $rsp                garbage: the slot is claimed but not written
;;;     si                        mov [rsp], rax
;;;     x/1gd $rsp                42 -- now it is there
;;;     si                        mov rax, 0   <- the register is destroyed
;;;     p $rax                    0
;;;     x/1gd $rsp                42 -- but the STACK COPY IS UNTOUCHED
;;;     si                        mov rax, [rsp]
;;;     p $rax                    42, recovered
;;;     si                        add rsp, 8   <- the slot is released...
;;;     x/1gd $rsp-8              ...and 42 IS STILL PHYSICALLY THERE
;;;
;;;   That last line is the most important one in the whole exercise. Popping
;;;   does not erase anything. It only moves rsp. The bytes are still in memory,
;;;   unowned, until the next push overwrites them -- which is precisely why a
;;;   pointer to a stack local becomes garbage after the function returns, and
;;;   why code-0007.asm warns about it.
;;;
;;;   See the macros disappear at assembly time:
;;;     x/8i $rip                 no `push`, no `pop` -- just sub/mov/mov/add
;;;     disassemble main
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   EVERYTHING IN THIS COURSE IS BUILT ON THE FOUR INSTRUCTIONS ABOVE. Once you
;;;   see push as "sub then store" and pop as "load then add", the rest follows
;;;   mechanically:
;;;
;;;     * The PROLOGUE `push rbp / mov rbp, rsp` is: drop rsp by 8, save the
;;;       caller's frame pointer there, then take a copy of rsp as an anchor that
;;;       will not move.
;;;     * `sub rsp, 8*3` to make three locals (code-0018.asm) is the SAME
;;;       subtraction as a push, just bigger and without the store. Locals are
;;;       nothing more than stack slots you claimed and named.
;;;     * The EPILOGUE `mov rsp, rbp / pop rbp` un-claims everything at once and
;;;       recovers the saved pointer.
;;;     * `call` is a push of rip followed by a jump, and `ret` is a pop into
;;;       rip. See call_return_demo.asm, which writes them out.
;;;     * `and rsp, -16` is just arithmetic on the same register.
;;;
;;;   Confirm the equivalence yourself, in this very session:
;;;       p $rsp
;;;       # the macro version dropped rsp by 8; a real `push` does the same:
;;;       # break somewhere in any lecture file and compare
;;;   Then open code-0013.asm and look at `push rax` between its two recursive
;;;   calls. It is this exact sub-and-store, saving fib(n-1) into a slot that the
;;;   inner call cannot reach. Same four bytes of machinery, doing real work.
;;; ============================================================================

global main                             ; export `main` for the C library start-up

section .text                           ; the executable-code section
; ------Macros
%macro PUSH64 1                         ; `%macro NAME argcount` begins a macro
                                        ;   definition. Everything up to %endmacro is
                                        ;   substituted by the PREPROCESSOR, before
                                        ;   assembly -- it emits no code of its own.
  sub  rsp, 8                           ; claim 8 bytes: the stack grows DOWNWARD, so
                                        ;   subtracting makes room
  mov [rsp], %1                         ; store the argument into the slot just claimed.
                                        ;   `%1` is replaced by whatever was written at
                                        ;   the call site.
                                        ;   THESE TWO LINES ARE `push %1`, exactly.
%endmacro

%macro POP64 1                          ; the inverse macro
   mov %1 , [rsp]                       ; read the value at the top of the stack...
   add rsp, 8                           ; ...and release the slot by moving rsp back up.
                                        ;   NOTE: nothing is erased. The bytes stay in
                                        ;   memory, merely unowned.
                                        ;   THESE TWO LINES ARE `pop %1`, exactly.
%endmacro

;;; ----------------------------------------------------------------------------
;;; main -- save a register to the stack and restore it, without using push/pop.
;;;   Receives : nothing
;;;   Returns  : rax = 42 -- but there is no `ret`, so nobody collects it
;;;   Clobbers : rax, and rsp (temporarily)
;;;   Four macro-generated instructions and two `mov`s. Step every one of them.
;;; ----------------------------------------------------------------------------
main:
  mov rax, 42                           ; the value we are about to protect
  PUSH64 rax                            ; expands to `sub rsp, 8` + `mov [rsp], rax`.
                                        ;   After this the value exists in TWO places:
                                        ;   the register and the stack slot.
  mov rax, 0                            ; destroy the register -- standing in for
                                        ;   whatever a `call` would have done to it
  POP64 rax                             ; expands to `mov rax, [rsp]` + `add rsp, 8`.
                                        ;   The value comes back from memory.
  nop                                   ; the end -- AND NO `ret`. rax is 42 again.
