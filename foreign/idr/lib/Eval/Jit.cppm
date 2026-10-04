// idr.eval:jit: compiling a round of compile-time evaluation: ORC's
// LLJIT, not mlir::ExecutionEngine, which aborts in a static musl process
// (PINS.md: orc-lljit). Nothing is linked from the process by name: the
// runtime's entry points, which idris-mlir-cc links natively, and the libc
// functions LLVM may call are bound through an absolute-symbol table, so the
// JITed code runs the same runtime and libm as executables.
//
// The code's memory is JITLink's in-process memory manager's (LLJIT's
// default on every target entry's triple): it maps each allocation readable
// and writable, links into it, then makes code readable and executable and
// never writable again (sys::Memory::protectMappedMemory, with the
// instruction cache flushed), all by the system's page. It never maps MAP_JIT
// memory, which Darwin needs only under the hardened runtime, and there only
// with an entitlement; whether this process may run what it wrote is the
// evaluation child's probe (refusesJitCode), so a system that refuses is an
// error that says so, not a child killed for no reason it gives.
// PIN(orc-lljit) — see PINS.md
module;
// The target entry's library calls, an X-macro, and the runtime's entry
// points and their macros, which no import carries; the C library's
// functions the JIT binds by address, from the global namespace.
#include "idr/TargetEntry.h"

#include "idris_rt.h"

#include <cmath>
#include <cstring>

export module idr.eval:jit;

import idr.mlir;
import idr.target;

export namespace idr::eval {

class Jit {
public:
  using Entry = void (*)(void *);

  // Translates `module` (LLVM dialect) to LLVM IR, optimizes it as
  // idris-mlir-cc optimizes executables for the host CPU,
  // compiles it once, and finds `entries`. On failure, says why in `error`.
  static std::unique_ptr<Jit> compile(mlir::ModuleOp module, llvm::ArrayRef<std::string> entries,
                                      std::string &error);

  llvm::ArrayRef<Entry> getEntries() const { return entries; }
  // A function of the same code that does nothing: what runs first, to see
  // that this process may run the code its JIT wrote.
  Entry getProbe() const { return probe; }
  // The address of the global `name` defines, or null when it defines none.
  const void *address(llvm::StringRef name) const;

private:
  // What the JIT's session reported while it linked (a failed mapping or
  // protection, say), which its lookups only summarize. It outlives the
  // session, which may report as it ends.
  std::string reported;
  std::unique_ptr<llvm::orc::LLJIT> jit;
  llvm::SmallVector<Entry> entries;
  Entry probe = nullptr;
};

} // namespace idr::eval

