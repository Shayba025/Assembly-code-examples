# cpuid.gdb -- inspect the integer feature words cpuid produces.
# Usage:  make inspect PROG=cpuid     (or: gdb -q -x cpuid.gdb ./cpuid)
break dbg_cpuid
run
printf "\n=== leaf-1 result registers (raw feature words) ===\n"
info registers eax ebx ecx edx
printf "\n=== ECX in binary -- bit 28 = AVX, bit 12 = FMA ===\n"
print/t $ecx
printf "\n=== EDX in binary -- bit 25 = SSE, bit 26 = SSE2 ===\n"
print/t $edx
printf "\n=== resuming ===\n"
continue
quit
