// idr.driver:options: idris-mlir-cc's command line, its exit statuses and
// the triple it compiles for. Every option is defined here, in one unit, so
// that they register, and --help lists them, in the order they are written.
// IDRIS_MLIR_RUNTIME and IDRIS_MLIR_RUNTIME_BITCODE_SECTION, the runtime the
// build prepared and where it keeps its bitcode, are compile definitions of
// idr_driver.
export module idr.driver:options;

import idr.mlir;

namespace cl = llvm::cl;

export namespace idr::driver {

// Required unless a --print option asks only what the build decided.
cl::opt<std::string> inputPath(cl::Positional, cl::desc("<input.mlir>"));
cl::opt<std::string> outputPath("o", cl::desc("Output file (not with --check)"), cl::init(""));
// Run the idr steps, whose user errors are rejections, and write nothing.
cl::opt<bool> checkOnly("check",
                        cl::desc("Stop before idr-lower and write nothing (exit status 3 "
                                 "names a rejection)"),
                        cl::init(false));
// No compile-time evaluation.
cl::opt<bool> noEval("no-eval", cl::desc("Do not run idr-eval"), cl::init(false));
cl::list<std::string> without(
    "without", cl::CommaSeparated,
    cl::desc("Leave out these steps of the pipeline (an idr-* pass other than idr-lower) or these "
             "mechanisms of idr-rc (reuse, borrow, sink), to measure what each one is worth"));
cl::opt<std::string> remarks("remarks",
                             cl::desc("Print the remarks (passed, missed, failed and analysis) "
                                      "of these categories (a regex), e.g. idr-eval"),
                             cl::init(""));
cl::opt<std::string> remarksFile("remarks-file",
                                 cl::desc("Write the remarks of the categories --remarks names, "
                                          "or of every category without it, to this YAML file"),
                                 cl::init(""));
// Which actions -log-actions-to logs: otherwise every one, each pass
// execution with the whole module.
cl::list<std::string> logActionsTags(
    "log-actions-tags",
    cl::desc("With -log-actions-to, log only the actions of these tags, e.g. idr-eval-call"),
    cl::CommaSeparated);
cl::opt<bool> timing("timing", cl::desc("Report the time of each pass and LLVM stage"),
                     cl::init(false));
cl::opt<std::string> emitKind("emit", cl::desc("obj (default), asm, llvm or mlir"),
                              cl::init("obj"));
cl::opt<std::string> dumpAfter("dump-after",
                               cl::desc("Dump the module after this step, or 'all'"),
                               cl::init(""));
cl::opt<std::string> dumpDir("dump-dir", cl::desc("Directory for --dump-after files"),
                             cl::init("."));
// The default is the target entry's (CMakeLists.txt), and an executable
// names what an older CPU lacks (idris_rt_start). `native` is the machine
// that compiles.
cl::opt<std::string> targetCpu("cpu",
                               cl::desc("Target CPU: " IDRIS_MLIR_TARGET_CPU
                                        " (default), native, or any CPU name LLVM knows "
                                        "for the target"),
                               cl::init(IDRIS_MLIR_TARGET_CPU));
// The runtime, recorded at build time: the object --prepare-runtime wrote
// from the runtime's archive, or that archive itself. Its bitcode joins the
// program's module, and the same file is on every executable's link line
// (--print-runtime). An empty path links no runtime.
cl::opt<std::string> runtimePath("runtime",
                                 cl::desc("The runtime whose bitcode joins the program, and "
                                          "which executables link: what --prepare-runtime "
                                          "wrote, or the archive it reads ('' for none)"),
                                 cl::init(IDRIS_MLIR_RUNTIME));
// Where the prepared runtime keeps the bitcode that joins every program, as
// the target entry's container says (CMakeLists.txt): in a section of its
// object that every link leaves out, or, with no section, in a file of its
// own beside the object, which no link names.
cl::opt<std::string> runtimeBitcodeSection(
    "runtime-bitcode-section",
    cl::desc("The section of the prepared runtime's object that holds its bitcode (by default "
             "the target entry's), or '' for a file beside the object, named as it is with .bc"),
    cl::init(IDRIS_MLIR_RUNTIME_BITCODE_SECTION));
cl::opt<bool> printRuntime("print-runtime",
                           cl::desc("Print the path of the runtime --runtime names, which "
                                    "every executable links, and exit"),
                           cl::init(false));
// The runtime is the same for every program, so it is optimized and
// compiled once, at build time, and each compilation links the result: what
// it then optimizes again is the program, and the runtime code it inlines.
cl::opt<bool> prepareRuntime("prepare-runtime",
                             cl::desc("Optimize the runtime archive --runtime names once, for "
                                      "the default CPU, into the object -o: native code for "
                                      "the link line with its bitcode for inlining, which "
                                      "every compilation then links (no input file)"),
                             cl::init(false));
cl::opt<bool> printTargetTriple("print-target-triple",
                                cl::desc("Print the target triple executables are linked for, "
                                         "and exit"),
                                cl::init(false));
// What links a program for the target entry, after its object, the runtime
// and -o, one argument of the pinned C compiler per line: --target with the
// triple, then the entry's executable and program link flags and GMP. The
// -o flow, tools/bisect.sh and the tests link with these.
cl::opt<bool> printLinkFlags("print-link-flags",
                             cl::desc("Print the arguments that link a program for the target, "
                                      "after its object, the runtime and -o, one per line, and "
                                      "exit"),
                             cl::init(false));
// What other compilers need to compile for the same machine, bench/run.sh's
// C versions among them: the CPU --cpu selects, `native` resolved.
cl::opt<bool> printTargetCpu("print-target-cpu",
                             cl::desc("Print the CPU code is compiled for, and exit"),
                             cl::init(false));

// Exit statuses: an internal error or a
// contract violation is 1, a usage error 2, and a rejection (a user error,
// `unsupported (<reason>)`) 3.
inline constexpr int ok = 0, failure = 1, usage = 2, rejected = 3;

// Code is compiled for the triple the runtime is built for (the target
// entry's), which its bitcode carries. The module records it with the CPU as
// its #llvm.target; every link of a program is for it too (the --target of
// --print-link-flags).
inline constexpr llvm::StringLiteral targetTriple = IDRIS_MLIR_TARGET_TRIPLE;

} // namespace idr::driver
