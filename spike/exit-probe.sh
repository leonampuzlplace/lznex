#!/usr/bin/env bash
# Descobre se o ExitCode do FPC chega ao shell, e se Halt chega.
set -u
cd /work
mkdir -p /tmp/ep
fpc -Mdelphi -Sh -FE/tmp/ep -FU/tmp/ep spike/ExitProbe.lpr 2>&1 | tail -2

echo "--- MODE=exitcode (espera 7)"
MODE=exitcode /tmp/ep/ExitProbe
echo "    exit=$?"

echo "--- MODE=halt (espera 7)"
MODE=halt /tmp/ep/ExitProbe
echo "    exit=$?"

echo "--- sem MODE (espera 0)"
/tmp/ep/ExitProbe
echo "    exit=$?"
