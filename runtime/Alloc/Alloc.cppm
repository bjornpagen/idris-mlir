// rt.alloc: the runtime's memory: raw blocks, cells, which it counts while
// they live, the allocation entry points over snmalloc, arrays, and GMP's
// allocation through it.
// PIN(runtime-quarantine) — see PINS.md
export module rt.alloc;

export import :arrays;
export import :blocks;
export import :cells;
export import :classes;
export import :gmp;
