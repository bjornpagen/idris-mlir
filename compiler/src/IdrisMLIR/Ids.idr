-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Identifiers. Each kind of name is its own type, so a function name cannot
||| be used where a data type is meant. A name the compiler makes is derived
||| from the content it names, through XXH3's 128-bit hash, never from a
||| counter, so the order things are made in cannot reach the output.
module IdrisMLIR.Ids

import Data.Bits
import Data.Fin
import Data.List
import Data.Nat

%default total

||| A function instance, by its symbol (`Term.keyText`).
public export
record FnId where
  constructor MkFnId
  name : String

||| A monomorphic data instance, by its symbol: `<Idris name>[<type
||| arguments>]`, with the identity's hash where the print loses part of it.
public export
record DataId where
  constructor MkDataId
  name : String

||| A constructor of a data instance: the instance and the Idris full name.
public export
record ConId where
  constructor MkConId
  dataId : DataId
  name : String

||| An Idris name as it is printed: what the compiler reports, never what it
||| compares. It has `Show` and no `Eq`, so code outside the registry can
||| name a definition in a message but cannot key behaviour on it.
export
data Shown = MkShown String

export
shown : String -> Shown
shown = MkShown

export
Show Shown where
  show (MkShown s) = s

||| What a key's print keeps of the instance's identity: all of it, or not
||| all, with the low 64 bits of the identity's hash, which the symbol then
||| carries so that two identities that print alike are two symbols.
public export
data KeyPrint = Whole | Lossy Bits64

||| What a function or data instance is an instance of: the definition and
||| the compile-time values it was instantiated at, each the
||| alpha-normalized text the frontend prints, and what that print keeps of
||| the identity. Emit writes it as #idr.instance; its symbol is
||| `Term.keyText` of it.
public export
record InstanceKey where
  constructor MkInstanceKey
  origin : String            -- the definition's printed full name
  arguments : List String    -- each position up to the last that keys, alpha-normalized text or `-`
  print : KeyPrint

export Eq FnId where a == b = a.name == b.name
export Ord FnId where compare a b = compare a.name b.name
export Show FnId where show = (.name)

export Eq DataId where a == b = a.name == b.name
export Ord DataId where compare a b = compare a.name b.name
export Show DataId where show = (.name)

export Eq ConId where a == b = a.dataId == b.dataId && a.name == b.name
export Ord ConId where compare a b = compare (a.dataId, a.name) (b.dataId, b.name)
export Show ConId where show c = c.name

------------------------------------------------------------------------------
-- Names from content
------------------------------------------------------------------------------

||| XXH3's 128-bit hash of a byte sequence: its low and high 64 bits.
public export
record Hash128 where
  constructor MkHash128
  low : Bits64
  high : Bits64

-- XXH3's 128-bit variant, seed 0 and the default secret, as LLVM's
-- `xxh3_128bits` computes it, in plain Idris over Bits64, whose arithmetic
-- is modulo 2^64: the frontend runs on Chez at stage 0, where a primitive
-- of ours would have no meaning, and natively after, with the same values.
-- The word operations are base's `Data.Bits` on `Bits64`.

||| A shift's amount, below 64, as `Data.Bits` takes it.
amount : Bits64 -> Fin 64
amount s = restrict 63 (cast s)

shr : Bits64 -> Bits64 -> Bits64
shr x s = shiftR x (amount s)

shl : Bits64 -> Bits64 -> Bits64
shl x s = shiftL x (amount s)

xor64 : Bits64 -> Bits64 -> Bits64
xor64 = xor

and64 : Bits64 -> Bits64 -> Bits64
and64 = (.&.)

or64 : Bits64 -> Bits64 -> Bits64
or64 = (.|.)

prime32_1, prime32_2, prime32_3 : Bits64
prime32_1 = 0x9E3779B1
prime32_2 = 0x85EBCA77
prime32_3 = 0xC2B2AE3D

prime64_1, prime64_2, prime64_3, prime64_4, prime64_5 : Bits64
prime64_1 = 11400714785074694791
prime64_2 = 14029467366897019727
prime64_3 = 1609587929392839161
prime64_4 = 9650029242287828579
prime64_5 = 2870177450012600261

