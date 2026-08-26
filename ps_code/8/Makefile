# ============================
#  Assembly Build System
#  Supports multiple programs
# ============================

ASM = nasm
ASMFLAGS = -f elf64 -g -F dwarf

LD = ld

# ----------------------------
#  Program 1: power
# ----------------------------
power: powersys.o
	$(LD) powersys.o -o power

powersys.o: powersys.asm
	$(ASM) $(ASMFLAGS) powersys.asm -o powersys.o

run_power: power
	./power

debug_power: power
	gdb ./power


# ----------------------------
#  Program 2: Ackermann safe
# ----------------------------
ack: ackermann_safe.o
	$(LD) ackermann_safe.o -o ack

ackermann_safe.o: ackermann_safe.asm
	$(ASM) $(ASMFLAGS) ackermann_safe.asm -o ackermann_safe.o

run_ack: ack
	./ack

debug_ack: ack
	gdb ./ack


# ----------------------------
#  Program 3: exp
# ----------------------------
exp: exp_x87.o
	$(LD) exp_x87.o -o exp

exp_x87.o: exp_x87.asm
	$(ASM) $(ASMFLAGS) exp_x87.asm -o exp_x87.o

run_exp: exp
	./exp

debug_exp: exp
	gdb ./exp


# ----------------------------
#  Clean
# ----------------------------
clean:
	rm -f *.o power ack exp