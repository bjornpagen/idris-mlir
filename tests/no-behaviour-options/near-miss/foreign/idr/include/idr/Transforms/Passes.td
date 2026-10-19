// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
def IdrExpect : Pass<"idr-expect", "ModuleOp"> {
  let options = [
    ListOption<"holds", "holds", "std::string", "The properties that must hold">
  ];
}
