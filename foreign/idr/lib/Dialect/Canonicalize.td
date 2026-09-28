// The canonicalizations of the idr dialect that DRR can state
// (IDR-IO-1, IDR-STR-2). The others are in Canonicalize.cc.

#ifndef IDR_CANONICALIZE
#define IDR_CANONICALIZE

include "mlir/IR/PatternBase.td"
include "idr/IdrOps.td"

def Idr_IsInteger : Constraint<CPred<"::llvm::isa<::mlir::IntegerType>($0.getType())">,
                               "an integer">;
def Idr_IsDouble : Constraint<CPred<"::llvm::isa<::mlir::FloatType>($0.getType())">,
                              "a Double">;

//===----------------------------------------------------------------------===//
// IDR-IO-1 (ELIM-G-7): output fusion. A string built only to be written is
// written piece by piece, in the same order, through the world.
//===----------------------------------------------------------------------===//

def Idr_PutStrOfAppend : Pat<(Idr_PutStrOp (Idr_StrAppendOp $a, $b), $w),
                             (Idr_PutStrOp $b, (Idr_PutStrOp $a, $w))>;

def Idr_PutStrOfCons : Pat<(Idr_PutStrOp (Idr_StrConsOp $c, $s), $w),
                           (Idr_PutStrOp $s, (Idr_PutCharOp $c, $w))>;

def Idr_PutStrOfFromChar : Pat<(Idr_PutStrOp (Idr_StrFromCharOp $c), $w),
                               (Idr_PutCharOp $c, $w)>;

def Idr_PutStrOfShowInt : Pat<(Idr_PutStrOp (Idr_StrShowOp $isSigned, $x), $w),
                              (Idr_PutIntOp $isSigned, $x, $w), [(Idr_IsInteger $x)]>;

def Idr_PutStrOfShowDouble : Pat<(Idr_PutStrOp (Idr_StrShowOp $isSigned, $x), $w),
                                 (Idr_PutDoubleOp $x, $w), [(Idr_IsDouble $x)]>;

//===----------------------------------------------------------------------===//
// IDR-STR-2 (ELIM-G-15): the first character of a string built at runtime.
//===----------------------------------------------------------------------===//

def Idr_HeadOfCons : Pat<(Idr_StrHeadOp (Idr_StrConsOp $c, $s)), (replaceWithValue $c)>;

def Idr_HeadOfShowInt : Pat<(Idr_StrHeadOp (Idr_StrShowOp $isSigned, $x)),
                            (Idr_IntHeadOp $isSigned, $x), [(Idr_IsInteger $x)]>;

def Idr_HeadOfShowDouble : Pat<(Idr_StrHeadOp (Idr_StrShowOp $isSigned, $x)),
                               (Idr_DoubleHeadOp $x), [(Idr_IsDouble $x)]>;

#endif // IDR_CANONICALIZE
