// idris-mlir-cc: runs the pipeline in process, from idr contract text to one
// object file that, linked with the runtime's, is the whole program. The
// driver is the module idr.driver (lib/Driver).

import idr.driver;

int main(int argc, char **argv) { return idr::driver::main(argc, argv); }
