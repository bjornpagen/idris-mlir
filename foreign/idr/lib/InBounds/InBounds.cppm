// idr.inbounds: the array accesses proven within their arrays, each marked
// `in_bounds` so that lowering emits no check. Base's arrays check an index
// against the size they keep beside the array, and the access checks it
// again; once a record of the two is taken apart, only the knowledge that
// the size is the array's length (lengths, over the values bound at
// joins and the components a constructor stored, joins) lets the first
// check prove the second. The proof is a
// system of linear constraints over the integers (system, of linear
// expressions, linear), from the path to the access (paths), a Euclidean
// quotient of a non-negative value (quotients), a masked index below a
// capacity already proved a positive power of two (masks), and the bounds
// its loops keep their counters in (induction), decided exactly (prove).
export module idr.inbounds;

export import :components;
export import :induction;
export import :joins;
export import :lengths;
export import :linear;
export import :masks;
export import :paths;
export import :prove;
export import :quotients;
export import :system;
