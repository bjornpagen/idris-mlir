// How a tagged action prints, out of the template so that every action
// shares one definition.

#include "idr/Support/Actions.h"

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

void idr::support::printTag(llvm::raw_ostream &os, llvm::StringRef tag) {
  os << '`' << tag << '`';
}
