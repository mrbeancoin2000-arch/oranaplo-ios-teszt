#!/usr/bin/env bash
# Each target resolves its own platform SDK. Never force -sdk for a combined iOS + watchOS scheme.
# One separate log per phase, only true Swift diagnostics are highlighted on failure.
set -uo pipefail
MODE="${1:-simulator}"
SCHEME=OraNaplo
if [[ "$MODE" == "simulator" ]]; then
  DEST='generic/platform=iOS Simulator'; LOG=xcodebuild-simulator.log; DERIVED=build-simulator
elif [[ "$MODE" == "watch" ]]; then
  DEST='generic/platform=watchOS Simulator'; LOG=xcodebuild-watchsimulator.log; DERIVED=build-watch
  SCHEME=OraNaploWatch
else
  DEST='generic/platform=iOS'; LOG=xcodebuild.log; DERIVED=build
fi
echo "[ÓraNapló CI] Starting $MODE: $(date -u +%FT%TZ)"
xcodebuild -quiet -project OraNaplo.xcodeproj -scheme "$SCHEME" -configuration Debug \
  -destination "$DEST" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build > "$LOG" 2>&1 &
pid=$!
start=$SECONDS
while kill -0 "$pid" 2>/dev/null; do
  sleep 20
  if kill -0 "$pid" 2>/dev/null; then
    echo "[ÓraNapló CI] $MODE Apple SDK compile in progress: ${SECONDS} seconds elapsed (${LOG})"
  fi
done
wait "$pid"; result=$?
if [[ "$result" -ne 0 ]]; then
  echo "::error::Apple SDK $MODE build failed (exit $result). Errors below, full log in artifact."
  grep -nE 'error:|fatal error:|\*\* BUILD FAILED' "$LOG" | head -70 || tail -40 "$LOG"
  exit "$result"
fi
echo "[ÓraNapló CI] $MODE compile succeeded. Elapsed: $((SECONDS-start)) seconds"