namespace idr::eval {

namespace {

template <typename T> std::pair<llvm::StringRef, llvm::orc::ExecutorAddr> bind(llvm::StringRef name, T *fn) {
  return {name, llvm::orc::ExecutorAddr::fromPtr(fn)};
}

using Unary = double (*)(double);
using Binary = double (*)(double, double);

// What lowered code may call: the runtime's entry points, the libm functions
// idr-lower calls (and fmod), and the memory functions LLVM emits on every
// target. What else LLVM emits for the target is the target entry's
// (libraryCalls).
llvm::SmallVector<std::pair<llvm::StringRef, llvm::orc::ExecutorAddr>> symbols() {
#define IDRIS_RT_BIND(name) bind(#name, &name)
  return {
      IDRIS_RT_BIND(idris_rt_cell), IDRIS_RT_BIND(idris_rt_arena_alloc),
      IDRIS_RT_BIND(idris_rt_eval_crash), IDRIS_RT_BIND(idris_rt_eval_tick),
      IDRIS_RT_BIND(idris_rt_crash), IDRIS_RT_BIND(idris_rt_flush),IDRIS_RT_BIND(idris_rt_io_put_str),
      IDRIS_RT_BIND(idris_rt_io_put_char), IDRIS_RT_BIND(idris_rt_io_put_int_s),
      IDRIS_RT_BIND(idris_rt_io_put_int_u), IDRIS_RT_BIND(idris_rt_io_put_double),
      IDRIS_RT_BIND(idris_rt_io_get_byte), IDRIS_RT_BIND(idris_rt_io_get_line),
      IDRIS_RT_BIND(idris_rt_io_write_bytes), IDRIS_RT_BIND(idris_rt_io_read_bytes),
      IDRIS_RT_BIND(idris_rt_io_eof),
      IDRIS_RT_BIND(idris_rt_to_int),
      IDRIS_RT_BIND(idris_rt_double_head), IDRIS_RT_BIND(idris_rt_int_head_s),
      IDRIS_RT_BIND(idris_rt_int_head_u), IDRIS_RT_BIND(idris_rt_str_append),
      IDRIS_RT_BIND(idris_rt_str_cons), IDRIS_RT_BIND(idris_rt_str_from_char),
      IDRIS_RT_BIND(idris_rt_str_alloc), IDRIS_RT_BIND(idris_rt_str_put_char),
      IDRIS_RT_BIND(idris_rt_str_put_str), IDRIS_RT_BIND(idris_rt_str_bytes_length),
      IDRIS_RT_BIND(idris_rt_str_is_ascii),
      IDRIS_RT_BIND(idris_rt_str_show_s), IDRIS_RT_BIND(idris_rt_str_show_u),
      IDRIS_RT_BIND(idris_rt_str_show_f64), IDRIS_RT_BIND(idris_rt_str_length),
      IDRIS_RT_BIND(idris_rt_str_index), IDRIS_RT_BIND(idris_rt_str_head),
      IDRIS_RT_BIND(idris_rt_str_tail), IDRIS_RT_BIND(idris_rt_str_substr),
      IDRIS_RT_BIND(idris_rt_str_reverse), IDRIS_RT_BIND(idris_rt_str_cmp),
      IDRIS_RT_BIND(idris_rt_str_to_double), IDRIS_RT_BIND(idris_rt_str_to_int),
      IDRIS_RT_BIND(idris_rt_big_add), IDRIS_RT_BIND(idris_rt_big_sub),
      IDRIS_RT_BIND(idris_rt_big_mul), IDRIS_RT_BIND(idris_rt_big_div),
      IDRIS_RT_BIND(idris_rt_big_mod), IDRIS_RT_BIND(idris_rt_big_and),
      IDRIS_RT_BIND(idris_rt_big_or), IDRIS_RT_BIND(idris_rt_big_xor),
      IDRIS_RT_BIND(idris_rt_big_neg), IDRIS_RT_BIND(idris_rt_big_pred),
      IDRIS_RT_BIND(idris_rt_nat_from_big), IDRIS_RT_BIND(idris_rt_big_cmp),
      IDRIS_RT_BIND(idris_rt_big_from_int_s), IDRIS_RT_BIND(idris_rt_big_from_int_u),
      IDRIS_RT_BIND(idris_rt_big_to_int), IDRIS_RT_BIND(idris_rt_big_from_double),
      IDRIS_RT_BIND(idris_rt_big_to_double), IDRIS_RT_BIND(idris_rt_big_show),
      IDRIS_RT_BIND(idris_rt_big_from_str),
      bind("exp", static_cast<Unary>(&::exp)), bind("log", static_cast<Unary>(&::log)),
      bind("pow", static_cast<Binary>(&::pow)), bind("sin", static_cast<Unary>(&::sin)),
      bind("cos", static_cast<Unary>(&::cos)), bind("tan", static_cast<Unary>(&::tan)),
      bind("asin", static_cast<Unary>(&::asin)), bind("acos", static_cast<Unary>(&::acos)),
      bind("atan", static_cast<Unary>(&::atan)), bind("sqrt", static_cast<Unary>(&::sqrt)),
      bind("floor", static_cast<Unary>(&::floor)), bind("ceil", static_cast<Unary>(&::ceil)),
      bind("exp2", static_cast<Unary>(&::exp2)), bind("fmod", static_cast<Binary>(&::fmod)),
      bind("ldexp", static_cast<double (*)(double, int)>(&::ldexp)),
      bind("memcpy", &::memcpy), bind("memmove", &::memmove), bind("memset", &::memset),
  };
#undef IDRIS_RT_BIND
}

std::string describe(llvm::Error error) { return llvm::toString(std::move(error)); }

constexpr llvm::StringLiteral probeName = "__idr_jit_probe";

// The probe, an entry that returns at once, added to the code it probes, so
// that it shares its pages and their protection.
void addProbe(mlir::ModuleOp module) {
  mlir::MLIRContext *ctx = module.getContext();
  mlir::OpBuilder b(ctx);
  b.setInsertionPointToEnd(module.getBody());
  auto type = mlir::LLVM::LLVMFunctionType::get(mlir::LLVM::LLVMVoidType::get(ctx),
                                                {mlir::LLVM::LLVMPointerType::get(ctx)});
  auto probe = mlir::LLVM::LLVMFuncOp::create(b, module.getLoc(), probeName, type);
  b.setInsertionPointToStart(probe.addEntryBlock(b));
  mlir::LLVM::ReturnOp::create(b, module.getLoc(), mlir::ValueRange{});
}

// The error of a lookup, with what the session reported as it failed: the
// lookup names the symbols it could not materialize, the report says why.
std::string describe(llvm::Error error, const std::string &reported) {
  std::string text = describe(std::move(error));
  return reported.empty() ? text : text + ": " + reported;
}

// The #llvm.target of the module or of the first module around it that has
// one: the program being evaluated.
mlir::LLVM::TargetAttr targetOf(mlir::Operation *op) {
  for (; op; op = op->getParentOp())
    if (auto target = op->getAttrOfType<mlir::LLVM::TargetAttr>(
            mlir::LLVM::LLVMDialect::getTargetAttrName()))
      return target;
  return {};
}

} // namespace

std::unique_ptr<Jit> Jit::compile(mlir::ModuleOp module, llvm::ArrayRef<std::string> names,
                                  std::string &error) {
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  // The code runs here, but is compiled for the program's target and CPU,
  // not this machine's: its frames, and so what a call spends of its stack
  // budget and whether it is evaluated, are then the same on every machine.
  // A module with no target (a test's) is compiled for this machine's
  // triple and the generic CPU, the triple's baseline.
  mlir::LLVM::TargetAttr target = targetOf(module);
  auto builder = target ? llvm::Expected<llvm::orc::JITTargetMachineBuilder>(
                              llvm::orc::JITTargetMachineBuilder(
                                  llvm::Triple(target.getTriple().getValue())))
                        : llvm::orc::JITTargetMachineBuilder::detectHost();
  if (!builder) {
    error = describe(builder.takeError());
    return nullptr;
  }
  std::string features =
      target && target.getFeatures() ? target.getFeatures().getFeaturesString() : "";
  // Code for a CPU with more than this one would stop on an illegal
  // instruction in the child.
  llvm::StringMap<bool> host = llvm::sys::getHostCPUFeatures();
  std::string lacking;
  for (const std::string &feature : llvm::SubtargetFeatures(features).getFeatures())
    if (auto it = host.find(llvm::StringRef(feature).drop_front()); feature.starts_with("+") &&
                                                                     it != host.end() && !it->second)
      lacking += " " + feature.substr(1);
  if (!lacking.empty()) {
    error = "compile-time evaluation runs code for " + target.getChip().str() +
            ", and this machine lacks" + lacking +
            " (compile with --cpu=native, or --no-eval)";
    return nullptr;
  }
  builder->setCPU(target ? target.getChip().str() : "generic");
  builder->getFeatures() = llvm::SubtargetFeatures(features);
  builder->setCodeGenOptLevel(llvm::CodeGenOptLevel::Aggressive);
  builder->getOptions() = target::targetOptions();
  auto machine = builder->createTargetMachine();
  if (!machine) {
    error = describe(machine.takeError());
    return nullptr;
  }
  addProbe(module);
  auto context = std::make_unique<llvm::LLVMContext>();
  std::unique_ptr<llvm::Module> code = mlir::translateModuleToLLVMIR(module, *context);
  if (!code) {
    error = "the translation to LLVM IR failed";
    return nullptr;
  }
  code->setDataLayout((*machine)->createDataLayout());
  code->setTargetTriple((*machine)->getTargetTriple());
  target::optimize(*code, **machine);

  auto made = llvm::orc::LLJITBuilder()
                  .setJITTargetMachineBuilder(std::move(*builder))
                  .setLinkProcessSymbolsByDefault(false)
                  .setPlatformSetUp(llvm::orc::setUpInactivePlatform)
                  .create();
  if (!made) {
    error = describe(made.takeError());
    return nullptr;
  }
  auto result = std::unique_ptr<Jit>(new Jit);
  result->jit = std::move(*made);
  std::string &reported = result->reported;
  result->jit->getExecutionSession().setErrorReporter([&reported](llvm::Error err) {
    reported += (reported.empty() ? "" : "; ") + describe(std::move(err));
  });
  llvm::orc::SymbolMap table;
  for (auto [name, address] : symbols())
    table[result->jit->mangleAndIntern(name)] = {
        address, llvm::JITSymbolFlags::Exported | llvm::JITSymbolFlags::Callable};
  if (auto err = result->jit->getMainJITDylib().define(llvm::orc::absoluteSymbols(table))) {
    error = describe(std::move(err));
    return nullptr;
  }
  // The library functions the target entry names, which LLVM's code for the
  // target calls beyond those (Darwin's bzero and __exp10, say): each is
  // bound from the process, which has a dynamic loader on every target that
  // names one, and no other process symbol is.
  llvm::orc::SymbolNameSet libraryCalls;
#define IDR_LIBRARY_CALL(name) libraryCalls.insert(result->jit->mangleAndIntern(name));
  IDRIS_MLIR_JIT_LIBRARY_CALLS(IDR_LIBRARY_CALL)
#undef IDR_LIBRARY_CALL
  if (!libraryCalls.empty()) {
    auto process = llvm::orc::DynamicLibrarySearchGenerator::GetForCurrentProcess(
        result->jit->getDataLayout().getGlobalPrefix(),
        [libraryCalls](const llvm::orc::SymbolStringPtr &name) { return libraryCalls.contains(name); });
    if (!process) {
      error = describe(process.takeError());
      return nullptr;
    }
    result->jit->getMainJITDylib().addGenerator(std::move(*process));
  }
  if (auto err = result->jit->addIRModule(
          llvm::orc::ThreadSafeModule(std::move(code), std::move(context)))) {
    error = describe(std::move(err));
    return nullptr;
  }
  for (const std::string &name : names) {
    auto address = result->jit->lookup(name);
    if (!address) {
      error = describe(address.takeError(), result->reported);
      return nullptr;
    }
    result->entries.push_back(address->toPtr<Entry>());
  }
  auto probe = result->jit->lookup(probeName);
  if (!probe) {
    error = describe(probe.takeError(), result->reported);
    return nullptr;
  }
  result->probe = probe->toPtr<Entry>();
  return result;
}

const void *Jit::address(llvm::StringRef name) const {
  auto found = jit->lookup(name);
  if (!found) {
    llvm::consumeError(found.takeError());
    return nullptr;
  }
  return found->toPtr<const void *>();
}

} // namespace idr::eval
