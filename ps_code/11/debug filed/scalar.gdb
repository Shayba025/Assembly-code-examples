# scalar.gdb -- watch lane 0 of xmm0 change across the scalar ops.
# Usage:  make inspect PROG=scalar_sse   (or: gdb -q -x scalar.gdb ./scalar_sse)
break dbg_scalar
run
printf "\n=== xmm0 before addss (only lane 0 is live) ===\n"
print $xmm0.v4_float
display $xmm0.v4_float
printf "\n=== step the addss : lane 0 should become 42 ===\n"
stepi
print $xmm0.v4_float
printf "\n=== continue to maxss ===\n"
break fmax2_f
continue
printf "\n=== inputs to maxss ===\n"
print $xmm0.v4_float
print $xmm1.v4_float
printf "\n=== resuming ===\n"
delete
continue
quit
