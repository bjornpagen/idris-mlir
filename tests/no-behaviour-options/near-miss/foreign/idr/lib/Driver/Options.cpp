// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
namespace idr::driver {
cl::opt<std::string> inputPath(cl::Positional, cl::desc("<input>"));
cl::opt<std::string> outputPath("o", cl::desc("Write the executable here"));
cl::list<std::string> packages("p", cl::desc("Load the Idris package of this name"));
cl::opt<unsigned> numThreads(
    "num-threads", cl::desc("Compile with this many threads"));
extern cl::opt<bool> elsewhere;
}