primeMx1, primeMx2 : Bits64
primeMx1 = 0x165667919E3779F9
primeMx2 = 0x9FB21C651E98DF25

||| The default secret, pseudorandom bytes taken from FARSH.
secret : List Bits8
secret =
  [ 0xb8, 0xfe, 0x6c, 0x39, 0x23, 0xa4, 0x4b, 0xbe, 0x7c, 0x01, 0x81, 0x2c, 0xf7, 0x21, 0xad, 0x1c
  , 0xde, 0xd4, 0x6d, 0xe9, 0x83, 0x90, 0x97, 0xdb, 0x72, 0x40, 0xa4, 0xa4, 0xb7, 0xb3, 0x67, 0x1f
  , 0xcb, 0x79, 0xe6, 0x4e, 0xcc, 0xc0, 0xe5, 0x78, 0x82, 0x5a, 0xd0, 0x7d, 0xcc, 0xff, 0x72, 0x21
  , 0xb8, 0x08, 0x46, 0x74, 0xf7, 0x43, 0x24, 0x8e, 0xe0, 0x35, 0x90, 0xe6, 0x81, 0x3a, 0x26, 0x4c
  , 0x3c, 0x28, 0x52, 0xbb, 0x91, 0xc3, 0x00, 0xcb, 0x88, 0xd0, 0x65, 0x8b, 0x1b, 0x53, 0x2e, 0xa3
  , 0x71, 0x64, 0x48, 0x97, 0xa2, 0x0d, 0xf9, 0x4e, 0x38, 0x19, 0xef, 0x46, 0xa9, 0xde, 0xac, 0xd8
  , 0xa8, 0xfa, 0x76, 0x3f, 0xe3, 0x9c, 0x34, 0x3f, 0xf9, 0xdc, 0xbb, 0xc7, 0xc7, 0x0b, 0x4f, 0x1d
  , 0x8a, 0x51, 0xe0, 0x4b, 0xcd, 0xb4, 0x59, 0x31, 0xc8, 0x9f, 0x7e, 0xc9, 0xd9, 0x78, 0x73, 0x64
  , 0xea, 0xc5, 0xac, 0x83, 0x34, 0xd3, 0xeb, 0xc3, 0xc5, 0x81, 0xa0, 0xff, 0xfa, 0x13, 0x63, 0xeb
  , 0x17, 0x0d, 0xdd, 0x51, 0xb7, 0xf0, 0xda, 0x49, 0xd3, 0x16, 0x55, 0x26, 0x29, 0xd4, 0x68, 0x9e
  , 0x2b, 0x16, 0xbe, 0x58, 0x7d, 0x47, 0xa1, 0xfc, 0x8f, 0xf8, 0xb8, 0xd1, 0x7a, 0xd0, 0x31, 0xce
  , 0x45, 0xcb, 0x3a, 0x8f, 0x95, 0x16, 0x04, 0x28, 0xaf, 0xd7, 0xfb, 0xca, 0xbb, 0x4b, 0x40, 0x7e ]

||| The little-endian word of the first `k` bytes (at most 8), missing
||| bytes counting as zero.
littleEndian : Nat -> List Bits8 -> Bits64
littleEndian k bytes = go 0 0 (take k bytes)
  where
    go : Bits64 -> Bits64 -> List Bits8 -> Bits64
    go acc _ [] = acc
    go acc at (b :: bs) = go (or64 acc (shl (cast b) at)) (at + 8) bs

||| The 64-bit little-endian word at an offset.
read64 : List Bits8 -> Nat -> Bits64
read64 bytes at = littleEndian 8 (drop at bytes)

||| The 32-bit little-endian word at an offset.
read32 : List Bits8 -> Nat -> Bits64
read32 bytes at = littleEndian 4 (drop at bytes)

||| The byte at an offset.
byteAt : List Bits8 -> Nat -> Bits64
byteAt bytes at = case drop at bytes of
  (b :: _) => cast b
  [] => 0

low32 : Bits64 -> Bits64
low32 x = and64 x 0xFFFFFFFF

