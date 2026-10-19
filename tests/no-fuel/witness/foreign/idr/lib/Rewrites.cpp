// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
void unlimited(mlir::GreedyRewriteConfig &config) {
  config.maxNumRewrites = mlir::GreedyRewriteConfig::kNoLimit;
}
