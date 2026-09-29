// idr.facts: what code may do besides computing its results, for the passes
// that drop, move or run it at compile time. Every function carries what
// idr-effects finds, `idr.effects`, and what Idris proves, `idr.total`; the
// questions the partitions answer read those and the ops themselves,
// nothing else.
export module idr.facts;

export import :closures;
export import :effects;
export import :evaluation;
export import :functions;
export import :infer;
export import :moves;
