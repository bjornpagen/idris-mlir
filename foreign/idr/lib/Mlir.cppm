// idr.mlir: MLIR's and LLVM's declarations, for module units to import.
// Their headers are parsed here, once; a unit that included them itself
// would parse them again, and one that included them after an import would
// clash with this module's copy of them. MLIR's API is headers only and
// exports nothing, so this module names what idr's code uses and re-exports
// it: each `using` below makes a declaration of the global module fragment
// visible to importers. Operators are re-exported too, so that lookup by
// argument finds them. The idr dialect's own declarations are idr.dialect's.
module;
#include "mlir/Analysis/CallGraph.h"
#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/IntegerRangeAnalysis.h"
#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/Analysis/DataFlow/Utils.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Analysis/Presburger/IntegerRelation.h"
#include "mlir/Analysis/Presburger/PresburgerSpace.h"
#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/Bytecode/BytecodeReader.h"
#include "mlir/Bytecode/BytecodeWriter.h"
#include "mlir/Conversion/ConvertToLLVM/ToLLVMPass.h"
#include "mlir/Conversion/LLVMCommon/MemRefBuilder.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Conversion/ReconcileUnrealizedCasts/ReconcileUnrealizedCasts.h"
#include "mlir/Conversion/SCFToControlFlow/SCFToControlFlow.h"
#include "mlir/Debug/BreakpointManagers/TagBreakpointManager.h"
#include "mlir/Debug/CLOptionsSetup.h"
#include "mlir/Debug/Counter.h"
#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Arith/Transforms/Passes.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Linalg/Passes.h"
#include "mlir/Dialect/Linalg/Transforms/Transforms.h"
#include "mlir/Dialect/Linalg/Utils/Utils.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/Dialect/SCF/Transforms/TileUsingInterface.h"
#include "mlir/Dialect/SCF/Transforms/Transforms.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/Dialect/Vector/Transforms/LoweringPatterns.h"
#include "mlir/Dialect/Vector/Transforms/VectorRewritePatterns.h"
#include "mlir/IR/Action.h"
#include "mlir/IR/AsmState.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Remarks.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Unit.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/CastInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "mlir/Interfaces/LoopLikeInterface.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/TilingInterface.h"
#include "mlir/Interfaces/ValueBoundsOpInterface.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Remark/RemarkStreamer.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Support/Timing.h"
#include "mlir/Support/TypeID.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Export.h"
#include "mlir/Target/LLVMIR/Transforms/TargetUtils.h"
#include "mlir/Target/LLVMIR/TypeToLLVM.h"
#include "mlir/Transforms/DialectConversion.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/Inliner.h"
#include "mlir/Transforms/InliningUtils.h"
#include "mlir/Transforms/LoopInvariantCodeMotionUtils.h"
#include "mlir/Transforms/Passes.h"
#include "mlir/Transforms/RegionUtils.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/DynamicAPInt.h"
#include "llvm/ADT/GraphTraits.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/BinaryFormat/Magic.h"
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/TargetLowering.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/ExecutionEngine/Orc/AbsoluteSymbols.h"
#include "llvm/ExecutionEngine/Orc/ExecutionUtils.h"
#include "llvm/ExecutionEngine/Orc/JITTargetMachineBuilder.h"
#include "llvm/ExecutionEngine/Orc/LLJIT.h"
#include "llvm/ExecutionEngine/Orc/ThreadSafeModule.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DebugInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Mangler.h"
#include "llvm/IR/Module.h"
#include "llvm/Linker/Linker.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Object/Archive.h"
#include "llvm/Object/IRObjectFile.h"
#include "llvm/Object/ObjectFile.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Remarks/RemarkFormat.h"
#include "llvm/Support/CheckedArithmetic.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/FormatVariadic.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/MathExtras.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/MemoryBufferRef.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/SHA1.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/TargetParser/SubtargetFeature.h"
#include "llvm/TargetParser/Triple.h"
#include "llvm/Transforms/IPO/Internalize.h"
#include "llvm/Transforms/Utils/ModuleUtils.h"

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <concepts>
#include <cstdint>
#include <cstring>
#include <expected>
#include <functional>
#include <initializer_list>
#include <limits>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <system_error>
#include <utility>
#include <variant>
#include <vector>

export module idr.mlir;

