// idr.layout: how idr values are represented at runtime, as the runtime
// (idris_rt.h) reads them: the cells of boxes, closures and arrays, the
// slots of unboxed sums, closure labels and their code, decided once per
// module for its target.
export module idr.layout;

export import :cellinfo;
export import :cells;
export import :codename;
export import :labels;
export import :layouts;
export import :sums;
