// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one mangling of a program symbol, applied where idr-lower hands the
// program's functions to the dialects bound for LLVM.

#ifndef IDR_CONVERSION_MANGLE_H
#define IDR_CONVERSION_MANGLE_H

#include "llvm/ADT/StringRef.h"

#include <string>

namespace idr::conversion {

// `name` in the alphabet every assembler and linker takes, [A-Za-z0-9_.$]:
// a code point in [A-Za-z0-9_.] is itself, and every other code point of the
// UTF-8 name, `$` included, is `$`, its decimal value, `$`. Injective, so two
// symbols stay two, and the identity on a C identifier, so a runtime name is
// its own mangling. Every `$` of a mangling is one of an escape's two, so
// the first is followed by a digit; the compiler's own names
// (idr::reservedName) have a letter after their first `$`, so no mangling
// is one of them.
std::string mangle(llvm::StringRef name);

} // namespace idr::conversion

#endif // IDR_CONVERSION_MANGLE_H