export namespace mlir {
using mlir::AffineMap;
using mlir::AnalysisState;
using mlir::any;
using mlir::APFloat;
using mlir::APInt;
using mlir::applyDefaultTimingManagerCLOptions;
using mlir::applyOpPatternsGreedily;
using mlir::applyPartialConversion;
using mlir::applyPassManagerCLOptions;
using mlir::applyPatternsGreedily;
using mlir::APSInt;
using mlir::ArrayAttr;
using mlir::ArrayRef;
using mlir::AsmParser;
using mlir::AsmPrinter;
using mlir::Attribute;
using mlir::BitVector;
using mlir::Block;
using mlir::BlockArgument;
using mlir::BoolAttr;
using mlir::BranchOpInterface;
using mlir::Builder;
using mlir::BytecodeOpInterface;
using mlir::CallableOpInterface;
using mlir::CallGraph;
using mlir::CallOpInterface;
using mlir::CallSiteLoc;
using mlir::cast;
using mlir::CastOpInterface;
using mlir::ChangeResult;
using mlir::ConstantIntRanges;
using mlir::ConversionConfig;
using mlir::ConversionPatternRewriter;
using mlir::ConversionTarget;
using mlir::createCanonicalizerPass;
using mlir::createConvertLinalgToLoopsPass;
using mlir::createConvertToLLVMPass;
using mlir::createCSEPass;
using mlir::createReconcileUnrealizedCastsPass;
using mlir::createSCFToControlFlowPass;
using mlir::DataFlowConfig;
using mlir::DataFlowSolver;
using mlir::DataLayout;
using mlir::DataLayoutSpecInterface;
using mlir::DefaultTimingManager;
using mlir::DenseElementsAttr;
using mlir::DenseI64ArrayAttr;
using mlir::DenseIntElementsAttr;
using mlir::DenseMap;
using mlir::DenseSet;
using mlir::DominanceInfo;
using mlir::Diagnostic;
using mlir::DiagnosticSeverity;
using mlir::Dialect;
using mlir::DialectInlinerInterface;
using mlir::DialectRegistry;
using mlir::DictionaryAttr;
using mlir::dyn_cast;
using mlir::dyn_cast_or_null;
using mlir::emitError;
using mlir::emitRemark;
using mlir::eraseUnreachableBlocks;
using mlir::failed;
using mlir::failure;
using mlir::FailureOr;
using mlir::FileLineColLoc;
using mlir::FlatSymbolRefAttr;
using mlir::Float64Type;
using mlir::FloatAttr;
using mlir::FloatType;
using mlir::FrozenRewritePatternSet;
using mlir::function_ref;
using mlir::FunctionOpInterface;
using mlir::FunctionType;
using mlir::FusedLoc;
using mlir::GenericLatticeAnchorBase;
using mlir::get;
using mlir::getAffineDimExpr;
using mlir::getConstantIntValue;
using mlir::getType;
using mlir::getUsedValuesDefinedAbove;
using mlir::GreedyRewriteConfig;
using mlir::GreedyRewriteStrictness;
using mlir::GreedySimplifyRegionLevel;
using mlir::IndexType;
using mlir::InferIntRangeInterface;
using mlir::InferTypeOpInterface;
using mlir::InFlightDiagnostic;
using mlir::inlineCall;
using mlir::Inliner;
using mlir::InlinerConfig;
using mlir::InlinerInterface;
using mlir::IntegerAttr;
using mlir::IntegerType;
using mlir::IntegerValueRange;
using mlir::InvocationBounds;
using mlir::IRMapping;
using mlir::IRRewriter;
using mlir::IRUnit;
using mlir::isa;
using mlir::isa_and_nonnull;
using mlir::isa_and_present;
using mlir::isMemoryEffectFree;
using mlir::isOpTriviallyDead;
using mlir::isSpeculatable;
using mlir::LLVMTypeConverter;
using mlir::Location;
using mlir::LocationAttr;
using mlir::LogicalResult;
using mlir::LoopLikeOpInterface;
using mlir::LowerToLLVMOptions;
using mlir::m_Constant;
using mlir::m_ConstantInt;
using mlir::matchPattern;
using mlir::MemoryEffectOpInterface;
using mlir::MemRefDescriptor;
using mlir::MemRefType;
using mlir::MLIRContext;
using mlir::ModuleAnalysisManager;
using mlir::ModuleOp;
using mlir::moveLoopInvariantCode;
using mlir::MutableArrayRef;
using mlir::NamedAttribute;
using mlir::NamedAttrList;
using mlir::NameLoc;
using mlir::NoneType;
using mlir::NonSuccessorInputReplacementBuilderFn;
using mlir::OpAsmDialectInterface;
using mlir::OpAsmParser;
using mlir::OpAsmPrinter;
using mlir::OpBuilder;
using mlir::OpConversionPattern;
using mlir::OperandRange;
using mlir::Operation;
using mlir::OperationEquivalence;
using mlir::OperationName;
using mlir::OperationState;
using mlir::OpFoldResult;
using mlir::OpOperand;
using mlir::OpPassManager;
using mlir::OpPrintingFlags;
using mlir::OpResult;
using mlir::OpRewritePattern;
using mlir::OptionalParseResult;
using mlir::OwningOpRef;
using mlir::parsePassPipeline;
using mlir::ParserConfig;
using mlir::ParseResult;
using mlir::parseSourceFile;
using mlir::Pass;
using mlir::PassDisplayMode;
using mlir::PassExecutionAction;
using mlir::PassManager;
using mlir::PassPipelineRegistration;
using mlir::Pattern;
using mlir::PatternRewriter;
using mlir::populateCallOpTypeConversionPattern;
using mlir::populateFunctionOpInterfaceTypeConversionPattern;
using mlir::populateRegionBranchOpInterfaceCanonicalizationPatterns;
using mlir::populateRegionBranchOpInterfaceInliningPattern;
using mlir::populateReturnOpTypeConversionPattern;
using mlir::ProgramPoint;
using mlir::RankedTensorType;
using mlir::raw_ostream;
using mlir::readBytecodeFile;
using mlir::Region;
using mlir::RegionBranchOpInterface;
using mlir::RegionBranchPoint;
using mlir::RegionBranchSuccessorMapping;
using mlir::RegionBranchTerminatorOpInterface;
using mlir::RegionSuccessor;
using mlir::registerAllDialects;
using mlir::registerAllExtensions;
using mlir::registerAllPasses;
using mlir::registerAsmPrinterCLOptions;
using mlir::registerBuiltinDialectTranslation;
using mlir::registerDefaultTimingManagerCLOptions;
using mlir::RegisteredOperationName;
using mlir::registerLLVMDialectTranslation;
using mlir::registerMLIRContextCLOptions;
using mlir::registerPassManagerCLOptions;
using mlir::ResultRange;
using mlir::RewritePatternSet;
using mlir::RewriterBase;
using mlir::SelfOwningTypeID;
using mlir::SetIntLatticeFn;
using mlir::SetIntRangeFn;
using mlir::SetVector;
using mlir::ShapedType;
using mlir::SmallVector;
using mlir::SmallVectorImpl;
using mlir::SMLoc;
using mlir::SourceMgrDiagnosticHandler;
using mlir::StringAttr;
using mlir::StringLiteral;
using mlir::StringRef;
using mlir::StringSet;
using mlir::StringSwitch;
using mlir::succeeded;
using mlir::success;
using mlir::SymbolRefAttr;
using mlir::SymbolTable;
using mlir::SymbolTableCollection;
using mlir::TilingInterface;
using mlir::TimingScope;
using mlir::TokenType;
using mlir::toString;
using mlir::translateModuleToLLVMIR;
using mlir::Twine;
using mlir::Type;
using mlir::TypeAttr;
using mlir::TypeConverter;
using mlir::TypedAttr;
using mlir::TypeID;
using mlir::TypeRange;
using mlir::TypeSwitch;
using mlir::UnitAttr;
using mlir::UnknownLoc;
using mlir::UnrealizedConversionCastOp;
using mlir::Value;
using mlir::ValueBoundsConstraintSet;
using mlir::ValueRange;
using mlir::VectorType;
using mlir::visitUsedValuesDefinedAbove;
using mlir::WalkOrder;
using mlir::WalkResult;
using mlir::writeBytecodeToFile;
using mlir::operator!;
using mlir::operator!=;
using mlir::operator&;
using mlir::operator&=;
using mlir::operator*;
using mlir::operator+;
using mlir::operator-;
using mlir::operator/;
using mlir::operator<<;
using mlir::operator<<=;
using mlir::operator==;
using mlir::operator>>;
using mlir::operator>>=;
using mlir::operator^;
using mlir::operator^=;
using mlir::operator|;
using mlir::operator|=;
using mlir::operator~;
} // namespace mlir

