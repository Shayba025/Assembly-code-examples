# fma.gdb -- watch the Horner accumulator xmm1 update on each FMA.
# Usage:  make inspect PROG=fma_horner   (or: gdb -q -x fma.gdb ./fma_horner)
break dbg_fma
run
printf "\n=== x (the evaluation point) ===\n"
print $xmm0.v4_float
printf "\n=== acc BEFORE this term ===\n"
print $xmm1.v4_float
display $xmm1.v4_float
printf "\n=== one vfmadd213ss : acc <- x*acc + coef[i] ===\n"
stepi
print $xmm1.v4_float
printf "\n=== a few more terms ===\n"
stepi
stepi
printf "\n=== resuming ===\n"
delete
continue
quit
