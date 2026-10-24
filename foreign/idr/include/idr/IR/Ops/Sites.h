// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The site of a crash a pass builds, and the operands a crash takes. The
// frontend writes each crash's and each guard's site from the source; a
// pass that builds a crash of its own (a test pass's, a dispatch's case no
// label reaches) has only a location, which this reads once into the site
// the crash carries as its property.
#ifndef IDR_IR_OPS_SITES_H
#define IDR_IR_OPS_SITES_H

#include "mlir/IR/Location.h"

#include <cstdint>

namespace idr {

class SiteAttr;
enum class CrashCause : std::uint32_t;

// How many operands a crash of `cause` takes: those its line reads, as the
// specification's ending table says (causeOperands), the operand its guard
// found false for a cause whose line names it and none for any other. The
// crash's verifier, the rule that refutes a guard and the guard's lowering
// ask this, so no list of causes is kept beside the table.
unsigned operandsRead(CrashCause cause);

// The site at `loc`: the file, line and column of the first span it holds,
// and the function the first name it holds names, as a definition's
// location is its Idris name at its span.
SiteAttr siteOf(mlir::Location loc);

} // namespace idr

#endif // IDR_IR_OPS_SITES_H