export namespace mlir::LLVM {
using mlir::LLVM::AddressOfOp;
using mlir::LLVM::AddrSpaceCastOp;
using mlir::LLVM::AllocaOp;
using mlir::LLVM::AndOp;
using mlir::LLVM::bitEnumContainsAny;
using mlir::LLVM::BrOp;
using mlir::LLVM::CallIntrinsicOp;
using mlir::LLVM::CallOp;
using mlir::LLVM::CondBrOp;
using mlir::LLVM::ConstantOp;
using mlir::LLVM::ConstantRangeAttr;
using mlir::LLVM::ExpectOp;
using mlir::LLVM::ExtractValueOp;
using mlir::LLVM::GEPArg;
using mlir::LLVM::GEPNoWrapFlags;
using mlir::LLVM::GEPOp;
using mlir::LLVM::GlobalOp;
using mlir::LLVM::ICmpOp;
using mlir::LLVM::ICmpPredicate;
using mlir::LLVM::InsertValueOp;
using mlir::LLVM::IntToPtrOp;
using mlir::LLVM::Linkage;
using mlir::LLVM::LLVMArrayType;
using mlir::LLVM::LLVMDialect;
using mlir::LLVM::LLVMFuncOp;
using mlir::LLVM::LLVMFunctionType;
using mlir::LLVM::LLVMPointerType;
using mlir::LLVM::LLVMStructType;
using mlir::LLVM::LLVMVoidType;
using mlir::LLVM::LoadOp;
using mlir::LLVM::MulOp;
using mlir::LLVM::PoisonAttr;
using mlir::LLVM::PoisonOp;
using mlir::LLVM::PtrToIntOp;
using mlir::LLVM::ReturnOp;
using mlir::LLVM::SAddWithOverflowOp;
using mlir::LLVM::SelectOp;
using mlir::LLVM::SMulWithOverflowOp;
using mlir::LLVM::SSubWithOverflowOp;
using mlir::LLVM::StoreOp;
using mlir::LLVM::SwitchOp;
using mlir::LLVM::TargetAttr;
using mlir::LLVM::TargetAttrInterface;
using mlir::LLVM::TargetFeaturesAttr;
using mlir::LLVM::TypeToLLVMIRTranslator;
using mlir::LLVM::UndefOp;
using mlir::LLVM::UnreachableOp;
using mlir::LLVM::ZeroOp;
using mlir::LLVM::operator&;
using mlir::LLVM::operator&=;
using mlir::LLVM::operator^;
using mlir::LLVM::operator^=;
using mlir::LLVM::operator|;
using mlir::LLVM::operator|=;
using mlir::LLVM::operator~;
} // namespace mlir::LLVM

