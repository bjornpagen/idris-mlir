// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
def IdrOptimize : Pass<"idr-optimize", "ModuleOp"> {
  let options = [
    Option<"aggressive", "aggressive", "bool", "false", "Inline more">
  ];
}
