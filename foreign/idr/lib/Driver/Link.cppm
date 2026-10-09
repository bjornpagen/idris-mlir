// idr.driver:link: the executable, the program's object and the runtime
// linked by the pinned clang for the target.
module;
// The target entry's link flags, an X-macro.
#include "idr/TargetEntry.h"

export module idr.driver:link;

import idr.mlir;

import :artifacts;
import :options;
import :report;

export namespace idr::driver {

// What links a program for the target entry, after its object, the runtime
// and -o: --target with the triple, then the entry's executable and
// program link flags and GMP. The link and --print-link-flags read this one
// list.
inline constexpr llvm::StringLiteral linkFlags[] = {
#define IDR_LINK_FLAG(flag) flag,
    IDRIS_MLIR_LINK_FLAGS(IDR_LINK_FLAG)
#undef IDR_LINK_FLAG
};

// The pinned clang links the program's one object and the runtime's (what
// the program did not inline resolves there) into an executable for the
// target the object was compiled for.
int link(const Artifacts &artifacts) {
  std::vector<llvm::StringRef> argv{pinnedCc, artifacts.objectPath, runtimePath.getValue(), "-o",
                                    artifacts.executablePath};
  argv.insert(argv.end(), std::begin(linkFlags), std::end(linkFlags));
  std::string error;
  bool notRun = false;
  int status = llvm::sys::ExecuteAndWait(pinnedCc, argv, std::nullopt, {}, 0, 0, &error, &notRun);
  if (notRun || status != 0) {
    Report() << "internal error: linking with " << pinnedCc << " failed"
             << (notRun || status < 0 ? ": " + error : " with status " + std::to_string(status));
    return failure;
  }
  return ok;
}

} // namespace idr::driver
