// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One bin of the partition read back out of the optimized program's
// bitcode: a lazily read module keeps what the bin defines, the constants it
// holds a copy of and the declarations of what they name, and only those
// bodies are materialized. It reads the partition and nothing of how the
// partition was made.

#include "idr/Support/Worklist.h"
#include "idr/Target/Target.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Twine.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Error.h"

#include <optional>
#include <string>
#include <variant>
#include <vector>

using namespace llvm;
using idr::target::Partition;

Error Partition::extract(unsigned bin, Module &module) const {
  std::vector<GlobalValue *> at = positions(module);
  if (at.size() != symbols.size())
    return createStringError("internal error: bin " + binList[bin].name + " reads " +
                             Twine(at.size()) + " symbols from the bitcode, and the partition was "
                             "made of " + Twine(symbols.size()));
  // What the bin defines, the constants it holds a copy of, and what they
  // name of everything else, which it declares; the rest it drops.
  enum class Role : unsigned char { Drop, Own, Hold, Declare };
  // A symbol's role leaves Drop once, and only then does a held one enter
  // the worklist, so each enters once.
  std::vector<Role> role(at.size(), Role::Drop);
  idr::OnceWorklist<unsigned> work;
  for (unsigned symbol : members[bin]) {
    role[symbol] = Role::Own;
    work.push(symbol);
  }
  while (std::optional<unsigned> symbol = work.pop())
    for (unsigned named : symbols[*symbol].refs)
      if (role[named] == Role::Drop) {
        role[named] =
            std::holds_alternative<Copied>(symbols[named].home) ? Role::Hold : Role::Declare;
        if (role[named] == Role::Hold)
          work.push(named);
      }
  // Bodies first: what the bin does not define becomes a declaration, so
  // that materializing reads only the bin's own bodies. An alias or an ifunc
  // cannot be a declaration: one the bin names gives its uses to a
  // declaration of its value type under its name, and goes.
  for (unsigned symbol = 0; symbol < at.size(); ++symbol) {
    GlobalValue *value = at[symbol];
    if (role[symbol] == Role::Own || role[symbol] == Role::Hold)
      continue;
    if (auto *function = dyn_cast<Function>(value)) {
      if (!function->isDeclaration())
        function->deleteBody();
      function->setComdat(nullptr);
      continue;
    }
    if (auto *variable = dyn_cast<GlobalVariable>(value)) {
      if (variable->hasInitializer()) {
        variable->setInitializer(nullptr);
        variable->setComdat(nullptr);
        variable->setLinkage(GlobalValue::ExternalLinkage);
      }
      continue;
    }
    if (role[symbol] == Role::Declare) {
      std::string name = value->getName().str();
      value->setName("");
      GlobalValue *declared;
      if (auto *type = dyn_cast<FunctionType>(value->getValueType()))
        declared = Function::Create(type, GlobalValue::ExternalLinkage, value->getAddressSpace(),
                                    name, &module);
      else
        declared = new GlobalVariable(module, value->getValueType(), false,
                                      GlobalValue::ExternalLinkage, nullptr, name, nullptr,
                                      value->getThreadLocalMode(), value->getAddressSpace());
      declared->setVisibility(value->getVisibility());
      declared->setDSOLocal(value->isDSOLocal());
      value->replaceAllUsesWith(declared);
      role[symbol] = Role::Drop;
    }
    value->dropAllReferences();
  }
  if (Error error = module.materializeAll())
    return error;
  for (unsigned symbol = 0; symbol < at.size(); ++symbol) {
    if (role[symbol] != Role::Drop)
      continue;
    at[symbol]->removeDeadConstantUsers();
    if (!at[symbol]->use_empty())
      return createStringError("internal error: bin " + binList[bin].name + " still uses " +
                               at[symbol]->getName() + ", which it neither defines nor declares");
    at[symbol]->eraseFromParent();
  }
  // Module-level assembly is defined once, in the first bin.
  if (bin != 0)
    module.removeModuleInlineAsm();
  return Error::success();
}
