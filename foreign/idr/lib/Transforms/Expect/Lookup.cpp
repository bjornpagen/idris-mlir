// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The properties idr-expect checks, by name.

#include "idr/Transforms/Expect.h"

#include "llvm/ADT/StringSwitch.h"

namespace idr::expect {

Check lookup(llvm::StringRef name) {
  return llvm::StringSwitch<Check>(name)
      .Case("no-closures", noClosures)
      .Case("no-heap-allocation", noHeapAllocation)
      .Case("every-cycle-has-breaker", everyCycleHasBreaker)
      .Case("breaks-last", breaksLast)
      .Case("one-clone", oneClone)
      .Case("not-called", notCalled)
      .Case("quantities-kept", quantitiesKept)
      .Case("reuses-in-place", reusesInPlace)
      .Case("moves-out", movesOut)
      .Case("counts-nothing", countsNothing)
      .Case("in-bounds", inBounds)
      .Case("bounds-checked", boundsChecked)
      .Case("no-guards", noGuards)
      .Case("tests-nothing", testsNothing)
      .Case("resets-unshared", resetsUnshared)
      .Case("reuses-every-cell", reusesEveryCell)
      .Case("contified", contified)
      .Case("facts-as-marked", factsAsMarked)
      .Case("output-fused", outputFused)
      .Case("folds-balanced", foldsBalanced)
      .Case("constant-stack", constantStack)
      .Case("counted-loop", countedLoop)
      .Case("word-loop", wordLoop)
      .Case("pure-array-loops", pureArrayLoops)
      .Case("vectorized", vectorized)
      .Case("narrowed-lanes", narrowedLanes)
      .Case("cells-fit", cellsFit)
      .Default(nullptr);
}

} // namespace idr::expect
