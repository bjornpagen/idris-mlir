// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* A test of the runtime that runs as a compiled program runs: its main
 * hands its body to idris_rt_start, which checks the machine, runs the
 * body on the stack the program states and ends the process as the ending
 * table says, the checked runtime's count of the cells still held when the
 * body returns among them. What the driver writes beside a compiled
 * program, the stack its frames need and its name, which every message
 * begins with, the test states once, in its one file:
 *
 *     IDRIS_RT_TEST_PROGRAM("name", stack bytes);
 *
 * and its main ends with idris_rt_test_start(body, argc, argv). */
#ifndef IDRIS_RT_TEST_PROGRAM_H
#define IDRIS_RT_TEST_PROGRAM_H

#include "idris_rt.h"

/* The cells the checked runtime holds, for a test that links it and
 * held.cpp. */
uint64_t prop_held(void);

#define IDRIS_RT_TEST_PROGRAM(name, stack)                                                         \
  const idris_rt_built idris_rt_program_built = {(stack), 0, 0, (name), sizeof(name) - 1}

/* The body run as a program whose target the processor runs whole: no
 * feature bit it needs. */
IDRIS_RT_NORETURN static inline void idris_rt_test_start(void (*body)(void), int argc, char **argv) {
  static idris_rt_program program;
  program.body = body;
  program.cpu_features = 0;
  idris_rt_start(&program, argc, argv);
}

#endif
