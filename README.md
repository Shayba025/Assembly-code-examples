# מבוא למחשבים — running the course's x86-64 assembly on an Apple Silicon Mac

This folder holds the course's NASM source files. It now also holds a small
toolchain that lets you **build, run and debug every one of them on a Mac**,
plus study annotations inside each `.asm` file.

---

## 1. Why you cannot just run these files

Every program here is **x86-64 assembly for Linux**:

* NASM syntax, assembled to **ELF64** objects (`nasm -f elf64`)
* linked against **glibc** (`printf`, `scanf`, `atoll`, `malloc`, …)
* using **Linux system call numbers** (`syscall` with `rax = 0/1/2/60`)
* ending in `section .note.GNU-stack`, a Linux linker marker

Your Mac is **arm64** (Apple Silicon) running **macOS**. Neither the instruction
set nor the operating system matches, so there is nothing to run. macOS also
uses Mach-O rather than ELF, and its C library has different symbol names
(`_printf`, not `printf`).

The fix is a Linux container with a cross-toolchain and an emulator. That is
what `Dockerfile`, `asm` and `debug` provide.

---

## 2. One-time setup

You need **Docker Desktop** installed and running. Then, from this folder:

```bash
docker build -t asm-course .
```

That is the whole setup. It takes about a minute the first time and is cached
afterwards. Rebuild it only if you edit the `Dockerfile`.

To check it worked:

```bash
./asm "lectures code /code-0000.asm" ; echo "exit status = $?"     # prints nothing, exits 0
./asm "lectures code /code-0018.asm"                               # a multiplication table
```

---

## 3. Everyday use

### Run a program

```bash
./asm "lectures code /code-0003.asm" 10 20 30      # arguments pass straight through
echo "3, 9" | ./asm "lectures code /code-0001.asm" # stdin works too
./asm "ps_code/6/subset-gen.asm" abc
```

The `.o` file and the executable are left next to the `.asm`, so you can inspect
them (`objdump`, `nm`, `ls -l`) if you want to.

### Debug a program

```bash
./debug "lectures code /code-0004.asm" 3
```

gdb opens **already stopped at the first instruction of `main`**, with Intel
syntax and a live register window. The commands you will use most:

| command | what it does |
|---|---|
| `si` / `ni` | step one instruction (`si` follows `call`, `ni` steps over it) |
| `bt` | backtrace — the chain of unfinished calls |
| `finish` | run the current function to completion and come back |
| `info registers rax rdi` | show particular registers |
| `p $rax` / `p/x $rax` / `p/t $rax` | one register, in decimal / hex / binary |
| `x/8gx $rsp` | dump eight quadwords of stack |
| `x/s $rdi` | show the string a pointer points at |
| `info frame` | this frame's return address and saved `rbp` |
| `info float` | the whole x87 FPU stack |
| `p $ymm0.v8_float` | a vector register, as eight floats |
| `layout regs` / `layout asm` | split-screen views |
| `c` / `q` | continue / quit |

Each `.asm` file's header block contains a **session tailored to that file** —
which line to break on, what to print, and what you should see. Start there.

### Both scripts handle the awkward cases automatically

* **A file with no `main()`** (`ps_code/5/add3.asm`, `asm_demo.asm`,
  `is_even.asm`, `sum_digits.asm`) is a *library*. If a file named
  `<name>_test.c` sits beside it, the scripts compile and link that C driver
  too. Four such drivers are included.
* **A file that defines `_start`** (`ps_code/7/reverse.asm`,
  `ps_code/8/*.asm`) is *freestanding* — no C library at all. The scripts detect
  the `global _start` line and link with plain `ld` instead of `gcc`.
* `-lm` is always linked, for `ps_code/11/fma_horner.asm` which calls `expf`.

---

## 4. Debugging with the play button in VS Code

Open **this folder** in VS Code (`File ▸ Open Folder…`). A `.vscode/` directory
is already configured.

### Without installing anything

`Terminal ▸ Run Task…` offers:

| task | what it does |
|---|---|
| **asm: run current file** | build and run the `.asm` in the active editor (also `⇧⌘B`) |
| **asm: run current file (with arguments)** | same, but prompts for arguments |
| **asm: debug current file in gdb (TUI)** | full-screen gdb with a live register pane |
| **asm: clean build artifacts** | delete every generated `.o` and executable |
| **asm: rebuild the Docker toolchain** | after editing the `Dockerfile` |

### With one extension — real breakpoints in the editor

Install **C/C++** (`ms-vscode.cpptools`); VS Code will offer it, since
`.vscode/extensions.json` recommends it. Then open any `.asm` file, click in the
gutter to set a breakpoint, and press **F5**.

What happens under the hood: a task builds the file and starts it inside the
container paused under a qemu gdb-stub; VS Code runs `gdb-multiarch` *in the
same container* over a pipe and attaches to it. You get the normal debug UI —
step, breakpoints, and a Registers view — on x86-64 code, on an arm64 Mac.

