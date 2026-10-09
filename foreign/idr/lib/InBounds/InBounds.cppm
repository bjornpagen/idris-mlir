// idr.inbounds: the guards that can never crash, erased, so that a proof
// is the guard's absence and lowering has nothing to check. Base's arrays
// check an index against the size they keep beside the array, and the
// access's guard checks it again; once a record of the two is taken apart,
// only the knowledge that the size is the array's length (lengths, over
// the values bound at joins and the components a constructor stored,
// joins) lets the first check prove the second. The proof is a
// system of linear constraints over the integers (system, of linear
// expressions, linear), from the path to the guard (paths), a Euclidean
// quotient of a non-negative value (quotients), a masked index below a
// capacity already proved a positive power of two, doubling included when
// the double stays below the sign (masks), and the bounds
// its loops keep their counters in (induction), decided exactly (prove).
// A guard of any kind also goes when an identical one runs before it, or
// when the ranges of its integers show its condition (prove).
export module idr.inbounds;

export import :components;
export import :guards;
export import :induction;
export import :joins;
export import :lengths;
export import :linear;
export import :masks;
export import :paths;
export import :prove;
export import :quotients;
export import :system;
