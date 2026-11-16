#!/bin/sh
# Multi-process networked match test (headless ENet on localhost). Run from repo root.
#   tools/net_test.sh [players] [late 0|1] [extra args for every process, e.g. --sim-latency=50 --sim-loss=0.02]
# Starts 1 host + (players-1) clients (+1 late joiner that connects after the first breach; players + late
# must stay within the 6-player cap, so the six-peer run is `5 1`), runs the
# NetTest scenarios, and fails unless the host and every client exit cleanly
# (clients must return to the menu with "Host left the game" when the host quits).
# Metrics JSON: $NET_METRICS_OUT (default /tmp/fps_net_metrics.json).
GODOT_BIN="${GODOT_BIN:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.." || exit 1
PLAYERS="${1:-2}"
LATE="${2:-0}"
shift 2 2>/dev/null
EXTRA="$*"
PORT="${NET_TEST_PORT:-24741}"
LOGDIR="${NET_TEST_LOGS:-/tmp/fps_net}"
METRICS="${NET_METRICS_OUT:-/tmp/fps_net_metrics.json}"
LATEFILE="$LOGDIR/late.go"
mkdir -p "$LOGDIR"
rm -f "$LOGDIR"/*.log "$LATEFILE"

HOST_ARGS="--match-host --net-test=$PLAYERS --no-steam --port=$PORT --name=Host --metrics-out=$METRICS"
[ "$LATE" = "1" ] && HOST_ARGS="$HOST_ARGS --late-file=$LATEFILE"
# shellcheck disable=SC2086
"$GODOT_BIN" --headless --path game -- $HOST_ARGS $EXTRA > "$LOGDIR/host.log" 2>&1 &
HP=$!
sleep 2
PIDS=""
i=2
while [ "$i" -le "$PLAYERS" ]; do
	# shellcheck disable=SC2086
	"$GODOT_BIN" --headless --path game -- --match-join=127.0.0.1 --net-test --host-left-ok --no-steam --port=$PORT --name=Bot$i $EXTRA > "$LOGDIR/client$i.log" 2>&1 &
	PIDS="$PIDS $!"
	i=$((i + 1))
done
if [ "$LATE" = "1" ]; then
	# shellcheck disable=SC2086
	"$GODOT_BIN" --headless --path game -- --match-join=127.0.0.1 --wait-file=$LATEFILE --net-test --host-left-ok --no-steam --port=$PORT --name=Late $EXTRA > "$LOGDIR/late.log" 2>&1 &
	PIDS="$PIDS $!"
fi

# Watchdog: nothing may hang the run.
rm -f "$LOGDIR/done"
( n=0; while [ $n -lt "${NET_TEST_LIMIT:-480}" ] && [ ! -f "$LOGDIR/done" ]; do sleep 1; n=$((n + 1)); done
  [ -f "$LOGDIR/done" ] || { echo "NET TEST WATCHDOG: killing processes"; kill $HP $PIDS 2>/dev/null; } ) &
WD=$!
FAIL=0
wait $HP || FAIL=1
grep -E "PASS|FAIL|SMOKE|SCRIPT ERROR|\[Test\]" "$LOGDIR/host.log"
for p in $PIDS; do
	wait "$p" || FAIL=1
done
for f in "$LOGDIR"/client*.log "$LOGDIR"/late.log; do
	[ -f "$f" ] || continue
	if grep -q "SMOKE_OK host-left" "$f"; then
		echo "  PASS $(basename "$f"): returned to menu after host left"
	else
		# Only the client the test tells to disconnect ends without the host-left message.
		echo "  note $(basename "$f"): ended without host-left (expected only for the disconnect-test client)"
	fi
	grep -q "SCRIPT ERROR" "$f" && { echo "  FAIL $(basename "$f") has script errors"; grep -m3 "SCRIPT ERROR" -A2 "$f"; FAIL=1; }
done
touch "$LOGDIR/done"
wait $WD
grep -q "SMOKE_OK match" "$LOGDIR/host.log" || FAIL=1
grep -q "SCRIPT ERROR" "$LOGDIR/host.log" && { echo "  FAIL host has script errors"; grep -m3 "SCRIPT ERROR" -A2 "$LOGDIR/host.log"; FAIL=1; }
[ "$FAIL" = "0" ] && echo "NET TEST PASSED ($PLAYERS players, late=$LATE, $EXTRA)" || echo "NET TEST FAILED (logs in $LOGDIR)"
exit $FAIL
