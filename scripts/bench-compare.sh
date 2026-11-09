#!/usr/bin/env bash
# Compares the benchmarks of a git revision with the working tree.
#
#   scripts/bench-compare.sh [revision] [compare options]
#       The revision defaults to main. The other arguments go to benchmarks/compare.lua, for example
#       `--time-threshold 0.5`. Both sides run the cases of the working tree, so that the report shows only the
#       change in lua/. The script exits with 1 when the working tree regressed.
#
# Environment:
#   SCROLLBAR_NVIM       The Neovim to run (default: nvim).
#   BENCH_RUNS           Runs of each side (default: 2). The sides alternate, and each side uses its best run.
#   GITHUB_STEP_SUMMARY  When it is set, the report is also appended there as Markdown.
set -euo pipefail

rev=${1:-main}
shift || true
nvim=${SCROLLBAR_NVIM:-nvim}
runs=${BENCH_RUNS:-2}
root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

base_rev=$(git -C "$root" rev-parse --short "$rev")
mkdir "$tmp/base"
git -C "$root" archive "$rev" lua | tar -x -C "$tmp/base"

run() {
    "$nvim" --headless --clean -l "$root/benchmarks/run.lua" --allow-errors "$@" >/dev/null
}

base_files=""
head_files=""
for i in $(seq "$runs"); do
    echo "Run $i of $runs: $rev" >&2
    run --root "$tmp/base" --revision "$base_rev" --json "$tmp/base-$i.json"
    echo "Run $i of $runs: working tree" >&2
    run --root "$root" --json "$tmp/head-$i.json"
    base_files="${base_files:+$base_files,}$tmp/base-$i.json"
    head_files="${head_files:+$head_files,}$tmp/head-$i.json"
done

args=("$base_files" "$head_files" "$@")
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    args+=(--markdown "$GITHUB_STEP_SUMMARY")
fi
"$nvim" --headless --clean -l "$root/benchmarks/compare.lua" "${args[@]}"
