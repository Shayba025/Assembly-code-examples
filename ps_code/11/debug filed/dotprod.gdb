# dotprod.gdb -- watch 8 partial sums accumulate, then collapse to 1.
# Usage:  make inspect PROG=dotprod   (or: gdb -q -x dotprod.gdb ./dotprod)
break dbg_dot_acc
run
printf "\n=== acc (8 partial sums) at the first FMA ===\n"
display $ymm0.v8_float
stepi
printf "\n=== after one FMA (8 products folded in) ===\n"
print $ymm0.v8_float
printf "\n=== jump to the fold (skip ahead in the loop) ===\n"
delete
break dbg_dot_fold
continue
printf "\n=== 8 partial sums, about to fold ===\n"
print $ymm0.v8_float
stepi
printf "\n=== after vextractf128 : lanes 4..7 now in xmm1 ===\n"
print $xmm0.v4_float
print $xmm1.v4_float
stepi
printf "\n=== after vaddps : 4 partials ===\n"
print $xmm0.v4_float
stepi
stepi
printf "\n=== after two vhaddps : sum in lane 0 ===\n"
print $xmm0.v4_float
printf "\n=== resuming ===\n"
delete
continue
quit
