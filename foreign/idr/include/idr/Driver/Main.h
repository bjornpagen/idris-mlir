// idris-mlir's entry, which the tool's `main` calls: MLIR's and LLVM's
// options with its own, the --print options, which answer what the build
// decided, and the compilation.
#ifndef IDR_DRIVER_MAIN_H
#define IDR_DRIVER_MAIN_H

namespace idr::driver {

// Parses the command line, answers a --print option, or compiles; the exit
// status.
int main(int argc, char **argv);

} // namespace idr::driver

#endif // IDR_DRIVER_MAIN_H
