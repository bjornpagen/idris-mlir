// idr.ops: what the hooks of the dialect's ops and types use besides their
// members: what an op does and the effects of IO on buffers and arrays,
// the ranges they state, the rules and syntax they share (an array's
// elements and loop bodies, a match's regions and syntax, a grade's
// spelling), the regions a match takes, and the inliner's rules.
export module idr.ops;

export import :bigbounds;
export import :bytebuffers;
export import :constants;
export import :does;
export import :elements;
export import :gradesyntax;
export import :inliner;
export import :ioeffects;
export import :linearranges;
export import :loopbodies;
export import :matchregions;
export import :matchsuccessors;
export import :matchsyntax;
export import :nonnegative;
export import :takenregions;
export import :untyped;
export import :words;
