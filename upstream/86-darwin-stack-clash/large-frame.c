// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//
// clang --target=arm64-apple-macosx14.0 -fstack-clash-protection -Werror -O2 -S large-frame.c -o -
//
// At the pin the driver drops the flag on Darwin ("argument unused during
// compilation", an error under -Werror), and without -Werror the 64 KiB
// frame is allocated by one subtraction from sp, which can step over the
// guard page below the stack. With the patch the prologue probes it one
// 4 KiB block at a time (a loop of `sub sp, sp, #1, lsl #12` and
// `ldr xzr, [sp]`). No header and no SDK is needed: it compiles to assembly
// on any host.
void use(char *);

void large(void) {
  char buffer[65536];
  use(buffer);
}
