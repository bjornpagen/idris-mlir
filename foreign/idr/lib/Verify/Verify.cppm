// idr.verify: the rules of a program as a whole, which the dialect checks
// through `idr.program` on the module: its root, its declarations and
// types, whether an array can hold a reference to itself, and how often
// each value of quantity 1 is used.
export module idr.verify;

export import :cycles;
export import :linearity;
export import :program;
