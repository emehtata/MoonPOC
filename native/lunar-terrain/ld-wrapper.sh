#!/bin/bash
# Linker for machines without a C compiler (rustc flavor `ld`): adds the C runtime start
# file and the dynamic loader for executables (build scripts), and a libgcc_s.so link
# (only the runtime libgcc_s.so.1 is installed). Shared objects get neither start file.
lib=/usr/lib/x86_64-linux-gnu
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
ln -s "$lib/libgcc_s.so.1" "$d/libgcc_s.so"
extra=()
case " $* " in *" -shared "*) ;; *) extra=("$lib/crt1.o" -dynamic-linker=/lib64/ld-linux-x86-64.so.2) ;; esac
exec ld "$@" -L"$lib" -L"$d" "${extra[@]}"
