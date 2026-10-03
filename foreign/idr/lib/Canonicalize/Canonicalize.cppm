// idr.canonicalize: upstream's canonicalize (Canonicalizer.cpp), with its
// rewrites counted. It collects the same patterns (those of every loaded
// dialect and every registered op, as filter-dialects, disable-patterns and
// enable-patterns filter them), when canonicalize does (at initialization),
// and runs the same greedy driver with the same configuration, whose
// defaults are canonicalize's options, not GreedyRewriteConfig's. The only
// addition is a listener, which changes nothing the driver does: it counts
// the patterns that apply. So the IR is what canonicalize leaves.
export module idr.canonicalize;

export import :counted;
export import :levels;
export import :patterns;
