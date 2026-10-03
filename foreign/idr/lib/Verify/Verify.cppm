// idr.verify: the rules of a program as a whole, which the dialect checks
// through `idr.program` on the module: its root, its declarations and
// types, and how often each value of quantity 1 is used.
export module idr.verify;

export import :linearity;
export import :program;
