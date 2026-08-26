# Toolchain for the course's x86-64 Linux NASM programs, usable from an Apple
# Silicon (arm64) Mac.
#
# NASM emits x86-64 ELF object files on any host, a cross-linker turns them into
# a Linux x86-64 executable, and qemu-user runs that executable -- with a gdb
# stub, so breakpoints and backtraces work (Docker's own x86 emulation blocks
# ptrace, so plain gdb cannot be used there).
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
        nasm make \
        gcc-x86-64-linux-gnu libc6-dev-amd64-cross \
        qemu-user gdb-multiarch \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
