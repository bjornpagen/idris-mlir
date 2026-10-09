// idr.os: the operating system the target triple names, folded to that string.

#include "idr/Idr.h"

#include "llvm/ADT/StringRef.h"

using namespace mlir;
using namespace idr;

namespace {

// The operating system as Idris's Scheme backends spell it, from the
// target triple: Linux and the BSDs are "unix", Apple's is "darwin",
// Windows is "windows".
llvm::StringRef osName() {
  llvm::StringRef triple = IDRIS_MLIR_TARGET_TRIPLE;
  if (triple.contains("apple") || triple.contains("darwin"))
    return "darwin";
  if (triple.contains("-linux") || triple.contains("freebsd") || triple.contains("openbsd") ||
      triple.contains("netbsd"))
    return "unix";
  if (triple.contains("windows") || triple.contains("mingw") || triple.contains("cygwin"))
    return "windows";
  return "unknown";
}

} // namespace

OpFoldResult OsOp::fold(FoldAdaptor) { return StringAttr::get(getContext(), osName()); }
