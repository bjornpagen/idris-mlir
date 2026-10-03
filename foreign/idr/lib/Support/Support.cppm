// idr.support: what the passes share that is no analysis of the program:
// transforms as actions MLIR's action framework can count and skip, the
// rewrites of a greedy driver by pattern, and the statistics of the passes
// a pass runs itself.
export module idr.support;

export import :actions;
export import :counts;
export import :statistics;
