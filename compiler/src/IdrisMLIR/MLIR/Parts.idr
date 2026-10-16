-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The parts of an attribute or type entry a dialect encodes natively, as
||| its bytecode records lay them out (IdrisMLIR.Encoding.*), which the
||| writer turns into bytes (IdrisMLIR.MLIR.Bytecode): a PrefixVarInt, a
||| zigzagged one, a byte, a string by its number in the string section, a
||| type or attribute by its entry's number, and an optional attribute,
||| 0 for none and 2n+1 for entry n.
module IdrisMLIR.MLIR.Parts

%default total

public export record TypeRef where { constructor MkTypeRef; number : Nat }
public export record AttrRef where { constructor MkAttrRef; number : Nat }
public export
data Part = VarInt Nat | SignedVarInt Integer | Flag Bool | Str String
          | TypeAt TypeRef | AttrAt AttrRef | OptionalAttrAt (Maybe AttrRef)
