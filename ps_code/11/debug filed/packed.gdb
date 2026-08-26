# packed.gdb -- watch ALL lanes update on one packed instruction.
# Usage:  make inspect PROG=packed   (or: gdb -q -x packed.gdb ./packed)
break dbg_addps
run
printf "\n=== addps : 4-lane inputs (xmm) ===\n"
print $xmm0.v4_float
print $xmm1.v4_float
printf "\n=== one addps updates all 4 lanes ===\n"
stepi
print $xmm0.v4_float
break dbg_vaddps
printf "\n=== continue to the 8-lane vaddps (ymm) ===\n"
continue
print $ymm0.v8_float
print $ymm1.v8_float
printf "\n=== one vaddps updates all 8 lanes ===\n"
stepi
print $ymm0.v8_float
printf "\n=== resuming ===\n"
delete
continue
quit
