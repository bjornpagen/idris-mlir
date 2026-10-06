// idr.graph: what the passes ask of the graph of calls and of a function's
// control: the cycles of a graph, tail position (modulo a constructor too),
// and how often a loop runs.
export module idr.graph;

export import :fieldsof;
export import :intailposition;
export import :intailpositionmoduloconstructor;
export import :isselfcall;
export import :moduloat;
export import :passesonprevious;
export import :scc;
export import :symboluses;
export import :trips;