Program output appears in the **asm: program output** task (`Terminal ▸ Run
Task… ▸ asm: program output`), because the program runs detached in the
container.

---

## 5. How the toolchain actually works

```
  your .asm                                        (x86-64 NASM source)
      │
      │  nasm -f elf64 -g -F dwarf                 runs NATIVELY on arm64 —
      ▼                                            NASM is a cross-assembler
  file.o                                           (x86-64 ELF object)
      │
      │  x86_64-linux-gnu-gcc -no-pie              a CROSS-LINKER
      ▼
  file                                             (x86-64 Linux executable)
      │
      │  qemu-x86_64 -L /usr/x86_64-linux-gnu      user-mode EMULATION
      ▼
  output on your terminal
```

**Why qemu and not Docker's own x86 emulation?** Docker Desktop can run
`--platform linux/amd64` images directly, and that works for *running* — but its
Rosetta backend does not support `ptrace`, so **gdb cannot attach**. It fails
with `Cannot PTRACE_GETREGS: Input/output error`. Running the binary under
`qemu-x86_64 -g 1234` gives a gdb stub instead, and that works perfectly. The
image is therefore a *native* arm64 image containing a cross-toolchain, which is
also faster than emulating the whole container.

---

## 6. What is in this folder

| path | what it is |
|---|---|
| `lectures code /` | the professor's 29 lecture examples, **annotated** |
| `ps_code/1` … `ps_code/11` | practice-session files, **annotated** |
| `originals/` | **pristine copies of all 85 original files**, untouched |
| `Dockerfile` | the toolchain image |
| `asm` | build + run one file |
| `debug` | build + open in gdb |
| `tools/align-comments.py` | the formatter that column-aligns every comment |
| `.vscode/` | tasks, launch config, extension recommendations |
| `ps_code/5/*_test.c` | C drivers for the four files that have no `main()` |

Nothing from the course was deleted. If you ever want to compare an annotated
file with what the professor actually wrote:

```bash
diff "originals/lectures code/code-0013.asm" "lectures code /code-0013.asm"
```

---

## 7. What the annotations contain

Every `.asm` file now opens with a banner block containing:

* **WHAT THIS PROGRAM DOES** — the idea, the instructions that are new, the
  traps, and any real bugs (several files have them, all verified by running
  the code and checking in gdb)
* **RUN IT** — copy-paste command lines, including edge cases
* **DEBUG IT** — a gdb session written for *that* file
* **WHAT THE CALL STACK TEACHES YOU HERE** — what to look at, and why

Then every function has a header stating its signature, what arrives in which
register, what it returns, what it clobbers, and how it works — and **every line
has a comment** explaining both what that line does and what the instruction
means in general.

All inline comments are aligned to one column per file, by
`tools/align-comments.py`. If you edit a file and want to restore the alignment:

```bash
python3 tools/align-comments.py "lectures code /code-0013.asm"
python3 tools/align-comments.py "lectures code /"*.asm ps_code/*/*.asm   # everything
```

A few files worth reading as pairs, because the comparison *is* the lesson:

| | |
|---|---|
| `code-0009` vs `code-0010` | factorial: iterative vs recursive |
| `code-0010` vs `code-0011` | C vs Pascal calling convention |
| `code-0013` vs `code-0014` | the same, with double recursion |
| `code-0004` vs `ps_code/6/subset-gen` | backtracking, bits vs letters |
| `code-0018` vs `ps_code/6/multboard` | loop variables in memory vs registers |
| `ps_code/11/scalar_sse` vs `packed` | one lane vs all lanes |
| `ps_code/8/ackermann_safe` vs `powersys` | one file has a one-line bug; find it |

---

## 8. Troubleshooting

**`Cannot connect to the Docker daemon`** — Docker Desktop is not running. Start
it and try again.

**`Unable to find image 'asm-course'`** — run `docker build -t asm-course .`
from this folder.

**The container cannot see my file** — `asm` and `debug` mount only the folder
the `.asm` lives in. For programs that open files (`code-0022.asm`,
`ps_code/7/cp.asm`) use filenames **relative to that folder**, not absolute
paths:

```bash
printf 'hello\n' > "lectures code /sample.txt"
./asm "lectures code /code-0022.asm" sample.txt copy.txt
```

**A program prints nothing and exits with a strange status** — many practice
files in `ps_code/1` and `ps_code/2` deliberately have no `ret`, so they run off
the end of `main` and crash. That is documented at the top of each one; they are
meant to be stepped in gdb, not run.

**F5 does nothing / no debug configuration** — install the C/C++ extension
(`ms-vscode.cpptools`).

**gdb says `Cannot PTRACE_GETREGS`** — you are attaching to a program running
under Docker's own x86 emulation rather than under qemu. Use `./debug` (or the
F5 configuration), which sets this up correctly.

**Everything got slow / stale containers** — clean up with:

```bash
docker rm -f asm-dbg 2>/dev/null
docker ps -q | xargs -r docker kill
```
