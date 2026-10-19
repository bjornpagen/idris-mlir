// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The stack idris-mlir, idris-mlir-opt and idris-mlir-reduce run on, the
// runtime's reserved-stack runner's, which programs run on too, and the one
// way a tool runs on it: MLIR's parser, printer and walks recurse over
// nested constants, as deep as that stack allows.
// PIN(mlir-recursion)
#ifndef IDR_SUPPORT_STACK_H
#define IDR_SUPPORT_STACK_H

#include "idr/Support/Profile.h"

// The runtime's C ABI: GMP's allocator and the reserved-stack runner.
#include "idris_rt.h"

#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/raw_ostream.h"

#include <cstddef>
#include <string>

// What the stack's exhaustion handler may call: write and _exit.
#include <unistd.h>

namespace idr::support {

namespace detail {

// What the exhaustion handler writes, filled before the run: a signal
// handler may neither format nor allocate.
inline std::string exhaustionMessage;

// From the fault handler, on a signal stack of its own: only write and
// _exit. 1 is every tool's status for an internal error (idris-mlir's
// table is Driver/Options.h's).
[[noreturn]] inline void onExhaustion() {
  (void)!write(2, exhaustionMessage.data(), exhaustionMessage.size());
  _exit(1);
}

struct ToolRun {
  llvm::function_ref<int()> body;
  int status = 1;
};

inline void enterTool(void *argument) {
  // This thread's share of the trace, finished before it is joined.
  profile::ThreadTrace thread;
  auto *run = static_cast<ToolRun *>(argument);
  run->status = run->body();
}

} // namespace detail

// Runs the tool `tool`'s `body` on the runtime's reserved-stack runner and
// returns its exit status. GMP is pointed at the runtime's allocator first,
// while no other thread exists: the folders run the runtime's big
// operations, whose GMP allocates where a program's does. The frontend and
// the link are spawned from the body's thread, which posix_spawn allows.
// The stack running out, or none being reserved, is the tool's internal
// error, said in its name.
inline int runTool(llvm::StringLiteral tool, llvm::function_ref<int()> body) {
  idris_rt_gmp_init();
  detail::exhaustionMessage =
      (llvm::Twine(tool) + ": internal error: the stack is exhausted\n").str();
  detail::ToolRun run{body};
  if (idris_rt_run_on_stack(detail::enterTool, &run, detail::onExhaustion) != 0) {
    llvm::errs() << tool << ": internal error: no stack could be reserved\n";
    return 1;
  }
  return run.status;
}

} // namespace idr::support

#endif // IDR_SUPPORT_STACK_H
