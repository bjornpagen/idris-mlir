# The stock Chez backend as an oracle: the same program, compiled by it,
# must print what this compiler's build printed and exit the same way.

# chez_agrees FIXTURE STDIN CRASH STATUS [OPTION...]: the IO program
# FIXTURE/Main.idr compiled by the stock Chez backend (with the idris2
# OPTIONs, such as `-p PACKAGE`) and run on STDIN prints what this
# compiler's build printed, $work/ours.out, and exits with its STATUS. CRASH
# is the cause of an expected crash, or empty; a crash's message is not
# compared, nor its exit status.
chez_agrees() {
  chez_fixture=$1
  chez_stdin=$2
  chez_crash=$3
  chez_ours_status=$4
  shift 4
  mkdir "$work/chez"
  copy_fixture "$chez_fixture" "$work/chez"
  (cd "$work/chez" && bounded "$idris2" --no-banner --no-color --no-prelude "$@" \
     --cg chez -o prog Main.idr) > "$work/chez.log" 2>&1
  chez_built=$?
  say "chez: compile exit $chez_built"
  if [ "$chez_built" -ne 0 ]; then
    show "$work/chez.log"
    return
  fi
  run_program chez "$work/chez/build/exec/prog" "$chez_stdin"
  chez_status=$ran
  chez_same=no
  if cmp -s "$work/ours.out" "$work/chez.out"; then
    chez_same=yes
  elif [ -n "$chez_crash" ]; then
    # Crash messages are not compared, and Chez writes its own to
    # stdout: after this compiler's output, or as an `ERROR: ` line before
    # the Prelude's buffered output.
    chez_bytes=$(wc -c < "$work/ours.out" | tr -d ' ')
    if head -c "$chez_bytes" "$work/chez.out" | cmp -s - "$work/ours.out"; then
      tail -c +"$((chez_bytes + 1))" "$work/chez.out" > "$work/chez.rest"
      if [ ! -s "$work/chez.rest" ] || [ "$(head -c 7 "$work/chez.rest")" = "ERROR: " ]; then
        chez_same=yes
      fi
    fi
    if [ "$chez_same" = no ] && sed '/^ERROR: /d' "$work/chez.out" | cmp -s - "$work/ours.out"; then
      chez_same=yes
    fi
  fi
  # On the lines `libm-lines` names (one number per line), the
  # outputs are libm results, musl's here and the host's in Chez, which may
  # differ by one unit in the last place where libm is not correctly
  # rounded.
  if [ "$chez_same" = no ] && [ -f "$chez_fixture/libm-lines" ] &&
     awk -v lines="$chez_fixture/libm-lines" '
       BEGIN { while ((getline n < lines) > 0) libm[n] = 1 }
       NR == FNR { ours[FNR] = $0; n1 = FNR; next }
       { n2 = FNR
         if ($0 == ours[FNR]) next
         if (!(FNR in libm)) exit 1
         a = ours[FNR] + 0; b = $0 + 0; m = (a < 0 ? -a : a); if ((b < 0 ? -b : b) > m) m = (b < 0 ? -b : b)
         d = a - b; if (d < 0) d = -d
         if (d > m * 2 ^ -52) exit 1 }
       END { if (n1 != n2) exit 1 }' "$work/ours.out" "$work/chez.out"; then
    chez_same=libm
  fi
  if [ "$chez_same" = libm ]; then
    if [ "$chez_status" -eq "$chez_ours_status" ]; then
      say "chez: same stdout, up to one ulp on the libm lines, and exit status"
    else
      say "chez: same stdout up to one ulp, but Chez exited $chez_status and this compiler $chez_ours_status"
    fi
  elif [ "$chez_same" = no ]; then
    say "chez: stdout differs (< this compiler, > Chez)"
    diff "$work/ours.out" "$work/chez.out" | head -n 20 | sed 's/^/  | /'
  elif [ -n "$chez_crash" ]; then
    say "chez: same stdout"
  elif [ "$chez_status" -eq "$chez_ours_status" ]; then
    say "chez: same stdout and exit status"
  else
    say "chez: same stdout, but Chez exited $chez_status and this compiler $chez_ours_status"
  fi
}
