// idr.expect:lookup: the properties idr-expect checks, by name.
export module idr.expect:lookup;

import idr.mlir;

import :allocation;
import :breaksLast;
import :clones;
import :closures;
import :constantStack;
import :continuations;
import :countedLoop;
import :countsNothing;
import :inBounds;
import :everyCycleHasBreaker;
import :facts;
import :folds;
import :narrowedLanes;
import :output;
import :pureArrayLoops;
import :quantities;
import :resetsUnshared;
import :reusesEveryCell;
import :reusesInPlace;
import :testsNothing;
import :vectorized;
import :words;

using namespace mlir;

export namespace idr::expect {

// Every property takes the module and the text after `=` in its request
// (empty when there is none), and fails when it reported an error.
using Check = LogicalResult (*)(ModuleOp module, StringRef argument);

// The property named `name`, or null when there is none.
Check lookup(StringRef name) {
  return llvm::StringSwitch<Check>(name)
      .Case("no-closures", noClosures)
      .Case("no-heap-allocation", noHeapAllocation)
      .Case("every-cycle-has-breaker", everyCycleHasBreaker)
      .Case("breaks-last", breaksLast)
      .Case("one-clone", oneClone)
      .Case("quantities-kept", quantitiesKept)
      .Case("reuses-in-place", reusesInPlace)
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
      .Default(nullptr);
}

} // namespace idr::expect
