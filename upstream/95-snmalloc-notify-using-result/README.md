<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [snmalloc] A refused commit hands out PROT_NONE pages

At snmalloc 0.7.6 (f126f1c, the pin of third_party/snmalloc), with the
`pal_enforce_access` mitigation, memory is reserved `PROT_NONE` and
committed by `notify_using`, whose `mprotect` result the POSIX and Apple
PALs ignore: both return true (`src/snmalloc/pal/pal_posix.h`,
`notify_using`, `notify_using_readonly`; `pal_apple.h`, `notify_using`;
*read*). On a host that refuses the commit (Linux with overcommit mode
2 past its limit) the caller hands out pages that stayed `PROT_NONE`,
and the program dies by SIGSEGV at its first touch, with no name and its
output lost (P0 §8's runtime row; proposals/0000 C100, D35, D37). Every
caller already handles a false result: `CommitRange` releases the range
and returns null, and the pagemap's registration fails.

## Reproduce

A program under `ulimit -v`, or overcommit mode 2, at the image plus a
few MiB, with the runtime compiled with `pal_enforce_access`: it dies by
SIGSEGV where it should end with status 111 (*read*; L19's check).

## Patch

`snmalloc.patch`, applying after 94: `notify_using` and
`notify_using_readonly` return false when `mprotect` fails, in both PALs.
Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed. Bjorn files it, if they choose
to (the Microsoft CLA, as 49's README notes).

- Where: one pull request against microsoft/snmalloc main.
- Upstream test: a unit test with a PAL whose `mprotect` fails, checking
  that the allocation returns null.
- The patch goes when a pinned snmalloc release reports the failure.
