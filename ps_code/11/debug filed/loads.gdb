# loads.gdb -- watch an aligned load fill ymm1, then the misaligned case.
# Usage:  make inspect PROG=loads   (or: gdb -q -x loads.gdb ./loads)
break dbg_aligned
run
printf "\n=== ymm1 before vmovaps (stale) ===\n"
print $ymm1.v8_float
stepi
printf "\n=== ymm1 after the ALIGNED load : eight 1.0s ===\n"
print $ymm1.v8_float
display $ymm0.v8_float
printf "\n=== jump to the misaligned vmovups (arr+1) ===\n"
delete
break dbg_misaligned
continue
stepi
printf "\n=== unaligned load from arr+1 succeeded ===\n"
print $ymm0.v8_float
printf "\n=== resuming ===\n"
delete
continue
quit
