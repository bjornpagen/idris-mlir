// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Euclidean division of a non-negative word by a positive constant, as a
// constraint. The identity is the op's. Signed division is Euclidean, so
// the remainder is in `[0, d)`; unsigned division of a non-negative word by
// the same positive constant is that quotient. So `n = q d + r` gives
// `0 <= q <= n`, and `q < n` when `n > 0` and `d > 1`. It does not put `q`
// inside an array whose length may be 0.
//
// The dividend must already be non-negative in the system: an array's
// length is, and so is a word a guard or a definition has bounded. A
// dividend that might be negative has a negative quotient under the same
// division, and a divisor that is not a positive constant does not keep the
// remainder in that range. Nothing here adds the non-negativity.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/InBounds.h"

#include "mlir/IR/Matchers.h"

#include "llvm/ADT/DenseSet.h"

using namespace mlir;
using llvm::DynamicAPInt;

namespace idr::inbounds {

namespace {

// Past this many quotients followed, the rest stay unrelated: an answer is
// then only weaker.
constexpr unsigned quotientLimit = 96;

// `value`, when it is a quotient the system can use. A dividend that is
// itself a quotient is related first, so a chain learns each bound from the
// one under it.
void relateQuotient(System &system, Value value, DenseSet<Value> &seen, unsigned depth) {
  if (depth > quotientLimit || !seen.insert(value).second)
    return;
  if (!system.known(value))
    return;
  auto div = value.getDefiningOp<DivOp>();
  if (!div)
    return;
  std::optional<unsigned> width = widthOf(value.getType());
  Value dividend = div.getLhs();
  APInt divisor;
  if (!width || *width == 0 || !isColumn(dividend) ||
      !matchPattern(div.getRhs(), m_ConstantInt(&divisor)) || !divisor.isStrictlyPositive())
    return;
  int64_t d = divisor.getSExtValue();
  relateQuotient(system, dividend, seen, depth + 1);
  if (d <= 0 || !system.nonNegative(dividend))
    return;
  Linear q = system.of(value);
  Linear n = system.of(dividend);
  Linear r = system.fresh(DynamicAPInt(0), DynamicAPInt(d - 1));
  Linear times;
  times.plus(q, DynamicAPInt(d));
  system.zero(n - times - r);
}

} // namespace

// The path and the length relation are what prove a dividend non-negative,
// so this follows them.
void relateQuotients(System &system) {
  DenseSet<Value> seen;
  for (Value value : system.values())
    relateQuotient(system, value, seen, 0);
}

} // namespace idr::inbounds
