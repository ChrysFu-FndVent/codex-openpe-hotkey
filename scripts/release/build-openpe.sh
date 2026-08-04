#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/../.." && pwd)"
lock_file="$project_root/release/openpe.lock.json"
output="${1:-$project_root/dist/openpe-server}"
target="${2:-macos-universal}"

for command_name in git go jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

repository="$(jq -er '.repository' "$lock_file")"
commit="$(jq -er '.commit | select(test("^[0-9a-f]{40}$"))' "$lock_file")"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
source_dir="$temporary_dir/openpe"

git init -q "$source_dir"
git -C "$source_dir" remote add origin "$repository"
git -C "$source_dir" fetch -q --depth 1 origin "$commit"
git -C "$source_dir" checkout -q --detach FETCH_HEAD

actual_commit="$(git -C "$source_dir" rev-parse HEAD)"
if [ "$actual_commit" != "$commit" ]; then
  echo "openPE commit mismatch: expected $commit, got $actual_commit" >&2
  exit 1
fi

mkdir -p "$(dirname "$output")"
case "$target" in
  macos-universal)
    arm_binary="$temporary_dir/openpe-server-arm64"
    intel_binary="$temporary_dir/openpe-server-x86_64"
    (
      cd "$source_dir"
      CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 \
        go build -trimpath -buildvcs=false -ldflags='-s -w' -o "$arm_binary" ./cmd/openpe-server
      CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 \
        go build -trimpath -buildvcs=false -ldflags='-s -w' -o "$intel_binary" ./cmd/openpe-server
    )
    /usr/bin/lipo -create "$arm_binary" "$intel_binary" -output "$output"
    /usr/bin/lipo "$output" -verify_arch arm64 x86_64
    ;;
  macos-arm64|macos-x86_64)
    architecture="${target#macos-}"
    [ "$architecture" != "x86_64" ] || architecture="amd64"
    (
      cd "$source_dir"
      CGO_ENABLED=0 GOOS=darwin GOARCH="$architecture" \
        go build -trimpath -buildvcs=false -ldflags='-s -w' -o "$output" ./cmd/openpe-server
    )
    ;;
  *)
    echo "Unsupported target: $target" >&2
    exit 2
    ;;
esac

chmod 755 "$output"
echo "Built openpe-server from $commit at $output"
