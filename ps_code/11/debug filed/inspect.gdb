# inspect.gdb -- inspect a live YMM register in the regview demo.
# Usage:  make inspect          (regview is the default PROG)
#         gdb -q -x inspect.gdb ./regview
#
# Core commands you reuse everywhere:
#   break LABEL · run · print $REG.VIEW · info registers REG
#   display $REG.VIEW · stepi / nexti · continue · quit
break after_load
run
printf "\n=== ymm0 as four 64-bit integers (the stored view) ===\n"
print $ymm0.v4_int64
printf "\n=== ymm0 as eight 32-bit integers ===\n"
print $ymm0.v8_int32
printf "\n=== ymm0 as eight floats (SAME bits, read as float) ===\n"
print $ymm0.v8_float
printf "\n=== xmm0 : the LOW 128 bits, as two int64 ===\n"
print $xmm0.v2_int64
printf "\n=== the whole register, every view at once ===\n"
info registers ymm0
printf "\n=== done; resuming ===\n"
continue
quit