||| The 128-bit product of two words, by 32-bit halves, as the reference's
||| portable path computes it.
mult128 : Bits64 -> Bits64 -> Hash128
mult128 lhs rhs =
  let loLo = low32 lhs * low32 rhs
      hiLo = shr lhs 32 * low32 rhs
      loHi = low32 lhs * shr rhs 32
      hiHi = shr lhs 32 * shr rhs 32
      cross = shr loLo 32 + low32 hiLo + loHi
      upper = shr hiLo 32 + shr cross 32 + hiHi
      lower = or64 (shl cross 32) (low32 loLo)
  in MkHash128 lower upper

||| The 128-bit product folded to 64 bits by exclusive or.
fold64 : Bits64 -> Bits64 -> Bits64
fold64 a b = let p = mult128 a b in xor64 p.low p.high

avalanche64 : Bits64 -> Bits64
avalanche64 h0 =
  let h1 = xor64 h0 (shr h0 33)
      h2 = h1 * prime64_2
      h3 = xor64 h2 (shr h2 29)
      h4 = h3 * prime64_3
  in xor64 h4 (shr h4 32)

avalanche3 : Bits64 -> Bits64
avalanche3 h0 =
  let h1 = xor64 h0 (shr h0 37)
      h2 = h1 * primeMx1
  in xor64 h2 (shr h2 32)

byteswap32 : Bits64 -> Bits64
byteswap32 x =
  or64 (or64 (shl (and64 x 0xFF) 24) (shl (and64 (shr x 8) 0xFF) 16))
       (or64 (shl (and64 (shr x 16) 0xFF) 8) (and64 (shr x 24) 0xFF))

byteswap64 : Bits64 -> Bits64
byteswap64 x = or64 (shl (byteswap32 (low32 x)) 32) (byteswap32 (shr x 32))

rotl32 : Bits64 -> Bits64 -> Bits64
rotl32 x r = low32 (or64 (shl x r) (shr (low32 x) (32 - r)))

len1to3 : List Bits8 -> Nat -> Hash128
len1to3 input n =
  let len = the Bits64 (cast n)
      c1 = byteAt input 0
      c2 = byteAt input (divNatNZ n 2 ItIsSucc)
      c3 = byteAt input (minus n 1)
      combinedl = or64 (or64 (shl c1 16) (shl c2 24)) (or64 c3 (shl len 8))
      combinedh = rotl32 (byteswap32 combinedl) 13
      bitflipl = xor64 (read32 secret 0) (read32 secret 4)
      bitfliph = xor64 (read32 secret 8) (read32 secret 12)
  in MkHash128 (avalanche64 (xor64 combinedl bitflipl)) (avalanche64 (xor64 combinedh bitfliph))

len4to8 : List Bits8 -> Nat -> Hash128
len4to8 input n =
  let len = the Bits64 (cast n)
      inputLo = read32 input 0
      inputHi = read32 input (minus n 4)
      input64 = inputLo + shl inputHi 32
      bitflip = xor64 (read64 secret 16) (read64 secret 24)
      keyed = xor64 input64 bitflip
      m = mult128 keyed (prime64_1 + shl len 2)
      high1 = m.high + shl m.low 1
      low1 = xor64 m.low (shr high1 3)
      low2 = xor64 low1 (shr low1 35)
      low3 = low2 * primeMx2
      low4 = xor64 low3 (shr low3 28)
  in MkHash128 low4 (avalanche3 high1)

len9to16 : List Bits8 -> Nat -> Hash128
len9to16 input n =
  let len = the Bits64 (cast n)
      bitflipl = xor64 (read64 secret 32) (read64 secret 40)
      bitfliph = xor64 (read64 secret 48) (read64 secret 56)
      inputLo = read64 input 0
      inputHi = read64 input (minus n 8)
      m = mult128 (xor64 (xor64 inputLo inputHi) bitflipl) prime64_1
      mLow = m.low + shl (len - 1) 54
      inputHi' = xor64 inputHi bitfliph
      mHigh = m.high + inputHi' + low32 inputHi' * (prime32_2 - 1)
      mLow' = xor64 mLow (byteswap64 mHigh)
      h = mult128 mLow' prime64_2
      hHigh = h.high + mHigh * prime64_2
  in MkHash128 (avalanche3 h.low) (avalanche3 hHigh)

