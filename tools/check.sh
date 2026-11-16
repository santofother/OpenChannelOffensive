#!/bin/sh
# Import/parse check + deterministic smoke tests. Run from repo root. Exit non-zero on any failure.
GODOT_BIN="${GODOT_BIN:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.." || exit 1
fail() { echo "CHECK FAILED: $1"; exit 1; }
PORT=24711

echo "== import/parse"
OUT=$("$GODOT_BIN" --headless --path game --import 2>&1); echo "$OUT" | grep -E "SCRIPT ERROR|Parse Error|ERROR:" && fail "import/parse errors"

echo "== offline smoke"
"$GODOT_BIN" --headless --path game -- --smoke-offline --no-steam 2>&1 | tee /tmp/fps_offline.log | grep -q SMOKE_OK || fail "offline smoke"

echo "== graybox controller smoke (walls, crouch clearance, doorway, reset)"
"$GODOT_BIN" --headless --path game res://scenes/graybox.tscn -- --smoke-graybox --no-steam 2>&1 | tee /tmp/fps_graybox.log | grep -E "PASS|FAIL|SMOKE|SCRIPT ERROR"
grep -q "SMOKE_OK graybox" /tmp/fps_graybox.log || fail "graybox smoke (see /tmp/fps_graybox.log)"

echo "== combat smoke (rifle, cover, charges, breaches, restart)"
"$GODOT_BIN" --headless --path game res://scenes/graybox.tscn -- --smoke-combat --no-steam 2>&1 | tee /tmp/fps_combat.log | grep -E "PASS|FAIL|SMOKE|SCRIPT ERROR|ERROR"
grep -q "SMOKE_OK combat" /tmp/fps_combat.log || fail "combat smoke (see /tmp/fps_combat.log)"

echo "== ENet host+join (2 players)"
"$GODOT_BIN" --headless --path game -- --smoke-host --no-steam --port=$PORT --name=Host > /tmp/fps_host.log 2>&1 &
HP=$!; sleep 3
"$GODOT_BIN" --headless --path game -- --smoke-join=127.0.0.1 --no-steam --port=$PORT --name=Guest > /tmp/fps_join.log 2>&1 || { kill $HP 2>/dev/null; fail "join client (see /tmp/fps_join.log)"; }
wait $HP || fail "host (see /tmp/fps_host.log)"
grep -q SMOKE_OK /tmp/fps_host.log && grep -q SMOKE_OK /tmp/fps_join.log || fail "roster not synced"

echo "== incompatible build rejected clearly"
PORT=$((PORT+1))
"$GODOT_BIN" --headless --path game -- --smoke-host --want=9 --no-steam --port=$PORT > /tmp/fps_host2.log 2>&1 &
HP=$!; sleep 3
"$GODOT_BIN" --headless --path game -- --smoke-join=127.0.0.1 --expect-reject --build-id=bogus --no-steam --port=$PORT > /tmp/fps_join2.log 2>&1 || { kill $HP 2>/dev/null; fail "mismatch not rejected (see /tmp/fps_join2.log)"; }
kill $HP 2>/dev/null
grep SMOKE_REJECTED /tmp/fps_join2.log
echo "ALL CHECKS PASSED"
