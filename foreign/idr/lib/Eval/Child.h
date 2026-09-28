// Running a round's calls in a child process.
// idris-mlir-cc runs MLIR single-threaded; elsewhere a module pass runs
// alone, so any threads of MLIR's pool wait idle, holding no lock the child
// needs, when it forks. The child runs the calls on a stack reserved as large
// as the address space allows, with a guard below it, and writes each
// result's attribute text to a pipe. A crash the runtime reports ends the
// child; the calls before it have their results and the caller forks again
// for the rest. Total code runs to completion: there is no fuel, no memory
// cap and no time limit.
#pragma once

#include "Eval/Jit.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/STLFunctionalExtras.h"

#include <string>

namespace idr::eval {

// The attribute texts of one call's results and how long the call ran.
struct Result {
  uint64_t nanoseconds = 0;
  llvm::SmallVector<std::string> texts;
};

struct Run {
  enum class Status {
    // Every call ran.
    Done,
    // A call crashed; `message` is what the runtime reported.
    Crashed,
    // The machine refused memory or stack, or killed the child.
    Exhausted,
    // Anything else: an internal error, described by `message`.
    Failed,
  };
  // The results of the calls from the first one, in order; the call after
  // the last of them is the one the status is about.
  llvm::SmallVector<Result> results;
  Status status = Status::Done;
  std::string message;
};

// Runs entries[first...] in a child. `words[i]` is the number of 8-byte
// result slots entry i fills; `reify(i, slots)` turns them into the texts
// of the results, in the child.
Run runInChild(llvm::ArrayRef<Jit::Entry> entries, llvm::ArrayRef<size_t> words, size_t first,
               llvm::function_ref<llvm::SmallVector<std::string>(size_t, llvm::ArrayRef<uint64_t>)>
                   reify);

} // namespace idr::eval
