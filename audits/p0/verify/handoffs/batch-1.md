<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L18, L02, L06, L04 follow-up handoffs (committed 81644c58, cc6d1894, 63a04a64, d1a8e833)

**L18, fifth pass (81644c58):**
- Workers make no types; tables are prepared by the serial decision.
- `givenAs` uses `data.reindex` where indices differ.
- Headers moved under `include/`.
- Five bugs fixed.
- Dispatched L18f for its closures-spec bugs and the reindex-before-tail
  question.

**L02, seventh pass (cc6d1894):**
- `cursorsInPlace` checks a tail call's cursors by position.
- Files split.
- Dispatched L02h for the interface-method declarations under patch 99
  and the null `cloneTypeWith`.

**L06, fifth pass (63a04a64):**
- `upstream/90` (operation equivalence), `91` (`getBufferType`) and `99`
  (`FunctionOpInterface` edits, C187).
- `scf` in `dialects.sh`.
- For INT: run `tools/dialects.sh generate`.
- Checks sent to L19e.

**L04, fifth pass (d1a8e833):**
- `walkFields` is a template member.
- The lifetime frame field is deleted.
- `Families.h` compiles in any include order.
- Accepted: `getNormalized` keeps upstream's `getChecked`-shaped
  `function_ref`.
- For INT: `lib/IR/CMakeLists.txt` still lists `DataBody.cpp`,
  `DataRemap.cpp` and `Layout/Fit.cpp`, all deleted.