export namespace mlir::LLVM::cconv {
using mlir::LLVM::cconv::CConv;
} // namespace mlir::LLVM::cconv

export namespace mlir::LLVM::detail {
using mlir::LLVM::detail::getTargetMachine;
using mlir::LLVM::detail::initializeBackendsOnce;
} // namespace mlir::LLVM::detail

export namespace mlir::LLVM::tailcallkind {
using mlir::LLVM::tailcallkind::TailCallKind;
} // namespace mlir::LLVM::tailcallkind

export namespace mlir::MemoryEffects {
using mlir::MemoryEffects::Allocate;
using mlir::MemoryEffects::Effect;
using mlir::MemoryEffects::EffectInstance;
using mlir::MemoryEffects::Free;
using mlir::MemoryEffects::Read;
using mlir::MemoryEffects::Write;
} // namespace mlir::MemoryEffects

export namespace mlir::OpTrait {
using mlir::OpTrait::ConstantLike;
using mlir::OpTrait::Elementwise;
using mlir::OpTrait::HasRecursiveMemoryEffects;
using mlir::OpTrait::IsIsolatedFromAbove;
using mlir::OpTrait::IsTerminator;
using mlir::OpTrait::SymbolTable;
using mlir::OpTrait::TraitBase;
} // namespace mlir::OpTrait

export namespace mlir::SideEffects {
using mlir::SideEffects::AutomaticAllocationScopeResource;
using mlir::SideEffects::DefaultResource;
using mlir::SideEffects::Effect;
using mlir::SideEffects::EffectInstance;
using mlir::SideEffects::Resource;
} // namespace mlir::SideEffects

export namespace mlir::Speculation {
using mlir::Speculation::Speculatability;
} // namespace mlir::Speculation

export namespace mlir::arith {
using mlir::arith::AddIOp;
using mlir::arith::AndIOp;
using mlir::arith::ArithDialect;
using mlir::arith::bitEnumContainsAny;
using mlir::arith::CeilDivUIOp;
using mlir::arith::CmpIOp;
using mlir::arith::CmpIPredicate;
using mlir::arith::ConstantIndexOp;
using mlir::arith::ConstantOp;
using mlir::arith::DivSIOp;
using mlir::arith::DivUIOp;
using mlir::arith::ExtSIOp;
using mlir::arith::ExtUIOp;
using mlir::arith::IndexCastOp;
using mlir::arith::IndexCastUIOp;
using mlir::arith::IntegerOverflowFlags;
using mlir::arith::invertPredicate;
using mlir::arith::MaxSIOp;
using mlir::arith::MaxUIOp;
using mlir::arith::MinSIOp;
using mlir::arith::MinUIOp;
using mlir::arith::MulIOp;
using mlir::arith::OrIOp;
using mlir::arith::populateIntRangeNarrowingPatterns;
using mlir::arith::RemSIOp;
using mlir::arith::RemUIOp;
using mlir::arith::SelectOp;
using mlir::arith::ShLIOp;
using mlir::arith::ShRSIOp;
using mlir::arith::ShRUIOp;
using mlir::arith::SubIOp;
using mlir::arith::TruncIOp;
using mlir::arith::XOrIOp;
using mlir::arith::operator&;
using mlir::arith::operator&=;
using mlir::arith::operator^;
using mlir::arith::operator^=;
using mlir::arith::operator|;
using mlir::arith::operator|=;
using mlir::arith::operator~;
} // namespace mlir::arith

