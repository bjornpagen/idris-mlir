# The passes' declarations, registration and bases, generated into
# include/idr/Transforms/Passes.h.inc, which each area header includes with
# the GEN_PASS_DECL_ of its own passes (IdrPassesIncGen).
set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name Idr)
add_public_tablegen_target(IdrPassesIncGen)
