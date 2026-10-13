# The clones of @apply that fill its budget, and a chain of calls of them.
$1 == "//" && $2 == "clones" {
  for (k = 1; k <= 1024; k++) {
    print "  idr.func private @apply.spec" k "(%x: i64) -> i64 attributes {clone = #idr.clone<@apply.spec" k ", #idr.spec_key<\"apply\", [#idr.key_closure<\"add\", [" k " : i64]>, #idr.key_hole<0>]>>, total, no_inline} {"
    print "    %a = arith.constant " k " : i64"
    print "    %y = arith.addi %a, %x : i64"
    print "    return %y : i64"
    print "  }"
  }
  next
}
$1 == "//" && $2 == "calls" {
  for (k = 1; k <= 1024; k++)
    print "    %r" k " = idr.call @apply.spec" k "(%r" (k - 1) ") : (i64) -> i64"
  next
}
{ print }
