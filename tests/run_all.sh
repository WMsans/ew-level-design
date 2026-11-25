#!/bin/sh
# Run every headless test; exit 1 if any fails.  usage: sh tests/run_all.sh
cd "$(dirname "$0")/.." || exit 1
godot --headless --path . --import >/dev/null 2>&1
rc=0
for t in tests/test_*.gd; do
	out=$(timeout 120 godot --headless --path . --script "res://$t" 2>&1)
	echo "$out" | grep -E "  FAIL |SCRIPT ERROR" ; echo "$t: $(echo "$out" | grep -c '  ok ') ok, $(echo "$out" | grep -c '  FAIL') failed"
	echo "$out" | grep -q "FAILS: 0" || rc=1
done
exit $rc
