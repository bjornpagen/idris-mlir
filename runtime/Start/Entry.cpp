// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The program's entry, idris_rt_start: the machine's checks, the program's
// arguments kept, the host's limit, its stack, and its end. It alone reads
// what the driver knows of the program (idris_rt_program_built), which a
// tool, linking the runtime without it, has no definition of.
#include "Alloc/Alloc.h"
#include "End/End.h"
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "Start/Start.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace {

void runProgram(void *argument) { static_cast<const idris_rt_program *>(argument)->body(); }

} // namespace

// The program's entry, which @main calls with what the lowering knows of
// the program (its body, the IDRIS_RT_CPU_FEATURES bits its target enables)
// and its own argc and argv, which the runtime keeps for
// idris_rt_io_arg_count and idris_rt_io_arg; what the driver knows of it
// (its stack, its largest frame, its signal stack, its name) is
// idris_rt_program_built. The startup check runs first (a machine that
// cannot run the program ends the process before it runs), so this and what
// it calls before it stay compiled for the target's baseline, which
// idris-mlir keeps. Then the program runs on its stack, the heap kept to the
// host's limit; when its main returns, the process ends as returned. It
// never returns.
extern "C" [[gnu::noinline]] IDRIS_RT_BASELINE void
idris_rt_start(const idris_rt_program *program, int32_t argc, char **argv) {
  const idris_rt_built &built = idris_rt_program_built;
  rt::end::name(built.name, built.name_bytes);
  rt::start::checkMachine(program->cpu_features);
  rt::start::keepArguments(argc, argv);
  rt::platform::ignoreBrokenPipes();
  // The program's own frames, the runtime's among them, are the driver's
  // count; the runner adds what outside code takes.
  idris_rt_stack_plan plan{built.stack_bytes, built.frame_bytes, built.signal_bytes};
  // The runner hands its argument to runProgram untouched, which reads the
  // record as the constant it is.
  if (rt::start::run(runProgram, const_cast<idris_rt_program *>(program), plan,
                     rt::platform::commitLimit()) != IDRIS_RT_RAN)
    rt::end::end(rt::end::OutOfMemory{});
  // The checked runtime's count of the cells the program holds, once the
  // handle table has given back the strings the runtime holds for it: one
  // still live when main returns was leaked, which counting placed wrong.
  if constexpr (rt::alloc::checked) {
    rt::io::releaseHandles();
    if (rt::alloc::cellsHeld != 0)
      rt::end::end(rt::end::CellsLeaked{rt::alloc::cellsHeld});
  }
  rt::end::end(rt::end::Returned{});
}
