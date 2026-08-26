#!/usr/bin/env bash
# Assemble, link and RUN one of the course's x86-64 Linux NASM programs.
#
#     ./asm "lectures code /code-0003.asm" 10 20 30
#     echo 42 | ./asm "lectures code /code-0001.asm"
#
# The .o file and the executable are left next to the .asm file.
set -euo pipefail

if [ $# -lt 1 ]; then
	echo "usage: $(basename "$0") file.asm [args...]" >&2
	exit 1
fi

src="$1"; shift
dir="$(cd "$(dirname "$src")" && pwd)"
base="$(basename "$src" .asm)"

if [ -t 0 ]; then tty=(-it); else tty=(-i); fi

docker run --rm "${tty[@]}" -v "$dir:/work" -w /work asm-course \
	bash -c 'set -e
		nasm -f elf64 -g -F dwarf "$1.asm" -o "$1.o"
		x86_64-linux-gnu-gcc -no-pie -o "$1" "$1.o"
		prog="$1"; shift
		exec qemu-x86_64 -L /usr/x86_64-linux-gnu "./$prog" "$@"' _ "$base" "$@"