len0to16 : List Bits8 -> Nat -> Hash128
len0to16 input n =
  if n > 8 then len9to16 input n
  else if n >= 4 then len4to8 input n
  else if n > 0 then len1to3 input n
  else MkHash128 (avalanche64 (xor64 (read64 secret 64) (read64 secret 72)))
                 (avalanche64 (xor64 (read64 secret 80) (read64 secret 88)))

mix16 : List Bits8 -> Nat -> Nat -> Bits64 -> Bits64
mix16 input at key seed =
  let lhs = xor64 (seed + read64 secret key) (read64 input at)
      rhs = xor64 ((0 - seed) + read64 secret (key + 8)) (read64 input (at + 8))
  in fold64 lhs rhs

mix32 : Hash128 -> List Bits8 -> Nat -> Nat -> Nat -> Bits64 -> Hash128
mix32 acc input at1 at2 key seed =
  let low1 = acc.low + mix16 input at1 key seed
      low2 = xor64 low1 (read64 input at2 + read64 input (at2 + 8))
      high1 = acc.high + mix16 input at2 (key + 16) seed
      high2 = xor64 high1 (read64 input at1 + read64 input (at1 + 8))
  in MkHash128 low2 high2

||| The last step of the mid-size hashes.
finishMid : Hash128 -> Bits64 -> Hash128
finishMid acc len =
  let low = acc.low + acc.high
      high = acc.low * prime64_1 + acc.high * prime64_4 + len * prime64_2
  in MkHash128 (avalanche3 low) (0 - avalanche3 high)

len17to128 : List Bits8 -> Nat -> Hash128
len17to128 input n =
  let acc0 = MkHash128 (cast n * prime64_1) 0
      acc1 = if n > 96 then mix32 acc0 input 48 (minus n 64) 96 0 else acc0
      acc2 = if n > 64 then mix32 acc1 input 32 (minus n 48) 64 0 else acc1
      acc3 = if n > 32 then mix32 acc2 input 16 (minus n 32) 32 0 else acc2
      acc4 = mix32 acc3 input 0 (minus n 16) 0 0
  in finishMid acc4 (cast n)

len129to240 : List Bits8 -> Nat -> Hash128
len129to240 input n =
  let acc0 = MkHash128 (cast n * prime64_1) 0
      acc1 = foldl (\acc, i => mix32 acc input (minus i 32) (minus i 16) (minus i 32) 0) acc0 [32, 64, 96, 128]
      acc2 = MkHash128 (avalanche3 acc1.low) (avalanche3 acc1.high)
      acc3 = foldl (\acc, i => mix32 acc input (minus i 32) (minus i 16) (3 + minus i 160) 0) acc2 (mids 160)
      -- The secret is 192 bytes; the reference reads the last pair from
      -- its minimum size, 136, less 17, less 16.
      acc4 = mix32 acc3 input (minus n 16) (minus n 32) (minus (minus 136 17) 16) 0
  in finishMid acc4 (cast n)
  where
    -- 160, 192, ... up to the length, inclusive.
    mids : Nat -> List Nat
    mids i = if i > n then [] else i :: assert_total (mids (i + 32))

||| The eight accumulators of the long hash.
Accs : Type
Accs = List Bits64

||| The words of a 64-byte stripe.
stripeWords : List Bits8 -> List Bits64
stripeWords bytes = map (\i => read64 bytes (8 * i)) [0 .. 7]

||| One 64-byte stripe accumulated, with the secret at `key`.
accumulate : Accs -> List Bits8 -> Nat -> Accs
accumulate acc stripe key = pairs acc (stripeWords stripe) (map (\i => read64 secret (key + 8 * i)) [0 .. 7])
  where
    product : Bits64 -> Bits64
    product k = low32 k * shr k 32
    pairs : List Bits64 -> List Bits64 -> List Bits64 -> List Bits64
    pairs (a0 :: a1 :: as) (d0 :: d1 :: ds) (k0 :: k1 :: ks) =
      (a0 + d1 + product (xor64 d0 k0)) :: (a1 + d0 + product (xor64 d1 k1)) :: pairs as ds ks
    pairs as _ _ = as

