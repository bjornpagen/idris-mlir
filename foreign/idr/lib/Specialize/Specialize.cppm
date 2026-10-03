// idr.specialize: idr-specialize, which clones a callee for a consumed
// result (raising) and for the static parts of its arguments
// (specialization), and the binding times that say which parameters a call
// may specialize on, which idr-binding-times reports.
export module idr.specialize;

export import :bindingtime;
export import :bindingtimes;
export import :clones;
export import :eraseunused;
export import :foreachreference;
export import :hasstructure;
export import :interpreter;
export import :isclosed;
export import :keyof;
export import :labels;
export import :operandsfor;
export import :parameterattrs;
export import :pattern;
export import :raise;
export import :rebuild;
export import :renumber;
export import :shapeof;
export import :specialization;
export import :specializer;
export import :unrollsize;
export import :usedonce;
