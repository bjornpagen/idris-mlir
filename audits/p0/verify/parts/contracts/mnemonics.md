<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Contract: op names (C11 as C158 settles it, 2026-10-21)

C11 says every mnemonic takes the prefix of the family it acts on: the
type or resource its operands are (D28's principle, named for what a
thing is). C158 settles the cases:

## Exceptions

- **Names a ruling fixes stand:** `idr.func`, `idr.call` (AGENTS.md,
  D22), and `idr.lifetime`, `idr.activation`, `idr.lend` (D90). The
  openers and lifetime ops of D93 take the `lifetime.` family:
  `idr.lifetime.home`, `.block`, `.stack`, `.chain`, `.forget`,
  `.reserve`, `.pack`, `.unpack`.
- **Ops that shape the IR and act on no type or resource stay bare,** as
  upstream's `func` and `scf` structure ops do: `idr.program`,
  `idr.return`, `idr.yield`, `idr.join`, `idr.loop`, `idr.jump`,
  `idr.constant`.

## Every other op takes its family

| today | name |
| --- | --- |
| con, field, tag, match | `data.con`, `data.field`, `data.tag`, `data.match` |
| match_lit | `lit.match` |
| closure, apply | `fn.closure`, `fn.apply` |
| delay, force, suspend | `lazy.delay`, `lazy.force`, `lazy.suspend` |
| dup, drop, share, take, unpack (of a cell) | `count.dup`, `count.drop`, `count.share`, `count.take`, `count.unpack` |
| divs, mods | `int.div_s`, `int.mod_s`; divu and modu are upstream `arith.divui` and `arith.remui` behind `check.nonzero` (L13: upstream holds their meaning) |
| shls, shlu, shrs, shru | `int.shl_s`, `int.shl_u`, `int.shr_s`, `int.shr_u` |
| to_char_s, to_char_u | `int.to_char_s`, `int.to_char_u` |
| big.pred | `nat.pred` |
| tabulate, fold_last, scan_last | `array.tabulate`, `array.fold_last`, `array.scan_last` |

## Placed within the rule by the op's owner

The owner names each in its family and lists the name in its handoff:
- **L13, as named:** `crash.cause` and `crash.message`; `platform.os`;
  `f64.to_int`, `int.head_s`, `int.head_u`, `f64.head`; `buffer.*`,
  `io.clock`, `io.file_time`, `str.of_errno`.
- **L12:** `tie_shape` (family `array.`, if it survives).

## Gone by rulings

`borrow` (D90), `tabulate_io`, `transpose` (C27), `may_loop` (the
divergence effect).

## The Idris side

The frontend prints names from the specification's generated modules
(D50), so it follows with no list of its own.
