#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob
files=(source-*.lst)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No coverage files found." >&2
  exit 1
fi

declare -i fail=0
for f in "${files[@]}"; do
  last_line=$(tail -n 1 "$f" | tr -d '\r')
  if [[ $last_line =~ ([0-9]+)% ]]; then
    perc=${BASH_REMATCH[1]}
    if (( perc < 70 )); then
      echo "Coverage for $f is below 70%: ${perc}%" >&2
      fail=1
    fi
  else
    echo "Could not parse coverage percentage from $f" >&2
    fail=1
  fi
done

if (( fail )); then
  echo "Coverage check failed." >&2
  exit 1
fi

echo "All coverage files meet the threshold."
