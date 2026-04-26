#!/usr/bin/env bash

set -euo pipefail

build_only=0
configuration="Release"
output_path=""
release_version=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-only)
      build_only=1
      shift
      ;;
    --configuration)
      configuration="${2:?missing value for --configuration}"
      shift 2
      ;;
    --output)
      output_path="${2:?missing value for --output}"
      shift 2
      ;;
    --release-version)
      release_version="${2:?missing value for --release-version}"
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

project_path="$repo_root/SSH Keys Manager.xcodeproj"
scheme="SSH Keys Manager"
build_root="$repo_root/build/release"
derived_data_path="/tmp/ssh-keys-manager-release-derived-data"
product_dir="$derived_data_path/Build/Products/$configuration"
artifact_dir="$build_root/Products/$configuration"
app_name="SSH Keys Manager.app"
app_path="$product_dir/$app_name"
artifact_app_path="$artifact_dir/$app_name"
stage_root="$build_root/dmg"
stage_app_path="$stage_root/$app_name"
dist_dir="$repo_root/dist"

info() {
  echo "==> $*"
}

fail() {
  echo "error: $*" >&2
  exit 1
}

for command_name in xcodebuild hdiutil ditto git; do
  command -v "$command_name" >/dev/null 2>&1 || fail "Missing required command: $command_name"
done

[[ -d "$project_path" ]] || fail "Project not found: $project_path"

if [[ -z "$release_version" ]]; then
  if ! release_version="$(git -C "$repo_root" describe --tags --always 2>/dev/null)"; then
    release_version="dev"
  fi
fi

release_version="$(printf '%s' "$release_version" | tr -d '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "$release_version" ]] || release_version="dev"

version_slug="$(printf '%s' "$release_version" | sed 's/[^A-Za-z0-9._-]/-/g')"
default_output="$dist_dir/SSH-Keys-Manager-$version_slug.dmg"
dmg_path="${output_path:-$default_output}"

info "Preparing release directories"
mkdir -p "$build_root" "$dist_dir" "$artifact_dir"
rm -rf "$stage_root"
rm -rf "$derived_data_path"
rm -rf "$artifact_dir"
mkdir -p "$artifact_dir"
mkdir -p "$stage_root"

info "Building $app_name ($configuration)"
xcodebuild \
  -project "$project_path" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

[[ -d "$app_path" ]] || fail "Built app not found at $app_path"

info "Copying build artifacts"
ditto "$app_path" "$artifact_app_path"

shopt -s nullglob
for dsym_path in "$product_dir"/*.dSYM; do
  ditto "$dsym_path" "$artifact_dir/$(basename "$dsym_path")"
done
shopt -u nullglob

info "Copying app into DMG staging folder"
ditto "$artifact_app_path" "$stage_app_path"
ln -s /Applications "$stage_root/Applications"

if [[ "$build_only" -eq 1 ]]; then
  info "Build-only mode finished"
  echo "$artifact_app_path"
  exit 0
fi

info "Creating DMG at $dmg_path"
rm -f "$dmg_path"
hdiutil create \
  -volname "SSH Keys Manager" \
  -srcfolder "$stage_root" \
  -ov \
  -format UDZO \
  "$dmg_path"

info "DMG ready"
echo "$dmg_path"
