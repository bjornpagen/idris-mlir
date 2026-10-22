// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How idris-mlir, idris-mlir-opt and idris-mlir-reduce run: on the
// runtime's runner, as a program does, on a small stack of the size the
// target entry measured for them on the deepest input the tests hold (our
// C++ never recurses on the input's size, and MLIR's recursions that do are
// patched upstream), behind a guard whose fault is the tool's internal
// error. Running out of memory, anywhere in LLVM, MLIR or the runtime, ends
// through one handler: the runtime's out-of-memory ending, its status and
// `<tool>: fatal: out of memory`, never LLVM's abort. A machine that cannot
// run what the target's programs run cannot run the tool either: the
// runtime's native code it links calls the target's simdutf kernels, whose
// features are the program CPU's, so the runner's startup check refuses such
// a machine, as a program's does.
#ifndef IDR_DRIVER_TOOL_H
#define IDR_DRIVER_TOOL_H

#include "idr/Driver/Report.h"
#include "idr/Support/Profile.h"

// The target entry's description: the program CPU's features.
#include "idr/TargetEntry.h"

// The runtime's C ABI: the runner and the out-of-memory ending; and the
// target entry's list of processor features.
#include "cpu_features.h"
#include "idris_rt.h"

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/ErrorHandling.h"

#include <concepts>
#include <cstdint>
#include <functional>
#include <type_traits>

// The tools' stack and signal stack, measured per target (its entry in
// CMakeLists.txt): their deepest path on the stage-1 module and the deep
// nesting fixtures, and the fault handler's on the signal stack.
#ifndef IDRIS_MLIR_TOOL_STACK_BYTES
#error "the target entry gives the tools' stack (IDRIS_MLIR_TOOL_STACK_BYTES)"
#endif
#ifndef IDRIS_MLIR_TOOL_SIGNAL_BYTES
#error "the target entry gives the tools' signal stack (IDRIS_MLIR_TOOL_SIGNAL_BYTES)"
#endif

namespace idr::driver {

namespace detail {

template <class Body>
struct ToolRun {
  Body &body;
  int status;
};

// The runner's C ABI takes a function pointer and an argument: the one
// erasure, instantiated per body, so the body itself is called directly.
template <class Body>
void enterTool(void *argument) {
  // This thread's share of the trace, finished before it is joined.
  profile::ThreadTrace thread;
  auto *run = static_cast<ToolRun<Body> *>(argument);
  run->status = std::invoke(run->body);
}

// LLVM's one hook for memory it cannot get, which its new handler calls
// too: the runtime's ending.
[[noreturn]] inline void outOfMemory(void *, const char *, bool) { idris_rt_out_of_memory(); }

} // namespace detail

// The tools' stack: the measured depth, its guard one page, since the
// tools are compiled with stack-clash probes, so no frame of theirs steps
// over a page; and their signal stack.
inline constexpr idris_rt_stack_plan toolStack{IDRIS_MLIR_TOOL_STACK_BYTES, 0,
                                               IDRIS_MLIR_TOOL_SIGNAL_BYTES};

// The processor features the tools' code may use, as the startup check's
// bits: the program CPU's, a constant of the build.
inline constexpr std::uint64_t toolCpuFeatures =
    rt::platform::featureBitsOf(IDRIS_MLIR_PROGRAM_CPU_FEATURES);

// Runs the tool's `body` on the runner and returns its exit status.
// The runner sets the heap and GMP's allocation up before the body runs,
// while no other thread exists: the folders run the runtime's operations,
// whose memory comes from where a program's does. The frontend and the
// link are spawned from the body's thread, which posix_spawn allows. The
// memory the runner asks for refused is the process out of memory.
template <class Body>
  requires std::same_as<std::invoke_result_t<Body &>, int>
int runTool(Body body) {
  llvm::install_bad_alloc_error_handler(detail::outOfMemory);
  llvm::install_out_of_memory_new_handler();
  detail::ToolRun<Body> run{body, 1};
  if (idris_rt_run_on_stack(detail::enterTool<Body>, &run, &toolStack, toolName.data(),
                            toolName.size(), toolCpuFeatures) != IDRIS_RT_RAN)
    idris_rt_out_of_memory();
  return run.status;
}

} // namespace idr::driver

#endif // IDR_DRIVER_TOOL_H
