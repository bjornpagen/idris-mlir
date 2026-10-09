// idr.ownership: ownership in the idr dialect: which values hold
// references, what each use of one does with it, the passes of idr-rc and
// the verifier of the owned stage.
//
// A value holds references when its type does (a string, a big, a box, a
// closure, a reuse token, or an unboxed sum with a slot of one of these).
// In the owned stage its grade says what it holds:
//   - owned (`!idr.own<T>`): one reference of its own, which exactly one
//     use on every path consumes. Results of calls, constructors, closures,
//     primitives and matches are owned, and so are the parameters that
//     borrow inference leaves owned;
//   - a view (plain T): none; it lives as long as what it was read from. A
//     borrowed parameter lives as long as the call, a field of a
//     constructor (an idr.field, or a field a match region binds) and an
//     idr.borrow as long as the value it was read from, and static data (a
//     constant, whose cells no count reaches) forever.
// idr.dup gives a view one reference of its own, which one use consumes.
//
// Each partition holds one concept. The ones that export nothing (classes,
// cells, checker, commit, ...) are the steps the exported passes share.
export module idr.ownership;

export import :arrayloop;
export import :borrow;
export import :borrowed;
export import :callee;
export import :cells;
export import :checker;
export import :classes;
export import :commit;
export import :counting;
export import :counts;
export import :exclusive;
export import :exclusiveanalysis;
export import :fields;
export import :followed;
export import :inownedstage;
export import :keepscountedfield;
export import :loops;
export import :noconstants;
export import :onlyreads;
export import :opchecks;
export import :ownsignatures;
export import :placement;
export import :rc;
export import :reachesonlyatoms;
export import :readfrom;
export import :references;
export import :regions;
export import :reshape;
export import :reuse;
export import :sharetainted;
export import :specialize;
export import :isstatic;
export import :take;
export import :takeatentry;
export import :takefields;
export import :usedafter;
export import :useof;
export import :usersin;
export import :verify;
export import :wheredies;
