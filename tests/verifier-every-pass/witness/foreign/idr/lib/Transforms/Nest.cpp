// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
void nest(mlir::OpPassManager &pm, bool checked) {
  pm.verifyPasses(checked);
}
