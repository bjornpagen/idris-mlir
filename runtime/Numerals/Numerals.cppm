// rt.numerals: `cast` from String. Idris documents no syntax for it and its
// backends disagree, so the cast reads what Idris's own syntax writes: a
// literal of the target type, with an optional sign before it, as the whole
// string. Any other string is 0, as a cast is total.
// - Every number type reads an integer literal: decimal digits, or 0b, 0o,
//   0x or 0X and digits of that base, in groups that single underscores may
//   separate (1_000). An integer type takes its value modulo 2^N; Double
//   the nearest double, as fromInteger does.
// - Double also reads a decimal literal, digits, a point and digits, with an
//   optional exponent (e, a sign, digits), and digits with an exponent and
//   no point, which is how a double's text is written when it has one
//   significant digit (1e21): every text of a double reads back as it, as
//   IEEE 754 requires of the two conversions, correctly rounded to nearest,
//   ties to even. It reads inf, infinity and nan, in any case, as IEEE 754
//   spells the infinities and NaN.
// So 12.7 is 0 as an Int, being no literal of one, and .5, 5., 1E3 and
// surrounding spaces are no number at all. rt.big reads an Integer's value
// and rt.doubles a Double's.
// PIN(runtime-quarantine) — see PINS.md
export module rt.numerals;

export import :machine;
export import :reading;
