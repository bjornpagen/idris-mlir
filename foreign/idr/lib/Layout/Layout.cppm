// idr.layout: how idr values are represented at runtime, as the runtime
// (idris_rt.h) reads them: the cells of boxes, memo sums and arrays and the
// slots of unboxed sums, decided once per module for its target; and the
// boxes that make every cell's object slots fit its header (fit), which
// idr-defunctionalize decides once the module's types are final.
export module idr.layout;

export import :cellinfo;
export import :cells;
export import :components;
export import :fit;
export import :layouts;
export import :sums;
