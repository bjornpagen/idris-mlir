// LLJIT for idr-eval, with the runtime bound by address.
// PIN(orc-lljit) — see PINS.md

#include "Eval/Jit.h"

#include "idr/Target.h"

#include "idris_rt.h"

#include "mlir/Target/LLVMIR/Export.h"

#include "llvm/ExecutionEngine/Orc/AbsoluteSymbols.h"
#include "llvm/ExecutionEngine/Orc/JITTargetMachineBuilder.h"
#include "llvm/Support/TargetSelect.h"

#include <cmath>
#include <cstring>

namespace idr::eval {

namespace {

template <typename T> std::pair<llvm::StringRef, llvm::orc::ExecutorAddr> bind(llvm::StringRef name, T *fn) {
  return {name, llvm::orc::ExecutorAddr::fromPtr(fn)};
}

using Unary = double (*)(double);
using Binary = double (*)(double, double);

// What lowered code may call: the runtime's entry points, the libm functions
// idr-lower calls (and fmod), and the memory functions LLVM emits.
llvm::SmallVector<std::pair<llvm::StringRef, llvm::orc::ExecutorAddr>> symbols() {
#define IDRIS_RT_BIND(name) bind(#name, &name)
  return {
      IDRIS_RT_BIND(idris_rt_cell), IDRIS_RT_BIND(idris_rt_arena_alloc),
      IDRIS_RT_BIND(idris_rt_eval_crash), IDRIS_RT_BIND(idris_rt_crash),
      IDRIS_RT_BIND(idris_rt_flush), IDRIS_RT_BIND(idris_rt_io_put_str),
      IDRIS_RT_BIND(idris_rt_io_put_char), IDRIS_RT_BIND(idris_rt_io_put_int_s),
      IDRIS_RT_BIND(idris_rt_io_put_int_u), IDRIS_RT_BIND(idris_rt_io_put_double),
      IDRIS_RT_BIND(idris_rt_io_get_char), IDRIS_RT_BIND(idris_rt_io_get_byte),
      IDRIS_RT_BIND(idris_rt_io_exit), IDRIS_RT_BIND(idris_rt_to_int),
      IDRIS_RT_BIND(idris_rt_double_head), IDRIS_RT_BIND(idris_rt_int_head_s),
      IDRIS_RT_BIND(idris_rt_int_head_u), IDRIS_RT_BIND(idris_rt_str_append),
      IDRIS_RT_BIND(idris_rt_str_cons), IDRIS_RT_BIND(idris_rt_str_from_char),
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
      IDRIS_RT_BIND(idris_rt_big_neg), IDRIS_RT_BIND(idris_rt_big_cmp),
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

} // namespace

std::unique_ptr<Jit> Jit::compile(mlir::ModuleOp module, llvm::ArrayRef<std::string> names,
                                  std::string &error) {
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  auto builder = llvm::orc::JITTargetMachineBuilder::detectHost();
  if (!builder) {
    error = describe(builder.takeError());
    return nullptr;
  }
  builder->setCodeGenOptLevel(llvm::CodeGenOptLevel::Aggressive);
  builder->getOptions() = targetOptions();
  auto machine = builder->createTargetMachine();
  if (!machine) {
    error = describe(machine.takeError());
    return nullptr;
  }
  auto context = std::make_unique<llvm::LLVMContext>();
  std::unique_ptr<llvm::Module> code = mlir::translateModuleToLLVMIR(module, *context);
  if (!code) {
    error = "the translation to LLVM IR failed";
    return nullptr;
  }
  code->setDataLayout((*machine)->createDataLayout());
  code->setTargetTriple((*machine)->getTargetTriple());
  optimize(*code, **machine);

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
  llvm::orc::SymbolMap table;
  for (auto [name, address] : symbols())
    table[result->jit->mangleAndIntern(name)] = {
        address, llvm::JITSymbolFlags::Exported | llvm::JITSymbolFlags::Callable};
  if (auto err = result->jit->getMainJITDylib().define(llvm::orc::absoluteSymbols(table))) {
    error = describe(std::move(err));
    return nullptr;
  }
  if (auto err = result->jit->addIRModule(
          llvm::orc::ThreadSafeModule(std::move(code), std::move(context)))) {
    error = describe(std::move(err));
    return nullptr;
  }
  for (const std::string &name : names) {
    auto address = result->jit->lookup(name);
    if (!address) {
      error = describe(address.takeError());
      return nullptr;
    }
    result->entries.push_back(address->toPtr<Entry>());
  }
  return result;
}

} // namespace idr::eval
