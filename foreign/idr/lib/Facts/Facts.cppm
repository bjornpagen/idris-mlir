// idr.facts: what a function may do besides computing its results. Every
// function carries what Idris proves, `idr.total` (every loop of its own
// body terminates), and what idr-effects finds from it and from the ops it
// reaches, `idr.effects`; a call answers MemoryEffectOpInterface from the
// latter (CallEffects.cc), so whether code may be dropped, moved or delayed is
// MLIR's question (idr::onlyAllocates, idr::performsIO), and the partitions
// here answer the rest: what a function reaches, what a closure passed to
// a call may do, and what a closed call may be evaluated as.
export module idr.facts;

export import :breakslast;
export import :closurelabel;
export import :effects;
export import :evaluation;
export import :infer;
export import :inherit;
export import :inlined;
export import :mayholdclosure;
export import :mayholdworld;
export import :of;
export import :passed;
export import :record;
export import :takesworld;
