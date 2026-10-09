// rt.io: the program's input and output, and its end: standard output and
// input through static buffers; base's files, directories, process,
// terminal, errors and clocks over the platform layer (rt.platform), whose
// pointers are handles of one table; and crash.
// PIN(runtime-quarantine) — see PINS.md
export module rt.io;

export import :buffer;
export import :bytes;
export import :clock;
export import :directories;
export import :ending;
export import :errors;
export import :files;
export import :filetimes;
export import :handles;
export import :input;
export import :lines;
export import :output;
export import :process;
export import :processors;
export import :scratch;
export import :terminal;
export import :writing;
