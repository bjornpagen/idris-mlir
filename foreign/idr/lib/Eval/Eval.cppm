// idr.eval: idr-eval: compile-time evaluation is runtime evaluation, run
// early. A closed call of a function that performs no IO runs the program's
// own lowered code on the same runtime, and its results replace it as
// constants. Whether Idris proves the code terminating decides only how
// much the call may spend, as Idris's own evaluator unfolds partial
// definitions as readily as total ones. Every call runs metered: a call of
// total code ends, but perhaps not soon, so it gets a larger budget than
// one that reaches code Idris does not prove terminating. A call that
// spends its budget, or that the machine refuses memory, stays, to run at
// runtime, as a call that crashes does.
export module idr.eval;

export import :calls;
export import :child;
export import :encoding;
export import :evaluate;
export import :jit;
export import :phases;
export import :reify;
export import :round;
export import :scratch;