||| The accumulators scrambled with the secret at `key`.
scramble : Accs -> Nat -> Accs
scramble acc key = zipWith step acc (map (\i => read64 secret (key + 8 * i)) [0 .. 7])
  where
    step : Bits64 -> Bits64 -> Bits64
    step a k = xor64 (xor64 a (shr a 47)) k * prime32_1

||| The accumulators merged into one word, with the secret at `key`.
merge : Accs -> Nat -> Bits64 -> Bits64
merge acc key start = avalanche3 (go start 0 acc)
  where
    go : Bits64 -> Nat -> List Bits64 -> Bits64
    go r i (a0 :: a1 :: as) =
      go (r + fold64 (xor64 a0 (read64 secret (key + 16 * i))) (xor64 a1 (read64 secret (key + 16 * i + 8)))) (S i) as
    go r _ _ = r

||| The long hash: every whole stripe before the last byte, sixteen to a
||| block with a scramble after each block, then the last 64 bytes.
long : List Bits8 -> Nat -> Hash128
long input n =
  let acc0 = [prime32_3, prime64_1, prime64_2, prime64_3, prime64_4, prime32_2, prime64_5, prime32_1]
      stripes = divNatNZ (minus n 1) 64 ItIsSucc
      acc1 = run acc0 0 stripes input
      acc2 = accumulate acc1 (drop (minus n 64) input) (minus (minus 192 64) 7)
      len = the Bits64 (cast n)
  in MkHash128 (merge acc2 11 (len * prime64_1))
               (merge acc2 (minus (minus 192 64) 11) (complement (len * prime64_2)))
  where
    complement : Bits64 -> Bits64
    complement x = xor64 x 0xFFFFFFFFFFFFFFFF
    run : Accs -> Nat -> Nat -> List Bits8 -> Accs
    run acc t Z _ = acc
    run acc t (S more) bytes =
      let acc' = accumulate acc bytes (8 * modNatNZ t 16 ItIsSucc)
          acc'' = if modNatNZ (S t) 16 ItIsSucc == 0 then scramble acc' (minus 192 64) else acc'
      in run acc'' (S t) more (drop 64 bytes)

||| XXH3's 128-bit hash, seed 0 and the default secret, of the bytes.
export
xxh3_128 : List Bits8 -> Hash128
xxh3_128 input =
  let n = length input in
  if n <= 16 then len0to16 input n
  else if n <= 128 then len17to128 input n
  else if n <= 240 then len129to240 input n
  else long input n

||| The UTF-8 bytes of a string, each character encoded by its scalar value
||| in one to four bytes.
export
utf8 : String -> List Bits8
utf8 s = concatMap encode (unpack s)
  where
    byte : Int -> Bits8
    byte = cast
    encode : Char -> List Bits8
    encode c =
      let v = ord c in
      if v < 0x80 then [byte v]
      else if v < 0x800 then [byte (0xC0 + v `div` 0x40), byte (0x80 + v `mod` 0x40)]
      else if v < 0x10000 then [ byte (0xE0 + v `div` 0x1000), byte (0x80 + (v `div` 0x40) `mod` 0x40)
                               , byte (0x80 + v `mod` 0x40) ]
      else [ byte (0xF0 + v `div` 0x40000), byte (0x80 + (v `div` 0x1000) `mod` 0x40)
           , byte (0x80 + (v `div` 0x40) `mod` 0x40), byte (0x80 + v `mod` 0x40) ]

||| A word as exactly 16 lowercase hexadecimal digits, most significant
||| first.
export
hex16 : Bits64 -> String
hex16 x = pack (map digit (reverse [0 .. 15]))
  where
    digit : Nat -> Char
    digit i =
      let d = and64 (shr x (cast (4 * i))) 0xF in
      if d < 10 then chr (cast d + ord '0') else chr (cast d - 10 + ord 'a')

||| The low half of the hash of a key's text, as 16 hex digits.
export
contentHash : String -> String
contentHash key = hex16 (xxh3_128 (utf8 key)).low

||| The symbol of what `key` denotes, generated from `owner`:
||| `<owner>.<kind>.<hex16>`.
export
contentName : (owner : String) -> (kind : String) -> (key : String) -> String
contentName owner kind key = owner ++ "." ++ kind ++ "." ++ contentHash key
