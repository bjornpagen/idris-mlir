// idr.stack: which boxes idr-stack builds in their function's frame: the
// cycles of calls among the module's functions, which cells may outlive
// their frame, and the decision that marks the others.
export module idr.stack;

export import :escape;
export import :mark;
export import :recursion;
