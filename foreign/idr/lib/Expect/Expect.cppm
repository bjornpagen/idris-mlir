// idr.expect: properties of a module that tests state by name, instead of
// matching the ops that happen to show them. Each property is a function
// that reports every place it fails, one error each, and changes nothing;
// idr-expect looks them up by name.
export module idr.expect;

export import :allocation;
export import :breaksLast;
export import :cellsFit;
export import :clones;
export import :closures;
export import :constantStack;
export import :continuations;
export import :countedLoop;
export import :countsNothing;
export import :inBounds;
export import :everyCycleHasBreaker;
export import :facts;
export import :folds;
export import :lookup;
export import :movesOut;
export import :named;
export import :narrowedLanes;
export import :notCalled;
export import :output;
export import :pureArrayLoops;
export import :quantities;
export import :references;
export import :report;
export import :resetsUnshared;
export import :reusesEveryCell;
export import :reusesInPlace;
export import :roots;
export import :testsNothing;
export import :vectorized;
export import :words;
