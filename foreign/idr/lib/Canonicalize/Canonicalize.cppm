// idr.canonicalize: upstream's canonicalize pass, with its rewrites
// counted. The pass is upstream's own, built from this pass's options and
// a configuration that names a listener, so it collects the patterns
// canonicalize collects, when canonicalize does, and runs the greedy driver
// as canonicalize runs it. The listener changes nothing the driver does: it
// counts the patterns that apply. So the IR is what canonicalize leaves.
export module idr.canonicalize;

export import :counted;
export import :levels;