export namespace mlir::cf {
using mlir::cf::ControlFlowDialect;
} // namespace mlir::cf

export namespace mlir::dataflow {
using mlir::dataflow::AbstractSparseForwardDataFlowAnalysis;
using mlir::dataflow::AbstractSparseLattice;
using mlir::dataflow::ConstantValue;
using mlir::dataflow::DeadCodeAnalysis;
using mlir::dataflow::Executable;
using mlir::dataflow::IntegerRangeAnalysis;
using mlir::dataflow::IntegerValueRangeLattice;
using mlir::dataflow::Lattice;
using mlir::dataflow::loadBaselineAnalyses;
using mlir::dataflow::PredecessorState;
using mlir::dataflow::SparseConstantPropagation;
using mlir::dataflow::SparseForwardDataFlowAnalysis;
} // namespace mlir::dataflow

export namespace mlir::func {
using mlir::func::CallIndirectOp;
using mlir::func::CallOp;
using mlir::func::ConstantOp;
using mlir::func::FuncDialect;
using mlir::func::FuncOp;
using mlir::func::ReturnOp;
} // namespace mlir::func

export namespace mlir::linalg {
using mlir::linalg::GenericOp;
using mlir::linalg::hasOnlyScalarElementwiseOp;
using mlir::linalg::IndexOp;
using mlir::linalg::isParallelIterator;
using mlir::linalg::LinalgDialect;
using mlir::linalg::VectorizationResult;
using mlir::linalg::vectorize;
using mlir::linalg::vectorizeOpPrecondition;
using mlir::linalg::YieldOp;
} // namespace mlir::linalg

export namespace mlir::math {
using mlir::math::IsFiniteOp;
using mlir::math::MathDialect;
} // namespace mlir::math

export namespace mlir::memref {
using mlir::memref::AllocaOp;
using mlir::memref::DimOp;
using mlir::memref::LoadOp;
using mlir::memref::MemRefDialect;
using mlir::memref::StoreOp;
using mlir::memref::SubViewOp;
} // namespace mlir::memref

export namespace mlir::presburger {
using mlir::presburger::BoundType;
using mlir::presburger::IntegerPolyhedron;
using mlir::presburger::PresburgerSpace;
} // namespace mlir::presburger

export namespace mlir::remark {
using mlir::remark::add;
using mlir::remark::analysis;
using mlir::remark::enableOptimizationRemarks;
using mlir::remark::metric;
using mlir::remark::missed;
using mlir::remark::passed;
using mlir::remark::reason;
using mlir::remark::RemarkCategories;
using mlir::remark::RemarkEmittingPolicyAll;
using mlir::remark::RemarkOpts;
} // namespace mlir::remark

export namespace mlir::remark::detail {
using mlir::remark::detail::InFlightRemark;
using mlir::remark::detail::LLVMRemarkStreamer;
using mlir::remark::detail::MLIRRemarkStreamerBase;
} // namespace mlir::remark::detail

export namespace mlir::scf {
using mlir::scf::ConditionOp;
using mlir::scf::ForOp;
using mlir::scf::IfOp;
using mlir::scf::IndexSwitchOp;
using mlir::scf::peelForLoopAndSimplifyBounds;
using mlir::scf::populateSCFStructuralTypeConversionsAndLegality;
using mlir::scf::populateUpliftWhileToForPatterns;
using mlir::scf::SCFTilingOptions;
using mlir::scf::SCFTilingResult;
using mlir::scf::tileUsingSCF;
using mlir::scf::WhileOp;
using mlir::scf::YieldOp;
} // namespace mlir::scf

export namespace mlir::tracing {
using mlir::tracing::Action;
using mlir::tracing::ActionImpl;
using mlir::tracing::DebugConfig;
using mlir::tracing::DebugCounter;
using mlir::tracing::InstallDebugHandler;
using mlir::tracing::TagBreakpointManager;
} // namespace mlir::tracing

