// idr.lower: idr-lower, which takes idr to func, arith, math, scf, ub and
// llvm in two phases (matches and loops over arrays first, still on idr
// types, then a dialect conversion that takes every idr type apart into the
// layouts of idr.layout), and idr-tail-calls, which makes every call in tail
// position on a cycle of calls a guaranteed tail call once the control flow
// is final.
export module idr.lower;

export import :arrayView;
export import :arrays;
export import :bigs;
export import :buildBox;
export import :cells;
export import :closures;
export import :counting;
export import :crashMessage;
export import :facts;
export import :fields;
export import :frame;
export import :idrPattern;
export import :loops;
export import :lowering;
export import :matches;
export import :passThroughMemory;
export import :patterns;
export import :returnRegisters;
export import :runtime;
export import :runtimeCalls;
export import :scalars;
export import :stackCell;
export import :staticData;
export import :strings;
export import :tailCalls;
export import :tailPosition;
export import :words;
