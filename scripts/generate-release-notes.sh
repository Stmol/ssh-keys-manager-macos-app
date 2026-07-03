#!/usr/bin/env bash

set -euo pipefail

current_tag=""
output_path="RELEASE_NOTES.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --current-tag)
      current_tag="${2:?missing value for --current-tag}"
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

if [[ -z "$current_tag" ]]; then
  echo "error: --current-tag is required" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

tag_ref="refs/tags/$current_tag"
target_ref="$current_tag"
if ! git -C "$repo_root" rev-parse -q --verify "$tag_ref" >/dev/null 2>&1; then
  target_ref="HEAD"
fi

previous_tag=""
if git -C "$repo_root" rev-parse -q --verify "${target_ref}^" >/dev/null 2>&1; then
  previous_tag="$(git -C "$repo_root" describe --tags --abbrev=0 "${target_ref}^" 2>/dev/null || true)"
fi

mkdir -p "$(dirname "$output_path")"

{
  echo "## What's Changed"
  echo

  if [[ -n "$previous_tag" ]]; then
    git -C "$repo_root" log --reverse --pretty=format:'- %s' "${previous_tag}..${target_ref}"
  else
    git -C "$repo_root" log --reverse --pretty=format:'- %s' "$target_ref"
  fi

  echo
  echo

  if [[ -n "$previous_tag" ]]; then
    remote_url="$(git -C "$repo_root" remote get-url origin 2>/dev/null || true)"
    if [[ "$remote_url" =~ github\.com[:/](.+)/(.+)(\.git)?$ ]]; then
      owner_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
      owner_repo="${owner_repo%.git}"
      echo "**Full Changelog**: https://github.com/${owner_repo}/compare/${previous_tag}...${current_tag}"
    fi
  fi
} > "$output_path"

echo "$output_path"
