// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
int main(int argc, char **argv) {
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  static llvm::cl::opt<bool> tool("tool");
}
