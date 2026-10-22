// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cases of the interval box, each drawn from a seed: a width, and
// operands of that width, each an interval (a constant, a signed or an
// unsigned range, or every value) whose ends are drawn from where the
// meanings change (0, 1 and 2 either side of 0, the ends of the width
// signed and unsigned, the width as a shift amount and its neighbours, the
// edges of the Unicode scalar values) or at random, with members of it:
// its ends, points drawn the same way that it holds, and random ones within
// it.
#ifndef IDR_TESTING_INTERVALCASES_H
#define IDR_TESTING_INTERVALCASES_H

#include "idr/IR/Numeric/Word.h"

#include "mlir/Interfaces/InferIntRangeInterface.h"

#include <cstdint>
#include <vector>

namespace idr::box::intervals {

// An operand: its interval, and members of it, each once.
struct Operand {
  mlir::ConstantIntRanges interval;
  std::vector<numeric::Word> members;
};

// A case: its width, and its operands; a meaning takes as many as it has
// operands, from the first.
struct Case {
  unsigned width;
  std::vector<Operand> operands;
};

// The case of `seed`, with `operands` operands.
Case caseOf(std::uint64_t seed, unsigned operands);

} // namespace idr::box::intervals

#endif // IDR_TESTING_INTERVALCASES_H
