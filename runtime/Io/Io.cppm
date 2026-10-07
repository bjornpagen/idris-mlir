// rt.io: standard output and input, and crash. Static storage and the stack
// only: the only libc symbols are write, read, _exit and getenv.
// PIN(runtime-quarantine) — see PINS.md
export module rt.io;

export import :bytes;
export import :ending;
export import :input;
export import :output;
export import :processors;
export import :writing;
