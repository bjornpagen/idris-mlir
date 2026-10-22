// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one mangling of a program symbol, applied where idr-lower hands the
// program's functions to LLVM.

#ifndef IDR_CONVERSION_MANGLE_H
#define IDR_CONVERSION_MANGLE_H

#include "llvm/ADT/StringRef.h"

#include <string>

namespace idr::conversion {

// What every program symbol begins with. It holds a dot, which no C
// identifier does, so no program symbol is a runtime function's name,
// `main` or a C library's, and it is not `llvm.`, which LLVM keeps for its
// intrinsics; the compiler's own names (idr::reservedName) begin `__idr$`.
// So no check of a collision guards a program symbol.
inline constexpr llvm::StringLiteral programPrefix = "idr.";

// `name` in the alphabet every assembler and linker takes, [A-Za-z0-9_.$]:
// a code point in [A-Za-z0-9_.] is itself, and every other code point of the
// UTF-8 name, `$` included, is `$`, its decimal value, `$`. Injective, so two
// symbols stay two.
std::string mangle(llvm::StringRef name);

// A program symbol's name in LLVM: the program's prefix, then its mangling.
std::string mangleProgramSymbol(llvm::StringRef name);

} // namespace idr::conversion

#endif // IDR_CONVERSION_MANGLE_H