export namespace mlir::ub {
using mlir::ub::PoisonAttr;
using mlir::ub::PoisonAttrInterface;
using mlir::ub::PoisonOp;
using mlir::ub::UBDialect;
using mlir::ub::UnreachableOp;
} // namespace mlir::ub

export namespace mlir::utils {
using mlir::utils::IteratorType;
} // namespace mlir::utils

export namespace mlir::vector {
using mlir::vector::populateDropUnitDimWithShapeCastPatterns;
using mlir::vector::populateVectorMaskLoweringPatternsForSideEffectingOps;
using mlir::vector::populateVectorTransferPermutationMapLoweringPatterns;
using mlir::vector::VectorDialect;
} // namespace mlir::vector

export namespace llvm {
using llvm::alignTo;
using llvm::all_of;
using llvm::all_of_zip;
using llvm::any;
using llvm::any_of;
using llvm::APFloat;
using llvm::APInt;
using llvm::append_range;
using llvm::APSInt;
using llvm::AreStatisticsEnabled;
using llvm::Argument;
using llvm::ArrayRef;
using llvm::ArrayType;
using llvm::AttributeList;
using llvm::bit_cast;
using llvm::BitVector;
using llvm::cast;
using llvm::CGSCCAnalysisManager;
using llvm::checkedMul;
using llvm::CodeGenFileType;
using llvm::CodeGenOptLevel;
using llvm::Constant;
using llvm::ConstantArray;
using llvm::ConstantDataArray;
using llvm::ConstantStruct;
using llvm::consumeError;
using llvm::copy;
using llvm::count;
using llvm::count_if;
using llvm::createStringError;
using llvm::DataLayout;
using llvm::DenseMap;
using llvm::DenseSet;
using llvm::DynamicAPInt;
using llvm::drop_begin;
using llvm::dyn_cast;
using llvm::dyn_cast_or_null;
using llvm::embedBufferInModule;
using llvm::enumerate;
using llvm::equal;
using llvm::erase;
using llvm::erase_if;
using llvm::Error;
using llvm::errs;
using llvm::exp;
using llvm::Expected;
using llvm::failed;
using llvm::failure;
using llvm::FailureOr;
using llvm::file_magic;
using llvm::fill;
using llvm::find;
using llvm::find_if;
using llvm::for_each;
using llvm::formatv;
using llvm::Function;
using llvm::function_ref;
using llvm::FunctionAnalysisManager;
using llvm::FunctionType;
using llvm::get;
using llvm::GetReturnInfo;
using llvm::getToken;
using llvm::GlobalObject;
using llvm::GlobalValue;
using llvm::GlobalVariable;
using llvm::GraphTraits;
using llvm::identify_magic;
using llvm::identity;
using llvm::InitializeNativeTarget;
using llvm::InitializeNativeTargetAsmParser;
using llvm::InitializeNativeTargetAsmPrinter;
using llvm::InitLLVM;
using llvm::IntegerType;
using llvm::interleaveComma;
using llvm::internalizeModule;
using llvm::is_contained;
using llvm::is_one_of;
using llvm::isa;
using llvm::isa_and_nonnull;
using llvm::IsaPred;
using llvm::isDigit;
using llvm::JITSymbolFlags;
using llvm::join;
using llvm::Linker;
using llvm::LLVMContext;
using llvm::LogicalResult;
using llvm::LoopAnalysisManager;
using llvm::MachineFunction;
using llvm::MachineModuleInfo;
using llvm::make_early_inc_range;
using llvm::make_filter_range;
using llvm::make_range;
using llvm::Mangler;
using llvm::map_to_vector;
using llvm::MapVector;
using llvm::MCSubtargetInfo;
using llvm::MDString;
using llvm::MemoryBuffer;
using llvm::MemoryBufferRef;
using llvm::MinAlign;
using llvm::Module;
using llvm::ModuleAnalysisManager;
using llvm::move;
using llvm::MutableArrayRef;
using llvm::nodes;
using llvm::none_of;
using llvm::OptimizationLevel;
using llvm::outs;
using llvm::parseBitcodeFile;
using llvm::ParseResult;
using llvm::PassBuilder;
using llvm::PipelineTuningOptions;
using llvm::PowerOf2Ceil;
using llvm::range_size;
using llvm::raw_fd_ostream;
using llvm::raw_ostream;
using llvm::raw_pwrite_stream;
using llvm::raw_string_ostream;
using llvm::replace;
using llvm::report_fatal_error;
using llvm::reverse;
using llvm::scc_begin;
using llvm::scope_exit;
using llvm::SetVector;
using llvm::SHA1;
using llvm::size;
using llvm::SmallDenseMap;
using llvm::SmallDenseSet;
using llvm::SmallPtrSet;
using llvm::SmallString;
using llvm::SmallVector;
using llvm::SmallVectorImpl;
using llvm::SMLoc;
using llvm::sort;
using llvm::SourceMgr;
using llvm::split;
using llvm::stable_sort;
using llvm::Statistic;
using llvm::StringLiteral;
using llvm::StringMap;
using llvm::StringRef;
using llvm::StringSet;
using llvm::StringSwitch;
using llvm::StripDebugInfo;
using llvm::SubtargetFeatures;
using llvm::succeeded;
using llvm::success;
using llvm::Target;
using llvm::TargetLowering;
using llvm::TargetMachine;
using llvm::TargetOptions;
using llvm::TargetRegistry;
using llvm::TargetSubtargetInfo;
using llvm::to_vector;
using llvm::ToolOutputFile;
using llvm::toString;
using llvm::transform;
using llvm::Triple;
using llvm::Twine;
using llvm::Type;
using llvm::TypeSwitch;
using llvm::unique;
using llvm::Use;
using llvm::Value;
using llvm::WriteBitcodeToFile;
using llvm::zip;
using llvm::zip_equal;
using llvm::operator!;
using llvm::operator!=;
using llvm::operator&;
using llvm::operator&=;
using llvm::operator*;
using llvm::operator+;
using llvm::operator+=;
using llvm::operator-;
using llvm::operator<;
using llvm::operator<<;
using llvm::operator<<=;
using llvm::operator<=;
using llvm::operator==;
using llvm::operator>;
using llvm::operator>=;
using llvm::operator>>;
using llvm::operator>>=;
using llvm::operator^;
using llvm::operator^=;
using llvm::operator|;
using llvm::operator|=;
using llvm::operator~;
} // namespace llvm

