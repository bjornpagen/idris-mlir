// rt.platform: what the runtime asks of the operating system and the
// processor, behind one interface whose partitions a target entry
// (CMakeLists.txt) picks: Platform/Posix's serve every POSIX system, and
// each processor has its own partition for its features (Platform/X86_64,
// Platform/Aarch64). Where Linux and macOS differ, one function of
// Platform/Posix holds the difference, chosen by the target's macros.
// PIN(runtime-quarantine) — see PINS.md
export module rt.platform;

export import :clocks;
export import :cpu;
export import :directories;
export import :faults;
export import :files;
export import :memory;
export import :process;
export import :processors;
export import :stacks;
export import :terminal;
