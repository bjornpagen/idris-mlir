// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The checks of idr-expect's properties, declared from the one table of
// them (Properties.inc, printed from harness/Properties.idr): each takes the
// typed argument of its property's shape, so a check written for another
// shape than its row's does not compile. Private to the pass: a test
// states a property by name, and the contracts reach the universal ones
// through `universal`.
#ifndef IDR_LIB_TRANSFORMS_EXPECT_CHECKS_H
#define IDR_LIB_TRANSFORMS_EXPECT_CHECKS_H

#include "idr/Transforms/Expect.h"

namespace idr::expect {

#define IDR_EXPECT_PROPERTY(name, Shape, check) mlir::LogicalResult check(const Request<Shape> &);
#define IDR_EXPECT_SELF_CHECK(name, Shape, check) IDR_EXPECT_PROPERTY(name, Shape, check)
#define IDR_EXPECT_UNIVERSAL(name, Shape, check) IDR_EXPECT_PROPERTY(name, Shape, check)
#include "Properties.inc"
#undef IDR_EXPECT_UNIVERSAL
#undef IDR_EXPECT_SELF_CHECK
#undef IDR_EXPECT_PROPERTY

} // namespace idr::expect

#endif // IDR_LIB_TRANSFORMS_EXPECT_CHECKS_H