export namespace llvm::CallingConv {
using llvm::CallingConv::ID;
using llvm::CallingConv::Tail;
} // namespace llvm::CallingConv

export namespace llvm::FPOpFusion {
using llvm::FPOpFusion::Strict;
} // namespace llvm::FPOpFusion

export namespace llvm::ISD {
using llvm::ISD::OutputArg;
} // namespace llvm::ISD

export namespace llvm::orc {
using llvm::orc::absoluteSymbols;
using llvm::orc::DynamicLibrarySearchGenerator;
using llvm::orc::ExecutorAddr;
using llvm::orc::JITTargetMachineBuilder;
using llvm::orc::LLJIT;
using llvm::orc::LLJITBuilder;
using llvm::orc::setUpInactivePlatform;
using llvm::orc::SymbolMap;
using llvm::orc::SymbolNameSet;
using llvm::orc::SymbolStringPtr;
using llvm::orc::ThreadSafeModule;
} // namespace llvm::orc

export namespace llvm::PICLevel {
using llvm::PICLevel::BigPIC;
} // namespace llvm::PICLevel

export namespace llvm::PIELevel {
using llvm::PIELevel::Large;
} // namespace llvm::PIELevel

export namespace llvm::Reloc {
using llvm::Reloc::PIC_;
} // namespace llvm::Reloc

export namespace llvm::cl {
using llvm::cl::CommaSeparated;
using llvm::cl::desc;
using llvm::cl::getRegisteredOptions;
using llvm::cl::init;
using llvm::cl::list;
using llvm::cl::NotHidden;
using llvm::cl::opt;
using llvm::cl::Option;
using llvm::cl::ParseCommandLineOptions;
using llvm::cl::Positional;
} // namespace llvm::cl

export namespace llvm::legacy {
using llvm::legacy::PassManager;
} // namespace llvm::legacy

export namespace llvm::object {
using llvm::object::Archive;
using llvm::object::IRObjectFile;
using llvm::object::ObjectFile;
using llvm::object::SectionRef;
} // namespace llvm::object

export namespace llvm::remarks {
using llvm::remarks::Format;
} // namespace llvm::remarks

export namespace llvm::sys {
using llvm::sys::getHostCPUFeatures;
using llvm::sys::getHostCPUName;
using llvm::sys::getProcessTriple;
} // namespace llvm::sys

export namespace llvm::sys::fs {
using llvm::sys::fs::OF_None;
} // namespace llvm::sys::fs

export namespace llvm::sys::path {
using llvm::sys::path::append;
using llvm::sys::path::replace_extension;
} // namespace llvm::sys::path

