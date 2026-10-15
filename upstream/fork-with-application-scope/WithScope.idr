module WithScope

record Box where
  constructor MkBox
  size : Nat

||| Calls its with block again, on a smaller value, from the right-hand side
||| itself: accepted at the pin.
direct : Nat -> Nat
direct n with (n)
  direct n | Z = Z
  direct n | (S k) = direct n | k

||| The same call from a local definition.
local : Nat -> Nat
local n with (n)
  local n | Z = Z
  local n | (S k) = go k
    where
      go : Nat -> Nat
      go m = local n | m

||| The same call in a record update's field.
update : Nat -> Box -> Box
update n b with (n)
  update n b | Z = b
  update n b | (S k) = { size := size (update n b | k) } b
