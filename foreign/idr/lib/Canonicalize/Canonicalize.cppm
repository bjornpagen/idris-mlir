// idr.canonicalize: canonicalize, with its rewrites counted. The pass
// collects the patterns canonicalize collects, when canonicalize does, and
// runs the same greedy driver with canonicalize's configuration and this
// pass's iteration budget. The listener changes nothing the driver does:
// it counts the patterns that apply. So the IR is what canonicalize
// leaves. A run that rewrites nothing preserves every analysis, which
// skips the walk of every nested operation; a run that rewrites is
// verified.
export module idr.canonicalize;

export import :counted;
