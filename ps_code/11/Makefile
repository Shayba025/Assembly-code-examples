# Makefile -- SSE / AVX demos, written entirely in x86-64 assembly (NASM).
# ===========================================================================
#   make                 build every program
#   make run             build, then run all seven in order (with banners)
#   make inspect             open regview under gdb (the default program)
#   make inspect PROG=packed open any program under gdb with its debug script
#   make clean           remove binaries and object files
#
# The inspect target builds the chosen program WITH debug info (-g -F dwarf)
# and drives gdb with that program's script (cpuid.gdb, scalar.gdb, fma.gdb,
# packed.gdb, dotprod.gdb, loads.gdb, or inspect.gdb for regview). Each script
# breaks at an exported label and prints the relevant registers.
#
# No C: each .asm is a complete program with its own main calling printf
# (and, for fma_horner, expf). gcc is used only as the linker.
# ===========================================================================
AS      = nasm
ASFLAGS = -f elf64
CC      = gcc
LDFLAGS =

PROGS = cpuid scalar_sse fma_horner packed dotprod loads regview

all: $(PROGS)

%.o: %.asm
	$(AS) $(ASFLAGS) $< -o $@

cpuid:      cpuid.o      ; $(CC) $(LDFLAGS) -o $@ $<
scalar_sse: scalar_sse.o ; $(CC) $(LDFLAGS) -o $@ $<
fma_horner: fma_horner.o ; $(CC) $(LDFLAGS) -o $@ $< -lm
packed:     packed.o     ; $(CC) $(LDFLAGS) -o $@ $<
dotprod:    dotprod.o    ; $(CC) $(LDFLAGS) -o $@ $<
loads:      loads.o      ; $(CC) $(LDFLAGS) -o $@ $<
regview:    regview.o    ; $(CC) $(LDFLAGS) -o $@ $<

run: all
	@for p in $(PROGS); do \
	  echo "==================== $$p ===================="; ./$$p; echo; \
	done

# ---- debugging -----------------------------------------------------------
# Pick the program with PROG=<name>; default is regview.
PROG   ?= regview
# map program -> its gdb script
SCRIPT_cpuid      = cpuid.gdb
SCRIPT_scalar_sse = scalar.gdb
SCRIPT_fma_horner = fma.gdb
SCRIPT_packed     = packed.gdb
SCRIPT_dotprod    = dotprod.gdb
SCRIPT_loads      = loads.gdb
SCRIPT_regview    = inspect.gdb

# extra linker flag: only fma_horner needs libm
LDADD_fma_horner = -lm

inspect:
	$(AS) $(ASFLAGS) -g -F dwarf $(PROG).asm -o $(PROG).o
	$(CC) -g -o $(PROG) $(PROG).o $(LDADD_$(PROG))
	gdb -q -x $(SCRIPT_$(PROG)) ./$(PROG)

clean:
	rm -f $(PROGS) *.o

.PHONY: all run inspect clean
