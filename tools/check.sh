#!/bin/sh
# Import/parse check + deterministic smoke tests. Run from repo root. Exit non-zero on any failure.
GODOT_BIN="${GODOT_BIN:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.." || exit 1
fail() { echo "CHECK FAILED: $1"; exit 1; }
PORT=24711

echo "== import/parse"
OUT=$("$GODOT_BIN" --headless --path game --import 2>&1); echo "$OUT" | grep -E "SCRIPT ERROR|Parse Error|ERROR:" && fail "import/parse errors"

echo "== recoil and lean (wire format, collision, prediction, bindings)"
"$GODOT_BIN" --headless --path game --script res://scripts/tools/controls_test.gd -- --no-steam > /tmp/fps_controls_test.log 2>&1 || fail "controls process"
grep -Eq "SCRIPT ERROR|^ERROR:" /tmp/fps_controls_test.log && fail "controls script errors"
grep -E "PASS|FAIL|SMOKE" /tmp/fps_controls_test.log
grep -q "SMOKE_OK controls" /tmp/fps_controls_test.log || fail "controls checks"

echo "== round rules (deadlines, interruptions, double elimination, side swap, clinch, deciding round, MVP, rematch)"
"$GODOT_BIN" --headless --path game --script res://scripts/match/round_test.gd -- --no-steam > /tmp/fps_round_unit.log 2>&1 || fail "round unit process"
grep -Eq "SCRIPT ERROR|^ERROR:" /tmp/fps_round_unit.log && fail "round unit script errors"
cat /tmp/fps_round_unit.log | grep -E "PASS|FAIL|SMOKE|SCRIPT ERROR"
grep -q "SMOKE_OK rounds" /tmp/fps_round_unit.log || fail "round unit checks"

echo "== voice codec, jitter queue and recipient rules"
"$GODOT_BIN" --headless --path game res://scripts/voice/voice_test.tscn -- --no-steam > /tmp/fps_voice_unit.log 2>&1
cat /tmp/fps_voice_unit.log | grep -E "PASS|FAIL|SMOKE|SCRIPT ERROR"
grep -q "SMOKE_OK voice" /tmp/fps_voice_unit.log || fail "voice unit checks"

echo "== offline smoke"
"$GODOT_BIN" --headless --path game -- --smoke-offline --no-steam 2>&1 | tee /tmp/fps_offline.log | grep -q SMOKE_OK || fail "offline smoke"

echo "== graybox controller smoke (walls, crouch clearance, doorway, reset)"
"$GODOT_BIN" --headless --path game res://scenes/graybox.tscn -- --smoke-graybox --no-steam 2>&1 | tee /tmp/fps_graybox.log | grep -E "PASS|FAIL|SMOKE|SCRIPT ERROR"
grep -q "SMOKE_OK graybox" /tmp/fps_graybox.log || fail "graybox smoke (see /tmp/fps_graybox.log)"

echo "== combat smoke (rifle, cover, charges, breaches, restart)"
"$GODOT_BIN" --headless --path game res://scenes/graybox.tscn -- --smoke-combat --no-steam 2>&1 | tee /tmp/fps_combat.log | grep -E "PASS|FAIL|SMOKE|SCRIPT ERROR|ERROR"
grep -q "SMOKE_OK combat" /tmp/fps_combat.log || fail "combat smoke (see /tmp/fps_combat.log)"

echo "== Lightwell graybox (doors, spawns, sites, wall coverage, resets)"
"$GODOT_BIN" --headless --path game -- --smoke-lightwell --no-steam > /tmp/fps_lightwell_geometry.log 2>&1 || fail "Lightwell process"
grep -Eq "SCRIPT ERROR|^ERROR:" /tmp/fps_lightwell_geometry.log && fail "Lightwell script errors"
grep -E "PASS|FAIL|SMOKE" /tmp/fps_lightwell_geometry.log
grep -q "SMOKE_OK lightwell" /tmp/fps_lightwell_geometry.log || fail "Lightwell geometry"

echo "== localized wall destruction (shots, melee, collision, replication, reset)"
"$GODOT_BIN" --headless --path game -- --smoke-destruction --no-steam > /tmp/fps_destruction_check.log 2>&1 || fail "localized destruction"
grep -Eq "SCRIPT ERROR|^ERROR:" /tmp/fps_destruction_check.log && fail "localized destruction script errors"
grep -E "PASS|FAIL|SMOKE" /tmp/fps_destruction_check.log
grep -q "SMOKE_OK destruction" /tmp/fps_destruction_check.log || fail "localized destruction checks"

echo "== bots (fill, navigation, comms orders, prep reinforcement, combat, bomb recovery/plant)"
"$GODOT_BIN" --headless --path game -- --match-host --bot-test --no-steam --port=24790 > /tmp/fps_bots.log 2>&1 || { grep -E "FAIL|SCRIPT ERROR" /tmp/fps_bots.log; fail "bot match (see /tmp/fps_bots.log)"; }
grep -Eq "SCRIPT ERROR" /tmp/fps_bots.log && fail "bot match script errors"
grep -E "PASS|FAIL|SMOKE" /tmp/fps_bots.log
grep -q "SMOKE_OK bots" /tmp/fps_bots.log || fail "bot checks"

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

echo "== networked match (host + client + late joiner: prediction, hits, penetration, charges, resets, leave)"
NET_TEST_LOGS=/tmp/fps_net_check NET_TEST_PORT=24751 NET_METRICS_OUT=/tmp/fps_net_check_metrics.json \
	./tools/net_test.sh 2 1 > /tmp/fps_netmatch.log 2>&1 || { grep -E "FAIL|SCRIPT ERROR" /tmp/fps_netmatch.log; fail "networked match (see /tmp/fps_netmatch.log, /tmp/fps_net_check/)"; }
grep -E "FAIL|NET TEST" /tmp/fps_netmatch.log
echo "== round loop integration (full match, objectives, late join, rematch)"
NET_TEST_LOGS=/tmp/fps_round_check NET_TEST_PORT=24761 NET_METRICS_OUT=/tmp/fps_round_check_metrics.json \
	./tools/net_test.sh 3 1 --round-test > /tmp/fps_roundmatch.log 2>&1 || { grep -E "FAIL|SCRIPT ERROR" /tmp/fps_roundmatch.log; fail "round loop (see /tmp/fps_roundmatch.log, /tmp/fps_round_check/)"; }
grep -E "FAIL|NET TEST" /tmp/fps_roundmatch.log
echo "ALL CHECKS PASSED"
