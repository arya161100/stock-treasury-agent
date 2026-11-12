#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
forge test -vv --no-match-test invariant
echo "----- invariants (256 runs) -----"
forge test --match-test invariant
