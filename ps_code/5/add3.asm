;;; ============================================================================
;;; add3.asm -- the smallest possible System V function: three arguments, one sum
;;; Practice session 5                       (study annotations added)
;;;
;;; WHAT THIS FILE IS
;;;   A single function, `long add3(long a, long b, long c)`, and NO `main`. It
;;;   cannot be linked on its own -- it is a LIBRARY, meant to be called from C.
;;;   That is the whole point: it shows that a function written in assembly and a
;;;   function written in C are the same kind of object, as long as both obey the
;;;   same calling convention.
;;;
;;;   A C driver, `add3_test.c`, sits next to it in this folder. The ./asm and
;;;   ./debug scripts notice any file named <name>_test.c and link it
;;;   automatically, so the commands below just work.
;;;   (Verified: add3(10,20,30) = 60, and it agrees with C.)
;;;
;;;   THE ENTIRE CONVENTION, on display in four instructions:
;;;       argument 1  ->  rdi          argument 4  ->  rcx
;;;       argument 2  ->  rsi          argument 5  ->  r8
;;;       argument 3  ->  rdx          argument 6  ->  r9
;;;       anything beyond that goes on the stack, right to left
;;;       the return value comes back in rax
;;;   That is the System V AMD64 ABI, and it is why the C compiler's `call add3`
;;;   and this assembly file understand each other without any agreement beyond
;;;   the prototype in the header file.
;;;
;;;   NOTICE WHAT IS ABSENT. There is no prologue, no epilogue, no `push rbp`,
;;;   no frame at all. None is needed:
;;;       * the function has no local variables, so it needs no stack space;
;;;       * it calls nothing, so no register needs protecting across a call;
;;;       * it touches only rax, which is CALLER-saved -- free to clobber.
;;;   A function like this is called a LEAF FUNCTION, and leaving out the frame
;;;   is not laziness, it is the correct thing to do. Compare func_demo.asm in
;;;   this folder, which contains the identical `add3` and a `main` that does
;;;   need a frame.
;;;
;;;   WHY `mov rax, rdi` FIRST. rax must end up holding the result, and the sum
;;;   has to start somewhere. Copy the first argument into the answer register,
;;;   then add the other two into it. `add rax, rsi` means rax := rax + rsi.
;;;
;;;   A DETAIL WORTH KNOWING: this file has no `section .note.GNU-stack`, so the
;;;   linker would normally warn that the stack might be made executable. The
;;;   ./asm and ./debug scripts pass `-z noexecstack` to silence it. Every file
;;;   in "lectures code " ends with the marker instead -- that is the proper fix.
;;;
;;; RUN IT   (copy-paste, from inside the "code examples" folder)
;;;   ./asm "ps_code/5/add3.asm"                  # the default 10, 20, 30
;;;   ./asm "ps_code/5/add3.asm" 7 8 9            # your own arguments
;;;   ./asm "ps_code/5/add3.asm" -5 5 100
;;;
;;;   The driver prints the assembly answer and C's own answer side by side, so
;;;   any disagreement is immediately visible.
;;;
;;; DEBUG IT
;;;   ./debug "ps_code/5/add3.asm" 7 8 9
;;;
;;;   Useful session:
;;;     break add3
;;;     c
;;;     info registers rdi rsi rdx     7, 8, 9 -- the C compiler put them there
;;;     bt                             #0 add3, #1 main (in add3_test.c)
;;;     si si si                       the three instructions
;;;     p $rax                         24
;;;     finish                         return to C
;;;     p $rax                         still 24 -- and the C code will print it
;;;
;;;   Watch the convention being obeyed from the C side:
;;;     break main
;;;     c
;;;     disassemble                    look for the `mov edi,.. mov esi,.. mov edx,..`
;;;                                    just before `call add3`. The compiler is
;;;                                    filling exactly the registers this file reads.
;;;
;;;   And prove the function has no frame of its own:
;;;     break add3
;;;     c
;;;     p $rsp
;;;     p $rbp                         rbp still belongs to the CALLER -- add3
;;;                                    never touched it
;;;     x/1gx $rsp                     the return address, sitting at the very top
;;;     info symbol *(long*)$rsp       a line inside main, in add3_test.c
;;;
;;; WHAT THE CALL STACK TEACHES YOU HERE
;;;   THIS IS THE MINIMAL CASE, AND IT IS WORTH SEEING EXACTLY. When `add3` is
;;;   running, the ONLY thing on the stack that belongs to it is the eight-byte
;;;   return address that `call` pushed. Confirm it:
;;;       break add3
;;;       c
;;;       p $rsp                     write this down
;;;       finish                     let it return
;;;       p $rsp                     8 higher. That difference is the whole cost
;;;                                  of calling this function.
;;;
;;;   Everything else you have seen -- `push rbp`, `sub rsp, 8*3`, `and rsp, -16`
;;;   -- is there to solve a problem this function does not have. Work through
;;;   when each one becomes necessary:
;;;       push rbp / mov rbp, rsp   needed once you have locals or arguments to
;;;                                 address, because rsp moves and rbp does not
;;;                                 (code-0015.asm, code-0018.asm)
;;;       sub rsp, k                needed to create local variables
;;;       and rsp, -16              needed before you CALL anything, because the
;;;                                 ABI promises 16-byte alignment at every call
;;;       push rbx / pop rbx        needed if you use a callee-saved register
;;;   A leaf function that uses only caller-saved registers needs none of them,
;;;   and that is why the fastest functions in any program are the small ones.
;;;
;;;   ONE MORE THING TO LOOK AT: `bt` inside add3 shows main as frame #1, even
;;;   though add3 built no frame. gdb can do that because the compiler recorded
;;;   unwind information in the object file -- and NASM emitted enough (via the
;;;   `-g -F dwarf` flags the ./asm script passes) for the line numbers to work.
;;;   Without debug information, `bt` on a frameless function is guesswork.
;;; ============================================================================

section .text                           ; the executable-code section
global add3                             ; export `add3` so the C driver can call it.
                                        ;   NOTE: no `global main` -- this file has no
                                        ;   main() and cannot be linked alone.

;;; ----------------------------------------------------------------------------
;;; add3 -- return the sum of three long arguments.
;;;   C signature : long add3(long a, long b, long c)
;;;   Receives    : rdi = a, rsi = b, rdx = c   (System V AMD64 ABI)
;;;   Returns     : rax = a + b + c
;;;   Clobbers    : rax only -- which is caller-saved, so nothing needs saving
;;;   Stack use   : just the 8-byte return address `call` pushed. NO FRAME.
;;;   This is a LEAF FUNCTION: no locals, no calls, no callee-saved registers.
;;;   That is why it needs no prologue and no epilogue.
;;; ----------------------------------------------------------------------------
add3:
    mov rax, rdi                        ; rax := a. The result register has to start
                                        ;   somewhere, so seed it with the first
                                        ;   argument.
    add rax, rsi                        ; rax := a + b. `add dst, src` means
                                        ;   dst := dst + src.
    add rax, rdx                        ; rax := a + b + c. The ABI says the return
                                        ;   value goes in rax, and it is already there.
   ret                                  ; pop the return address into rip. The caller
                                        ;   finds the answer in rax.
