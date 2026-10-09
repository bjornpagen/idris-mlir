// idris-mlir: the one user command. Idris source or an idr module in, an
// executable (or with -c an object) out: the frontend beside it for Idris
// source, the pipeline in process, then the pinned clang to link. The
// driver is the module idr.driver (lib/Driver).

import idr.driver;

int main(int argc, char **argv) { return idr::driver::main(argc, argv); }
