#!/usr/bin/env bash
# Activate the exact reviewed Temurin JDK from disposable Build storage.

set -euo pipefail

if [[ "$#" -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 2
fi

for command_name in chmod curl grep mkdir mktemp mv readlink rm sed sha256sum tar; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "FATAL: required JDK activation command is missing: $command_name" >&2
    exit 1
  fi
done

: "${GITHUB_ENV:?FATAL: GITHUB_ENV is required}"
: "${GITHUB_PATH:?FATAL: GITHUB_PATH is required}"

build_root="${SML_TOOLCHAIN_ROOT:-$HOME/Build}"
jdk_cache="$build_root/such-moon-launch/cache/jdk"
jdk_home="$jdk_cache/temurin-17.0.20+8"
marker="$jdk_home/.such-reviewed-jdk"
archive_name="OpenJDK17U-jdk_x64_linux_hotspot_17.0.20_8.tar.gz"
archive="$jdk_cache/$archive_name"
archive_url="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20%2B8/$archive_name"
archive_sha256="be7668bc030d578b83d6d5ef9221d6d6729bbbca8cf94a7d52e16ac68b5a5a35"

if [[ "$build_root" != /* || -L "$build_root" ]]; then
  echo "FATAL: CI toolchain root must be one physical absolute directory." >&2
  exit 1
fi
mkdir -p "$build_root" "$jdk_cache"
resolved_build_root="$(cd -- "$build_root" && pwd -P)"
resolved_jdk_cache="$(cd -- "$jdk_cache" && pwd -P)"
if [[ "$resolved_jdk_cache" != "$resolved_build_root/such-moon-launch/cache/jdk" ]]; then
  echo "FATAL: JDK cache escaped disposable Moon Launch Build storage." >&2
  exit 1
fi

verify_jdk() {
  local version_line
  [[ -d "$jdk_home" && ! -L "$jdk_home" && -x "$jdk_home/bin/java" ]] || return 1
  [[ -f "$marker" && ! -L "$marker" ]] || return 1
  grep -Fxq "archive_url=$archive_url" "$marker" || return 1
  grep -Fxq "archive_sha256=$archive_sha256" "$marker" || return 1
  version_line="$("$jdk_home/bin/java" -version 2>&1 | sed -n '1p')"
  [[ "$version_line" == *'version "17.0.20"'* ]]
}

temporary_archive=""
extraction_root=""
cleanup() {
  if [[ -n "$temporary_archive" ]]; then
    rm -f -- "$temporary_archive"
  fi
  if [[ -n "$extraction_root" ]]; then
    rm -rf -- "$extraction_root"
  fi
}
trap cleanup EXIT INT TERM

if ! verify_jdk; then
  if ! printf '%s  %s\n' "$archive_sha256" "$archive" |
    sha256sum -c - >/dev/null 2>&1; then
    rm -f -- "$archive"
    temporary_archive="$(mktemp "$jdk_cache/$archive_name.download.XXXXXX")"
    curl \
      --fail \
      --location \
      --proto '=https' \
      --proto-redir '=https' \
      --retry 3 \
      --silent \
      --show-error \
      --output "$temporary_archive" \
      "$archive_url"
    printf '%s  %s\n' "$archive_sha256" "$temporary_archive" |
      sha256sum -c - >/dev/null
    mv -- "$temporary_archive" "$archive"
    temporary_archive=""
  fi

  rm -rf -- "$jdk_home"
  extraction_root="$(mktemp -d "$jdk_cache/extract.XXXXXX")"
  tar --extract --gzip --no-same-owner --file "$archive" --directory "$extraction_root"
  extracted_jdk="$extraction_root/jdk-17.0.20+8"
  if [[ ! -d "$extracted_jdk" || -L "$extracted_jdk" ]]; then
    echo "FATAL: reviewed JDK archive did not contain its exact root." >&2
    exit 1
  fi
  mv -- "$extracted_jdk" "$jdk_home"
  {
    printf 'archive_url=%s\n' "$archive_url"
    printf 'archive_sha256=%s\n' "$archive_sha256"
  } >"$marker"
  chmod 0444 "$marker"
  rm -rf -- "$extraction_root"
  extraction_root=""
fi

verify_jdk || {
  echo "FATAL: exact reviewed Temurin JDK activation did not pass." >&2
  exit 1
}
resolved_jdk_home="$(readlink -f -- "$jdk_home")"
if [[ "$resolved_jdk_home" != "$resolved_jdk_cache/temurin-17.0.20+8" ]]; then
  echo "FATAL: activated JDK escaped disposable Build storage." >&2
  exit 1
fi

{
  printf 'JAVA_HOME=%s\n' "$resolved_jdk_home"
  printf 'SML_JAVA_HOME=%s\n' "$resolved_jdk_home"
} >>"$GITHUB_ENV"
printf '%s\n' "$resolved_jdk_home/bin" >>"$GITHUB_PATH"
printf '%s\n' "Temurin JDK 17.0.20+8: PASS"
