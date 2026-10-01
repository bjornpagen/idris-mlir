// idr.facts: what a function may do besides computing its results. Every
// function carries what idr-effects finds, `idr.effects`, and what Idris
// proves, `idr.total`; a call answers MemoryEffectOpInterface from them
// (CallEffects.cc), so whether code may be dropped, moved or delayed is
// MLIR's question (idr::onlyAllocates, idr::performsIO), and the partitions
// here answer the rest: what a function reaches, what a closure passed to
// a call may do, and what a closed call may be evaluated as.
export module idr.facts;

export import :closures;
export import :effects;
export import :evaluation;
export import :functions;
export import :infer;
