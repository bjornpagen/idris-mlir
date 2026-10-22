// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The memory a process may still commit before its host kills it, as the
 * runtime reads it from a Linux host's cgroup files (Platform/Posix/
 * Cgroups.cpp), on every target: read under each root the arguments name,
 * a host's tree the test planted there, so the reader meets limits no host
 * of the test's holds. One line per root: its bytes, or that no limit
 * holds. */
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "idris_rt.h"
#include "program.h"

static int roots;
static char **names;

static void body(void) {
  for (int i = 0; i < roots; ++i) {
    uint64_t limit = idris_rt_commit_limit(names[i]);
    const char *name = strrchr(names[i], '/');
    name = name == NULL ? names[i] : name + 1;
    if (limit == UINT64_MAX)
      printf("%s: no limit\n", name);
    else
      printf("%s: %" PRIu64 " bytes\n", name, limit);
  }
  fflush(stdout);
}

IDRIS_RT_TEST_PROGRAM("commit-limit", 256 * 1024);

int main(int argc, char **argv) {
  roots = argc - 1;
  names = argv + 1;
  idris_rt_test_start(body, argc, argv);
}
