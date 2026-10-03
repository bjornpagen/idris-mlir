// rt.platform: what the runtime asks of the operating system and the
// processor, behind one interface: a target entry (CMakeLists.txt) picks
// the units that implement it. Platform/Posix serves every POSIX system;
// each processor has its own unit for its features (Platform/X86_64,
// Platform/Aarch64).
// PIN(runtime-quarantine) — see PINS.md
export module rt.platform;

export import :cpu;
export import :faults;
export import :memory;
export import :stacks;
