// idr.driver: idris-mlir-cc, which runs the pipeline in process, from idr
// contract text to one object file that, linked with the runtime's, is the
// whole program; and which prepares that runtime once, at build time
// (--prepare-runtime). The tool's `main` calls idr::driver::main.
export module idr.driver;

export import :besideobject;
export import :cpu;
export import :dump;
export import :emit;
export import :externalize;
export import :isprepared;
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
export import :retarget;
export import :run;
export import :runonlargestack;
export import :sametarget;
export import :settarget;
export import :writeoutput;
