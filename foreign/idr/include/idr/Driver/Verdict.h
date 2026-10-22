// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a compilation comes to: its verdict, the one rule every step folds
// into and the exit status is computed from, and the outcome its report is
// written from.
#ifndef IDR_DRIVER_VERDICT_H
#define IDR_DRIVER_VERDICT_H

// The verdicts, each worse than the one before, their names in a report
// (EnumTraits<Verdict>::names) and the status each exits with
// (exitStatus): the specification's closed set, which the harness reads
// too. Every step that fails says why in the compilation's diagnostic
// engine, so a failure is always an error, and the worst seen wins. A
// refusal fails the step that makes it, so no step runs after it and no
// error is its cascade: an internal error beside a refusal is from the same
// step, the compiler's, which must be fixed before the refusal can be
// believed.
#include "idr/IR/Generated/Verdict.h.inc"

#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <cstdint>
#include <map>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace idr::driver {

// One compilation's outcome, which its diagnostics fold into
// (foldDiagnostics, the one fold of the verdict) and the report is written
// from: the worst verdict seen, each diagnostic's fields in the order the
// handler received them, and each pass statistic's sum. The diagnostic
// handler and the pass instrumentation update it from whichever thread
// they run on, so every member is read and written under one lock.
class Outcome {
public:
  void see(Verdict verdict) {
    std::lock_guard<std::mutex> lock(mutex);
    worst = std::max(worst, verdict);
  }

  Verdict verdict() const {
    std::lock_guard<std::mutex> lock(mutex);
    return worst;
  }

  void diagnostic(std::string fields) {
    std::lock_guard<std::mutex> lock(mutex);
    diagnostics.push_back(std::move(fields));
  }

  // Adds `by` to the statistic `key`, which is in the report from its first
  // count on, a count of zero included.
  void count(std::string key, uint64_t by) {
    std::lock_guard<std::mutex> lock(mutex);
    counts[std::move(key)] += by;
  }

  // `verdict: <name>`, then `diagnostic: <fields>` for each diagnostic, then
  // `statistic: <key>=<sum>` for each statistic in the bytewise order of
  // their keys, one per line.
  void write(llvm::raw_ostream &os) const {
    std::lock_guard<std::mutex> lock(mutex);
    os << "verdict: " << EnumTraits<Verdict>::names[std::to_underlying(worst)] << '\n';
    for (const std::string &fields : diagnostics)
      os << "diagnostic: " << fields << '\n';
    for (const auto &[key, sum] : counts)
      os << "statistic: " << key << '=' << sum << '\n';
  }

private:
  mutable std::mutex mutex;
  Verdict worst = Verdict::Accepted;
  std::vector<std::string> diagnostics;
  std::map<std::string, uint64_t> counts;
};

} // namespace idr::driver

#endif // IDR_DRIVER_VERDICT_H
