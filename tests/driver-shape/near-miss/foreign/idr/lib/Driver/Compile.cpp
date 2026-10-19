// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
int compile(const Options &options, mlir::DialectRegistry &registry) {
  registry.insert<mlir::arith::ArithDialect, idr::IdrDialect>();
  llvm::cl::ParseCommandLineOptions(argc, argv);
  return options.outputPath.empty() ? 1 : 0;
}
