// rt.platform: what the runtime asks of the operating system and the
// processor, behind one interface whose partitions a target entry
// (CMakeLists.txt) picks: Platform/Posix's serve every POSIX system, and
// each processor has its own partition for its features (Platform/X86_64,
// Platform/Aarch64).
// PIN(runtime-quarantine) — see PINS.md
export module rt.platform;

export import :cpu;
export import :faults;
export import :memory;
export import :processors;
export import :stacks;