// Re-exports only, as libc++'s own std module does: nothing is added to
// std.
// NOLINTBEGIN(bugprone-std-namespace-modification)
export namespace std {
using std::acos;
using std::advance;
using std::all_of;
using std::any_of;
using std::apply;
using std::arg;
using std::array;
using std::asin;
using std::atan;
using std::back_inserter;
using std::begin;
using std::bind;
using std::bit_cast;
using std::byte;
using std::ceil;
using std::convertible_to;
using std::copy;
using std::cos;
using std::count;
using std::count_if;
using std::ctime;
using std::data;
using std::dec;
using std::empty;
using std::end;
using std::endian;
using std::ends;
using std::equal;
using std::erase;
using std::error_code;
using std::exit;
using std::exp;
using std::exp2;
using std::expected;
using std::fill;
using std::find;
using std::fixed;
using std::floor;
using std::fmod;
using std::for_each;
using std::free;
using std::function;
using std::get;
using std::get_if;
using std::holds_alternative;
using std::identity;
using std::initializer_list;
using std::int32_t;
using std::int64_t;
using std::internal;
using std::is_same_v;
using std::iterator;
using std::ldexp;
using std::left;
using std::log;
using std::make_pair;
using std::make_shared;
using std::make_tuple;
using std::make_unique;
using std::map;
using std::max;
using std::memcpy;
using std::memmove;
using std::memset;
using std::milli;
using std::min;
using std::minmax;
using std::minus;
using std::move;
using std::next;
using std::none_of;
using std::nullopt;
using std::nullopt_t;
using std::numeric_limits;
using std::optional;
using std::pair;
using std::plus;
using std::pow;
using std::predicate;
using std::prev;
using std::ref;
using std::remove;
using std::replace;
using std::reverse;
using std::round;
using std::set;
using std::set_union;
using std::shared_ptr;
using std::sin;
using std::size;
using std::size_t;
using std::sort;
using std::sqrt;
using std::strerror;
using std::string;
using std::tan;
using std::tie;
using std::time;
using std::timespec;
using std::to_string;
using std::transform;
using std::trunc;
using std::tuple;
using std::tuple_element;
using std::tuple_size;
using std::uint32_t;
using std::uint64_t;
using std::uint8_t;
using std::uintptr_t;
using std::unexpected;
using std::unique;
using std::unique_ptr;
using std::unreachable;
using std::variant;
using std::vector;
using std::visit;
using std::operator!=;
using std::operator&;
using std::operator&=;
using std::operator*;
using std::operator+;
using std::operator-;
using std::operator/;
using std::operator<;
using std::operator<<;
using std::operator<<=;
using std::operator<=;
using std::operator<=>;
using std::operator==;
using std::operator>;
using std::operator>=;
using std::operator>>;
using std::operator>>=;
using std::operator^;
using std::operator^=;
using std::operator|;
using std::operator|=;
using std::operator~;
} // namespace std

export namespace std::chrono {
using std::chrono::ceil;
using std::chrono::duration;
using std::chrono::floor;
using std::chrono::nanoseconds;
using std::chrono::round;
using std::chrono::steady_clock;
using std::chrono::operator%;
using std::chrono::operator*;
using std::chrono::operator+;
using std::chrono::operator-;
using std::chrono::operator/;
using std::chrono::operator<;
using std::chrono::operator<=;
using std::chrono::operator<=>;
using std::chrono::operator==;
using std::chrono::operator>;
using std::chrono::operator>=;
} // namespace std::chrono

export namespace std::ranges {
using std::ranges::advance;
using std::ranges::all_of;
using std::ranges::any_of;
using std::ranges::begin;
using std::ranges::contains;
using std::ranges::copy;
using std::ranges::count;
using std::ranges::count_if;
using std::ranges::data;
using std::ranges::empty;
using std::ranges::end;
using std::ranges::ends_with;
using std::ranges::equal;
using std::ranges::fill;
using std::ranges::find;
using std::ranges::for_each;
using std::ranges::get;
using std::ranges::max;
using std::ranges::min;
using std::ranges::move;
using std::ranges::next;
using std::ranges::none_of;
using std::ranges::prev;
using std::ranges::range;
using std::ranges::remove;
using std::ranges::replace;
using std::ranges::reverse;
using std::ranges::set_union;
using std::ranges::size;
using std::ranges::sort;
using std::ranges::starts_with;
using std::ranges::transform;
using std::ranges::unique;
using std::ranges::operator|;
} // namespace std::ranges

export namespace std::ranges::views {
using std::ranges::views::all;
using std::ranges::views::reverse;
} // namespace std::ranges::views
// NOLINTEND(bugprone-std-namespace-modification)

// The C names of the integer types, which <cstdint> declares in the global
// namespace as well, re-exported as libc++'s std.compat module does.
export {
using ::int32_t;
using ::int64_t;
using ::size_t;
using ::uint32_t;
using ::uint64_t;
using ::uint8_t;
using ::uintptr_t;
}
