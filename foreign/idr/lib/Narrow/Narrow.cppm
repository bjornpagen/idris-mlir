// idr.narrow: integers computed in fewer bits where an analysis proves they
// fit. The bigs and naturals that fit a small become plain i64 words, after
// versioning a loop whose natural only descends (words, with the analysis,
// naturals; the bounds of values, facts; the ops, ops; the values carried
// round loops and out of merges, carried; the versions, versions). And the
// integer lanes of a vectorized loop compute in 32 bits under a runtime
// bound on its sizes (lanes, on a copy of the loop, copy, whose ops' widths
// widths reads).
export module idr.narrow;

export import :carried;
export import :copy;
export import :facts;
export import :lanes;
export import :naturals;
export import :ops;
export import :versions;
export import :widths;
export import :words;
