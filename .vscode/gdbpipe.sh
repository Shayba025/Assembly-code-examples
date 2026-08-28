#!/bin/bash
# Pipe VS Code's debugger session into the container.
#
# The C/C++ extension starts this script and tells it how to launch gdb. It may
# do that in either of two ways, so both are handled:
#
#   * as an ARGUMENT   -- what it actually does: argv[1] is the gdb command line
#   * on STDIN         -- the classic ssh-style pipe protocol
#
# Either way we `exec docker exec`, which replaces this shell so the rest of the
# pipe carries the GDB/MI conversation straight to gdb.
#
# Progress is logged to /tmp/asm-gdbpipe.log.
LOG=/tmp/asm-gdbpipe.log
DEFAULT_GDB="/usr/bin/gdb-multiarch --interpreter=mi"

{
	echo "=== $(date '+%H:%M:%S') gdbpipe.sh started"
	echo "    argv: $*"
	docker ps --filter name=asm-dbg --format '    container: {{.Names}} {{.Status}}' 2>&1
} >>"$LOG"

if ! docker ps --filter name=asm-dbg --format '{{.Names}}' | grep -q asm-dbg; then
	echo "    FAILED: container asm-dbg is not running" >>"$LOG"
	exit 1
fi

if [ $# -gt 0 ]; then
	gdb_cmd="$*"                         # the normal path: no waiting at all
	echo "    gdb command from argv" >>"$LOG"
elif IFS= read -r -t 3 line && [ -n "$line" ]; then
	gdb_cmd="$line"
	echo "    gdb command from stdin" >>"$LOG"
else
	gdb_cmd="$DEFAULT_GDB"
	echo "    nothing supplied -- using the default" >>"$LOG"
fi

echo "    exec: docker exec -i asm-dbg $gdb_cmd" >>"$LOG"
exec /usr/local/bin/docker exec -i asm-dbg $gdb_cmd
