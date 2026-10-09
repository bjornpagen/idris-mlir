// idr.fold: what the folders of the string and big ops, and of double_head
// and int_head, share: each converts its constant operands to runtime
// values, calls the runtime's own C function, which idris-mlir-cc links
// natively, and converts the result back. A primitive has one
// implementation, at compile time and at runtime; nothing here computes
// one. A total op is not folded where the condition of its guard fails on
// its constants (idr::checkHolds): the guard crashes there first, at
// runtime. The folders themselves (the ops' `fold` hooks) are plain units
// beside it.
export module idr.fold;

export import :calls;
export import :lists;
export import :scope;
export import :values;
