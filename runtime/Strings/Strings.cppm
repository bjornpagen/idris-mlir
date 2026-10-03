// rt.strings: strings, UTF-8 bytes with their scalar count and an ASCII
// flag, over simdutf, and the text of integers and scalars. A string is one
// cell, header, lengths and bytes together, so freeing it is freeing the
// cell.
// PIN(runtime-quarantine) — see PINS.md
export module rt.strings;

export import :concat;
export import :integers;
export import :making;
export import :order;
export import :replacement;
export import :scalars;
export import :show;
export import :simd;
export import :utf8;
