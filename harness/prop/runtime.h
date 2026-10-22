// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a property program needs of the runtime beyond its C interface: to
// run on it as every user of the runtime does, through its runner, which
// sets the heap and GMP's allocation up before anything of the runtime
// runs; and the checked runtime's count of the cells it holds, which a
// property holds to its model after each operation. A property program
// links the checked runtime (prop.sh), whose count this reads; the runtime
// every program ships with counts nothing.
#pragma once
// A unit of the checked runtime, which the program links: the build tells
// a unit compiled against the runtime it joins the one every program
// links, and this one joins the other.
#undef IDRIS_RT_CHECKED
#define IDRIS_RT_CHECKED 1
#include "Alloc/Alloc.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace prop {

static_assert(rt::alloc::checked, "a property program reads the checked runtime's count");

// The heap cells the checked runtime has made and not freed.
inline uint64_t held() { return rt::alloc::cellsHeld; }

// The stack a property program runs on: the bound tests/runtime-api holds
// the runtime's freeing of 10^7 cells to, which every operation of the
// runtime keeps whatever its input (freeing a structure of any depth,
// GMP's small operands, building a string). A property program that needs
// more has found a recursion on its input.
inline constexpr uint64_t stackBytes = uint64_t{256} * 1024;

namespace detail {
struct Entry {
  int (*properties)(int, char **);
  int argc;
  char **argv;
  int status;
};
inline void enter(void *argument) {
  auto &entry = *static_cast<Entry *>(argument);
  entry.status = entry.properties(entry.argc, entry.argv);
}
} // namespace detail

// properties(argc, argv) on the runtime's runner, every message of the
// runtime's named `name`; its status. A property program is compiled for
// its target's baseline, so the runner's startup check needs no feature
// bit of the processor. A runner the system refuses its memory is the
// process out of memory, which the runtime ends as such.
template <size_t N>
int onRuntime(int argc, char **argv, const char (&name)[N], int (*properties)(int, char **)) {
  detail::Entry entry{properties, argc, argv, 2};
  idris_rt_stack_plan plan{stackBytes, 0, 0};
  if (idris_rt_run_on_stack(detail::enter, &entry, &plan, name, N - 1, 0) != IDRIS_RT_RAN)
    idris_rt_out_of_memory();
  return entry.status;
}

} // namespace prop
