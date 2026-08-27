#!/usr/bin/env bash
# Build the given .asm file and start a paused x86-64 debug server for it.
#
#   .vscode/dbgserver.sh <path/to/file.asm> [program args as one string]
#
# Leaves a detached container named `asm-dbg` running the program under
# qemu-user with a gdb stub on port 1234 (inside the container). VS Code's
# debugger reaches it with `docker exec`; see .vscode/launch.json.
#
# STANDARD INPUT: the program runs detached, so there is no terminal attached to
# it. If a file named <name>.stdin sits next to <name>.asm, it is fed to the
# program automatically. That is how you debug scanf/read programs with F5.
# (Alternatively run the "asm: program output" task, which attaches a terminal
# you can both read and type into.)
set -euo pipefail

src="$1"; shift
prog_args="${1:-}"

dir="$(cd "$(dirname "$src")" && pwd)"
base="$(basename "$src" .asm)"

echo "==> building $base"
docker run --rm -v "$dir:/work" -w /work asm-course bash -c "
	set -e
	nasm -f elf64 -g -F dwarf '$base.asm' -o '$base.o'
	if grep -qE '^[[:space:]]*global[[:space:]]+_start' '$base.asm'; then
		x86_64-linux-gnu-ld -z noexecstack -o '$base' '$base.o'
	elif [ -f '${base}_test.c' ]; then
		x86_64-linux-gnu-gcc -no-pie -g -Wl,-z,noexecstack \
			-o '$base' '${base}_test.c' '$base.o' -lm
	else
		x86_64-linux-gnu-gcc -no-pie -Wl,-z,noexecstack \
			-o '$base' '$base.o' -lm
	fi"

docker rm -f asm-dbg >/dev/null 2>&1 || true

echo "==> starting debug server for $base $prog_args"
if [ -f "$dir/$base.stdin" ]; then
	echo "==> feeding $base.stdin to the program's standard input"
	# shellcheck disable=SC2086  -- word splitting of prog_args is intentional
	docker run -d -i --name asm-dbg -v "$dir:/work" -w /work asm-course \
		bash -c "exec qemu-x86_64 -L /usr/x86_64-linux-gnu -g 1234 \
			'./$base' $prog_args < '$base.stdin'" >/dev/null
else
	# shellcheck disable=SC2086
	docker run -d -i --name asm-dbg -v "$dir:/work" -w /work asm-course \
		qemu-x86_64 -L /usr/x86_64-linux-gnu -g 1234 "./$base" $prog_args >/dev/null
fi

# wait until the stub is actually listening before letting the debugger connect
for _ in $(seq 1 50); do
	if docker exec asm-dbg sh -c 'cat /proc/net/tcp 2>/dev/null' | grep -qi ':04D2 '; then
		break
	fi
	sleep 0.1
done

echo "==> ready. Program output appears in the 'asm: program output' task."
