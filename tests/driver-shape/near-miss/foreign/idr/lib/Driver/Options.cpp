// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
namespace idr::driver {
llvm::cl::opt<std::string> outputPath("o", llvm::cl::desc("Write the executable here"));
llvm::cl::list<std::string> packages("p", llvm::cl::desc("Load the Idris package of this name"));
} // namespace idr::driver
