// mlir-tblgen -gen-pass-decls -name Example -I <mlir include> crtp-pass.td
//
// A pass whose base class is a CRTP template naming the derived pass: the
// generated `ExampleBase<DerivedT>` derives from
// `::example::StagedPass<DerivedT, ::mlir::ModuleOp>`, as the documentation
// the patch adds says. The splice is the pin's; the patch documents it.
include "mlir/Pass/PassBase.td"

class StagedPass<string passArg, string operation>
    : PassBase<passArg, "::example::StagedPass<DerivedT, " # operation # ">">;

def Example : StagedPass<"example", "::mlir::ModuleOp"> {
  let summary = "a pass with a CRTP base class";
}
