# Dictionary fields and opaque types

Research note for the design of runtime dictionary fields. Status of claims:
**tested** (run here, with the stock Chez backend as the oracle), **read**
(the frontend's code), **conjecture**.

## What the compiler does

A constructor can hold an implementation (`Empty : Ord k => SortedDMap k v`
in Data.SortedMap). The frontend makes such a dictionary field a
compile-time value of the data instance (`Dictionaries`): it is erased from
the representation, every construction site of the constructor in the whole
program must give it one implementation, and a match binds the field to
that one. Two sites that give two implementations are rejected under
`unsupported (dictionary field)` (read).

Data instances are keyed by their type arguments in closed normal form, and
that normal form unfolds every definition whatever its visibility
(`normaliseAll`, Closed.idr), since `delType`, private to Data.SortedMap,
must reduce in `treeDelete`'s type (read).

## The case

`Lib` exports `Meters : Type` without its definition (`Meters = Int`), and a
named, descending `[ordM] Ord Meters`. `Main` builds a
`SortedMap Meters String` with `ordM` and a `SortedMap Int String` with the
Prelude's `Ord Int`. To Idris these are two types, and Chez prints the keys
of the first descending and of the second ascending. To the compiler,
`Meters` unfolds to `Int`: both maps are one data instance, whose `Empty`
would hold two implementations, and the program is rejected (tested,
`tests/reject/dictionary-field-opaque-type`). The rejection names `Meters`
as the definition the compiler sees through.

The rejection is sound: unequal implementations are never merged. A program
that builds the instance with one implementation only (the maps of `Meters`
alone, even handed out by `Lib` as maps of `Int`) compiles and prints what
Chez prints (tested, `tests/programs/data/sortedmap-opaque-key`).

## Why keying data by the type Idris sees is not sound

The obvious fix is to key data instances by the type as Idris sees it where
the value is used: `SortedMap Meters String` and `SortedMap Int String` as
two instances, each with its own dictionary. Inside `Lib` the two types are
one, so `Lib` can hand out a map of one as a map of the other:

```idris
export
asInts : SortedMap Meters String -> SortedMap Int String
asInts m = m
```

A map built with `ordM` then leaves `Lib` as a `SortedMap Int String`, and
still holds `ordM`. Chez runs every operation with the dictionary the value
holds: on `asInts down` (keys 10, 5, 1 built descending), `insert 7`
gives keys `[10, 7, 5, 1]` (tested). Keyed by the type `Main` sees, the
converted map would take the `SortedMap Int String` instance's dictionary,
`Ord Int`, and insert into a descending tree with an ascending order: a
silent miscompile. The two instance keys would disagree about the dictionary
the value holds, and nothing in the checked TT marks the conversion: it is
definitional equality inside `Lib`, not a term.

Unfolding definitions only where reduction is blocked (as for `delType`)
does not help either: `Meters` is not blocked anywhere, it is simply a
different type to `Main` than to `Lib`.

## Toward runtime dictionary fields

The sound way to give one data instance two implementations is to keep the
choice in the value, as Chez does, without making every method call an
unknown closure:

- **A defunctionalized tag.** Each dictionary field is a small runtime tag
  over the implementations the program's construction sites give it (here
  two: `ordM` and `Ord Int`), found by the same whole-program pass that
  finds them today. A match on the constructor binds the field to a case
  over the tag, and each method call on it becomes a match whose
  alternatives are the specialized calls, one per implementation
  (conjecture: with one implementation the tag is erased and nothing
  changes from today).
- **Where the tag lives.** In the constructor that holds the dictionary
  (`Empty`, `M`), as one more field: the representation changes only for
  data whose field has more than one implementation.
- **What it costs.** A branch per method call on a value whose instance has
  two implementations. Specialization by the tag's value where it is known
  (a map built and used in one function) removes it (conjecture).

Until then, the rejection stands and names the opaque definition.

## Related

- `d02b-merge` in the driver review: `mergeLeft` on any map is rejected
  with `unsupported (dependent field)`, the reverse case of one type split
  into two by its fields' types. Explicit, not a crash.
