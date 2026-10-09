// idr.driver:runonlargestack: the compilation, on a stack of its own.
module;
// The runtime's C ABI: its reserved-stack runner.
#include "idris_rt.h"

// What the stack's exhaustion handler may call: write and _exit.
#include <unistd.h>

export module idr.driver:runonlargestack;

import idr.mlir;

import :options;
import :report;

namespace idr::driver {

namespace {

// The compilation runs on the runtime's reserved-stack runner, on a stack
// committed as it is touched: MLIR's parser, printer and walks recurse over
// nested constants, and compile-time evaluation builds them as large as the
// program's own values (no limits but the machine's). The stack is 2^40
// bytes, more than the memory of a machine that compiles, so memory runs
// out first; no more, since reserving costs time in proportion to the
// size, at the start, at the exit and at every fork of compile-time
// evaluation. The frontend and the link are spawned from this thread,
// which posix_spawn allows. PIN(mlir-recursion) — see PINS.md
struct Compilation {
  llvm::function_ref<int()> body;
  int status = failure;
};

void enter(void *argument) {
  auto *compilation = static_cast<Compilation *>(argument);
  compilation->status = compilation->body();
}

// From the signal handler: only write and _exit.
[[noreturn]] void compilationExhausted() {
  static constexpr char message[] =
      "idris-mlir: internal error: the compilation exhausted its stack\n";
  (void)!write(2, message, sizeof message - 1);
  _exit(failure);
}

} // namespace

} // namespace idr::driver

export namespace idr::driver {

// Runs `body` on the runtime's reserved-stack runner; its exit status.
int runOnLargeStack(llvm::function_ref<int()> body) {
  Compilation compilation{body};
  if (idris_rt_run_on_stack(enter, &compilation, size_t{1} << 40, size_t{1} << 20,
                            compilationExhausted) != 0) {
    Report() << "no stack could be reserved for the compilation";
    return failure;
  }
  return compilation.status;
}

} // namespace idr::driver
