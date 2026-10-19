// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// static int counter = 0; thread_local and std::atomic in a comment
static constexpr int kRounds = 3;
static const char *name = "static int counter = 0;";
static inline const int kWidth = 64;
static llvm::cl::opt<bool> verbose("verbose", llvm::cl::desc("say more"));
static int twice(int x) { return 2 * x; }
static mlir::LogicalResult
apply(mlir::Operation *op, int x = 0);
mlir::TypeID Action::getTypeID() {
  static mlir::SelfOwningTypeID id;
  return id;
}
