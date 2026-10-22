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

||| The bytes of a character in UTF-8: the specification's text is ASCII, a
||| source file's comment may not be, and both hosts read files as UTF-8.
export
utf8 : Char -> List Bits64
utf8 c =
  let n = cast {to = Bits64} (ord c)
  in if n < 0x80 then [n]
     else if n < 0x800 then [0xC0 .|. shiftR n 6, 0x80 .|. (n .&. 0x3F)]
     else if n < 0x10000 then [0xE0 .|. shiftR n 12, 0x80 .|. (shiftR n 6 .&. 0x3F), 0x80 .|. (n .&. 0x3F)]
     else [0xF0 .|. shiftR n 18, 0x80 .|. (shiftR n 12 .&. 0x3F), 0x80 .|. (shiftR n 6 .&. 0x3F), 0x80 .|. (n .&. 0x3F)]

||| FNV-1a over 64 bits: a pure function of the bytes, the same on both
||| hosts, which wrap a 64-bit product alike.
export
fnv : Bits64 -> List Char -> Bits64
fnv h [] = h
fnv h (c :: cs) = fnv (step h (utf8 c)) cs
  where
    step : Bits64 -> List Bits64 -> Bits64
    step x [] = x
    step x (b :: bs) = step (xor x b * 0x100000001b3) bs

||| A text's fingerprint, sixteen hexadecimal digits.
export
fingerprint : String -> String
fingerprint s = hex64 (integerToNat (cast {to = Integer} (fnv 0xcbf29ce484222325 (unpack s))))

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
