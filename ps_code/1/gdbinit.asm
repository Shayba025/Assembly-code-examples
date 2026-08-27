### ============================================================================
### gdbinit.asm -- NOT ASSEMBLY. This is a gdb configuration file.
### Practice session 1                       (study annotations added)
###
### WHAT THIS FILE IS
###   Despite the .asm extension, there is not one instruction here. This is a
###   gdb start-up script: a list of commands you would otherwise type by hand,
###   plus three DEFINED COMMANDS of your own. Do not try to assemble it --
###   `nasm` will reject every line.
###
###   Its comment character is `#`, not `;`, which is the quickest way to tell a
###   gdb script from NASM source at a glance.
###
### HOW TO ACTUALLY USE IT
###   gdb looks for a file called `.gdbinit` (leading dot, no extension) and
###   reads it automatically at start-up. So:
###
###   1. Copy it into place, once, from the "code examples" folder:
###          cp "ps_code/1/gdbinit.asm" "ps_code/1/.gdbinit"
###
###   2. Modern gdb refuses to auto-load a .gdbinit from a directory it does not
###      trust. Tell it the directory is fine by putting this in ~/.gdbinit:
###          add-auto-load-safe-path /work
###      (inside the course container, everything is mounted at /work).
###
###   3. Or -- simpler -- just type the commands you want at the gdb prompt.
###      `layout asm` and `set disassembly-flavor intel` are the two that matter.
###
###   The ./debug script already turns on Intel syntax, sets the architecture,
###   attaches to the program and breaks at `main`, so you get most of this
###   file's benefit with no setup at all.
###
### WHAT `define` DOES
###   `define name ... end` creates a new gdb command. Afterwards, typing that
###   name at the gdb prompt runs every line in the block. It is gdb's macro
###   facility, and it is how you avoid retyping a six-line window setup every
###   time you start a session.
###
### WHAT "TUI" MEANS
###   The Text User Interface: gdb's split-screen mode. Instead of a bare prompt
###   you get panes -- source or disassembly on top, registers above that,
###   command line below -- redrawn after every step. It is the closest thing to
###   a graphical debugger you get in a terminal, and it is what makes `si`
###   genuinely useful: you SEE the highlighted line move and the changed
###   registers light up.
###
###   Handy keys once TUI is on:
###       Ctrl-X A       toggle TUI on and off
###       Ctrl-X 2       cycle through the window layouts
###       Ctrl-L         redraw, when the display gets corrupted
###       Up / Down      scroll the focused window, NOT the command history
###       Ctrl-P/Ctrl-N  command history, while TUI has taken the arrow keys
###
### TRY IT RIGHT NOW   (copy-paste, from inside the "code examples" folder)
###   ./debug "ps_code/1/fib.asm"
###
###   Then, at the gdb prompt, type the contents of the `asm` definition below,
###   one line at a time:
###       set disassembly-flavor intel
###       layout asm
###       tui reg all
###   and step with `si`. Watch the register pane highlight exactly the
###   registers each instruction changed. That highlighting is the single most
###   useful feature in this whole file.
###
###   To go back to a plain prompt:
###       tui disable
###
### WHAT THIS HAS TO DO WITH THE CALL STACK
###   `layout asm` plus `tui reg all` keeps rip, rsp and rbp on screen at all
###   times, updating after every instruction. That turns every claim the lecture
###   files make about the stack into something you can simply watch:
###
###     * step a `push`  -- rsp drops by 8
###     * step a `call`  -- rsp drops by 8 AND rip jumps elsewhere
###     * step a `ret`   -- both are undone at once
###     * step a `jmp`   -- rip moves while rsp sits perfectly still
###
###   Add `layout split` (source and disassembly together) and you can watch one
###   line of NASM turn into the machine instructions it actually became. Try it
###   on `lea rax, [rdi + 8*rax - '0']` in code-0016.asm -- one source line, one
###   instruction, three arithmetic operations.
###
###   And when you want frames rather than registers, the TUI does not replace
###   `bt`, `up`, `down` and `info frame`. It just means you can see where you
###   are while you type them.
### ============================================================================

set debuginfod enabled on
                                        # Let gdb fetch debug symbols for system
                                        # libraries over the network, on demand. Makes
                                        # backtraces through the C library readable
                                        # instead of a list of bare hex addresses.
                                        # Needs internet access, harmless without it.

# switch to commandline debugging
define line
                                        # `define` creates a new gdb command. After
                                        # this block, typing `line` runs its body.
  tui disable
                                        # Turn the split-screen Text User Interface
                                        # off, back to a plain scrolling prompt.
end
                                        # `end` closes the definition.

# switch to debugging c:
define clang
                                        # A one-word setup for debugging C source.
   tui  enable
                                        # Turn the split-screen interface on.
   set extended -prompt clang (\w)>
                                        # Intended: change the prompt, so you can tell
                                        # at a glance which mode you are in. (\w
                                        # expands to the working directory.) NOTE the
                                        # real setting is `set extended-prompt`, with
                                        # a hyphen and no space -- as written, gdb
                                        # rejects this line. A typo worth spotting.
   set tui border-mode standout
                                        # How the border of an INACTIVE pane is drawn.
   set tui active-border-mode standout
                                        # ...and of the pane that currently has focus.
   set tui border-kind acs
                                        # Draw borders with the terminal's line-drawing
                                        # characters (ACS) rather than ASCII +-| signs.
   layout src
                                        # Panes: C SOURCE on top, command line below.
end

# switch to debugging assembly - language:
define asm
                                        # The one you actually want for this course.
   set extended -prompt asm (\w)>
                                        # Same intended prompt change, same typo.
   set disassembly-flavor intel
                                        # THE IMPORTANT LINE. gdb defaults to AT&T
                                        # syntax -- `movq %rsp, %rbp`, operands
                                        # reversed, sigils everywhere. This switches to
                                        # Intel syntax, which is what NASM uses:
                                        # `mov rbp, rsp`. Without it, everything you
                                        # disassemble reads backwards from your source.
   layout asm
                                        # Panes: DISASSEMBLY on top, command line below.
                                        # (`layout split` shows source AND disassembly.)
   tui reg all
                                        # Add the register window, showing every
                                        # register and HIGHLIGHTING the ones each
                                        # instruction just changed. This is what makes
                                        # single-stepping worth doing.
   set tui border-mode standout
                                        # cosmetic: inactive pane borders
   set tui active-border-mode standout
                                        # cosmetic: focused pane border
   set tui border-kind acs
                                        # cosmetic: line-drawing characters
end
