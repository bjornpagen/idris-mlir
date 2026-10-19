// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
void run(mlir::PassManager &pm, mlir::OpPassManager &nested) {
  pm.enableVerifier(true);
  pm.enableVerifier();
  nested.verifyPasses( true );
}
