-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The one committed manifest of the generated files: the fingerprint of the
||| specification's sources, of the generator's, and of each file's text. No
||| generated file carries a stamp, so a file is rewritten only when its
||| bytes change and an edit recompiles only what it reaches; `make check`
||| regenerates and compares the files and this, so a hand edit fails, and
||| so does a generator changed without its outputs.
module IdrisMLIR.Spec.Generator.Manifest

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Generator.Render

import Data.Bits
import Data.List
import Data.List1

%default total

||| FNV-1a over 64 bits: a pure function of the bytes, the same on both
||| hosts, which wrap a 64-bit product alike.
export
fnv : Bits64 -> List Bits8 -> Bits64
fnv h [] = h
fnv h (b :: bs) = fnv (xor h (cast b) * 0x100000001b3) bs

||| A text's fingerprint, sixteen hexadecimal digits: of its UTF-8, since the
||| specification's text is ASCII but a source file's comment may not be,
||| and both hosts read files as UTF-8.
export
fingerprint : String -> String
fingerprint s = hex64 (integerToNat (cast {to = Integer} (fnv 0xcbf29ce484222325 (utf8 s))))

||| The manifest's text: the specification's and the generator's
||| fingerprints, then each output's, in the outputs' order.
export
manifest : (specification, generator : String) -> List (Path, String) -> String
manifest spec gen outs =
  render (["specification " ++ spec, "generator " ++ gen]
          ++ map (\(p, t) => fingerprint t ++ " " ++ pathText p) outs)

||| The manifest's path, beside the generated tree.
export
manifestPath : Path
manifestPath = "foreign" ::: ["idr", "generated.manifest"]
