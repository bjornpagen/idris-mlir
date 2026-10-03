// rt.big: bigs, Integer and the Nat-like types. A value that fits in 63 bits
// is a tagged word, and any other is a GMP integer, so each integer has one
// representation; every operation returns the small form when the result
// fits.
// PIN(runtime-quarantine) — see PINS.md
export module rt.big;

export import :arithmetic;
export import :bitwise;
export import :compare;
export import :conversions;
export import :digits;
export import :operands;
export import :words;
