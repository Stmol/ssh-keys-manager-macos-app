#!/usr/bin/env bash

set -euo pipefail

release_version=""
output_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-version)
      release_version="${2:?missing value for --release-version}"
      shift 2
      ;;
    --output)
      output_path="${2:?missing value for --output}"
      shift 2
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

if [[ -z "$release_version" ]]; then
  if ! release_version="$(git -C "$repo_root" describe --tags --always 2>/dev/null)"; then
    release_version="dev"
  fi
fi

release_version="$(printf '%s' "$release_version" | tr -d '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "$release_version" ]] || release_version="dev"

version_slug="$(printf '%s' "$release_version" | sed 's/[^A-Za-z0-9._-]/-/g')"
build_root="$repo_root/build/release"
dist_dir="$repo_root/dist"
product_dir="$build_root/Products/Release"
stage_dir="$build_root/dsyms-stage"
zip_path="${output_path:-$dist_dir/SSH-Keys-Manager-$version_slug-dSYMs.zip}"

mkdir -p "$dist_dir"
rm -rf "$stage_dir"
mkdir -p "$stage_dir"

shopt -s nullglob
found_any=0

for dsym in "$product_dir"/*.dSYM; do
  cp -R "$dsym" "$stage_dir/"
  found_any=1
done

if [[ "$found_any" -eq 0 ]]; then
  echo "error: no .dSYM bundles found in $product_dir" >&2
  rm -rf "$stage_dir"
  exit 1
fi

rm -f "$zip_path"
ditto -c -k --sequesterRsrc "$stage_dir" "$zip_path"
rm -rf "$stage_dir"

echo "$zip_path"
