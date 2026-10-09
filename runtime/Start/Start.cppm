// rt.start: the program's entry and the reserved-stack runner. A program's
// main calls idris_rt_start, which checks the processor, keeps the
// program's arguments and runs the program on a reserved stack, so that
// running out of it is a named crash rather than a bare fault that loses the
// buffered output. idris-mlir and
// compile-time evaluation's child run on the same runner, with stacks of
// their own sizes. What it needs of the system is in the platform layer
// (rt.platform).
// PIN(runtime-quarantine) — see PINS.md
export module rt.start;

export import :entry;
export import :runner;
