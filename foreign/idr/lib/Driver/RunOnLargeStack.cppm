// idr.driver:runonlargestack: the compilation, on a stack of its own.
module;
// The runtime's C ABI: its reserved-stack runner.
#include "idris_rt.h"

// What the stack's exhaustion handler may call: write and _exit.
#include <unistd.h>

export module idr.driver:runonlargestack;

import idr.mlir;

import :options;
import :run;

namespace idr::driver {

namespace {

// The compilation runs on the runtime's reserved-stack runner, on a stack
// as large as the address space allows, committed as it is touched: MLIR's
// parser, printer and walks recurse over nested constants, and compile-time
// evaluation builds them as large as the program's own values (no limits
// but the machine's). PIN(mlir-recursion) — see PINS.md
struct Compilation {
  int status = failure;
};

void compile(void *argument) { static_cast<Compilation *>(argument)->status = run(); }

// From the signal handler: only write and _exit.
[[noreturn]] void compilationExhausted() {
  static constexpr char message[] =
      "idris-mlir-cc: internal error: the compilation exhausted its stack\n";
  (void)!write(2, message, sizeof message - 1);
  _exit(failure);
}

} // namespace

} // namespace idr::driver

export namespace idr::driver {

// Runs `run` on the runtime's reserved-stack runner; its exit status.
int runOnLargeStack() {
  Compilation compilation;
  if (idris_rt_run_on_stack(compile, &compilation, size_t{1} << 44, size_t{1} << 20,
                            compilationExhausted) != 0) {
    llvm::errs() << "idris-mlir-cc: no stack could be reserved for the compilation\n";
    return failure;
  }
  return compilation.status;
}

} // namespace idr::driver
