// idr.driver: idris-mlir, the one user command: Idris source through the
// frontend beside it (idris-mlir-front) to an idr module, or a module as
// given, then the pipeline in process to one object file, which the pinned
// clang links with the runtime's into the whole program; and which
// prepares that runtime once, at build time (--prepare-runtime). The
// tool's `main` calls idr::driver::main.
export module idr.driver;

export import :artifacts;
export import :besideobject;
export import :compile;
export import :dump;
export import :emit;
export import :externalize;
export import :frontend;
export import :isprepared;
export import :link;
export import :linkruntime;
export import :main;
export import :markannotated;
export import :marks;
export import :members;
export import :moduleflagstring;
export import :namesapart;
export import :nativeruns;
export import :options;
export import :prepare;
export import :preparedbitcode;
export import :preparemember;
export import :readruntime;
export import :report;
export import :retarget;
export import :run;
export import :runonlargestack;
export import :sametarget;
export import :settarget;
export import :writeoutput;
