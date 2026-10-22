// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The site of a crash a pass builds. The frontend writes each crash's and
// each guard's site from the source; a pass that builds a crash of its own
// (a test pass's, a dispatch's case no label reaches) has only a location,
// which this reads once into the site the crash carries as its property.
#ifndef IDR_IR_OPS_SITES_H
#define IDR_IR_OPS_SITES_H

#include "mlir/IR/Location.h"

namespace idr {

class SiteAttr;

// The site at `loc`: the file, line and column of the first span it holds,
// and the function the first name it holds names, as a definition's
// location is its Idris name at its span.
SiteAttr siteOf(mlir::Location loc);

} // namespace idr

#endif // IDR_IR_OPS_SITES_H
