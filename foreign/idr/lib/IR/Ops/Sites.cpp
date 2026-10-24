// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The site of a crash a pass builds, read from a location, and the
// operands a crash takes, read from the ending table.

#include "idr/IR/Ops/Sites.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Location.h"

// The ending table: how many operands each cause's line reads.
#include "idr/IR/Generated/Endings.h.inc"

using namespace mlir;

// The dialect's causes and the ending table's are printed from one closed
// set, so a cause's position is its row in the table, as it is the
// runtime's: checked when the compiler is built.
static_assert(idr::EnumTraits<idr::CrashCause>::names ==
              idr::EnumTraits<idr::endings::CrashCause>::names);

unsigned idr::operandsRead(CrashCause cause) {
  return idr::endings::causeOperands[static_cast<idr::endings::CrashCause>(cause)];
}

// Emit writes a definition's location as its Idris name at its span, within
// the fusion a library's code or a deduplication wraps it in, so the first
// span and the first name a walk of the location meets are the place and
// the function. Essential: code no file holds has no span, and its site is
// at no place, the empty file at line 0, column 0, as the frontend writes
// one; and a location may hold no name, which names no function, met only
// by a cause said by its site alone.
idr::SiteAttr idr::siteOf(Location loc) {
  StringRef file;
  uint64_t line = 0;
  uint64_t column = 0;
  if (auto span = loc->findInstanceOf<FileLineColRange>()) {
    file = span.getFilename().getValue();
    line = span.getStartLine();
    column = span.getStartColumn();
  }
  StringRef function;
  if (auto named = loc->findInstanceOf<NameLoc>())
    function = named.getName().getValue();
  return SiteAttr::get(loc.getContext(), file, line, column, function);
}
