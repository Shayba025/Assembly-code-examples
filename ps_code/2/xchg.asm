;;; ============================================================================
;;; xchg.asm -- swapping two registers with one instruction
;;; Practice session 2                       (study annotations added)
;;;
;;; WHAT THIS PROGRAM DOES
;;;   Puts 1234 in rax and 5678 in rbx, then swaps them.
;;;   (Verified: rax = 5678, rbx = 1234 at the `nop`.)
;;;
;;;   *** RUNNING IT IS UNRELIABLE, AND THAT IS EXPECTED. *** `main` has no `ret`.
;;;
;;;   THE INSTRUCTION: `xchg a, b` exchanges the two operands. In C you would
;;;   need a temporary --
;;;       t = a;  a = b;  b = t;
;;;   -- and here the hardware supplies it. No third register, no memory, one
;;;   instruction. Compare xorxchg.asm in this folder, which does the same swap
;;;   with three XORs and no temporary either, and change.asm, which is this file
;;;   again with different whitespace.
;;;
;;;   THE THING NOBODY TELLS YOU ABOUT `xchg`: when one operand is MEMORY, `xchg`
;;;   is AUTOMATICALLY ATOMIC -- the CPU asserts a bus lock for the duration,
;;;   even without a `lock` prefix. It is the only instruction that behaves that
;;;   way. That is why `xchg` is the classic building block of a SPINLOCK:
;;;
;;;       acquire:  mov eax, 1
;;;                 xchg eax, [lock_var]    ; atomically swap in a 1
;;;                 test eax, eax           ; what was there before?
;;;                 jnz acquire             ; someone else held it -- try again
;;;
;;;   Because the swap cannot be interrupted half-way, exactly one thread can
;;;   ever see a 0 come back. Register-to-register `xchg`, as used here, needs no
;;;   locking and is just a swap.
;;;
;;;   IT IS ALSO SLOWER THAN IT LOOKS. On modern CPUs a register-to-register
;;;   `xchg` costs about three micro-operations, whereas three `mov`s through a
;;;   scratch register are often faster and can sometimes be eliminated entirely
;;;   by the register renamer. Compilers essentially never emit `xchg` for a
;;;   plain swap. Use it when you want the atomicity, or when registers are
;;;   genuinely scarce.
;;;
;;;   THE FAMILY, worth knowing as a set:
;;;       xchg   swap two operands
;;;       xadd   swap AND add: dst := dst+src, src := old dst   (see code-0012)
;;;       cmpxchg  compare-and-swap -- the primitive behind every lock-free
;;;                data structure
;;;   All three exist mainly for concurrency, and all three are worth
;;;   recognising when you read compiler or library output.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   `main` has no `ret`, so running it is unreliable. To watch what happens:
;;;   ./asm "ps_code/2/xchg.asm" ; echo "exit status = $?"
;;;
;;; DEBUG IT   -- this is how this file is meant to be used
;;;   ./debug "ps_code/2/xchg.asm"
;;;
;;;   Useful session:
;;;     display/d $rax
;;;     display/d $rbx
;;;     si si                     load 1234 and 5678
;;;     si                        the swap -- both change in ONE step
;;;     info registers eflags     unchanged: `xchg` sets no flags
;;;
;;;   Convince yourself no temporary is involved:
;;;     info registers            before the xchg -- note every register
;;;     si
;;;     info registers            after -- only rax and rbx differ. Nothing else
;;;                               was borrowed, not even rsp.
;;;
;;;   And compare the cost with the alternatives:
;;;     x/1i $rip                 the xchg -- 3 bytes
;;;     # a mov-based swap would be three instructions and need a third register
;;;     # an xor-based swap is three instructions and needs none (see xorxchg.asm)
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   Nothing moves on it -- but `xchg` is worth thinking about precisely in
;;;   terms of what the stack normally does for you.
;;;
;;;   Every time a lecture file needed to preserve a value across something, it
;;;   used the stack: `push rsi` / `call printf` / `pop rsi` in code-0002.asm,
;;;   `push rax` to park fib(n-1) in code-0013.asm. The stack is where values go
;;;   when there is nowhere else to put them. `xchg` is the opposite case -- a
;;;   rearrangement that needs NO temporary storage at all, so the stack never
;;;   enters into it.
;;;
;;;   That distinction is worth having in mind when you write your own code. Ask
;;;   "how many values must be alive at once?" If the answer fits in registers,
;;;   you touch no memory. If it does not, you spill -- and then the frame layout
;;;   diagrams from code-0013.asm and code-0018.asm are what you need.
;;;
;;;   One concrete stack connection: `xchg` with a memory operand is atomic, and
;;;   that memory is very often ON THE STACK -- a lock variable in a frame shared
;;;   between threads. Try it in gdb:
;;;       break xchg.asm:NN         NN on the `xchg` line
;;;       # then, at the prompt, look at how an atomic version would address memory
;;;       p/x $rsp
;;;   In this file the operands are both registers, so no locking happens. Change
;;;   it to `xchg rax, [rsp-8]` and the CPU silently locks the bus for you.
;;;
;;;   As everywhere here, rbx is CALLEE-SAVED and clobbered without a push, and
;;;   the return address sits untouched at [rsp]:
;;;       info symbol *(long*)$rsp
;;; ============================================================================

global main                             ; export `main` for the C library start-up
                                        ;   (NASM defaults to section .text)

;;; ----------------------------------------------------------------------------
;;; main -- swap two registers.
;;;   Receives : nothing
;;;   Returns  : rax = 5678, rbx = 1234 -- but there is no `ret`
;;;   Clobbers : rax, and rbx (which is CALLEE-SAVED and is not preserved)
;;; ----------------------------------------------------------------------------
main:
   mov rax, 1234                        ; the first value
   mov rbx, 5678                        ; the second
   xchg rax, rbx                        ; EXCHANGE: rax and rbx trade contents in one
                                        ;   instruction, with no temporary register
                                        ;   and no memory. Sets NO flags.
                                        ;   With a MEMORY operand this instruction is
                                        ;   automatically atomic -- see the header --
                                        ;   which is why it underlies spinlocks.
   nop                                  ; the end -- AND NO `ret`.
