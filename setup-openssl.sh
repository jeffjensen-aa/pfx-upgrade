#!/usr/bin/env bash
set -Eeuo pipefail

version=3.5.9
archive="openssl-$version.tar.gz"
archive_url="https://github.com/openssl/openssl/releases/download/openssl-$version/$archive"
expected_sha256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
install_root="$HOME/.local/pfx-upgrade/openssl-$version"

usage() {
  printf 'Usage: %s\n' "${0##*/}"
  printf 'Downloads, verifies, and builds OpenSSL %s (3.5 LTS) for this user.\n' "$version"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
[[ $# -eq 0 ]] || { usage >&2; exit 2; }

case "$(uname -s)" in
  Linux|Darwin) ;;
  *) fail "Use setup-openssl.ps1 on Windows, or run this script in Linux/macOS Bash." ;;
esac

openssl_path="$install_root/bin/openssl"
if [[ -x "$openssl_path" ]]; then
  installed_version=$("$openssl_path" version)
  [[ "$installed_version" == "OpenSSL $version "* ]] ||
    fail "Unexpected OpenSSL already exists at $openssl_path: $installed_version"
  printf 'OpenSSL %s is already available at %s\n' "$version" "$openssl_path"
  exit 0
fi
[[ ! -e "$install_root" ]] ||
  fail "The target already exists; move it aside or remove it before setup: $install_root"

for tool in curl tar make perl; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required build tool not found: $tool"
done
if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1; then
  fail "A C compiler is required to build OpenSSL."
fi

mkdir -p "$(dirname "$install_root")"
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/pfx-openssl.XXXXXX")
cleanup() {
  local exit_code=$?
  trap - EXIT HUP INT TERM
  if [[ -d "$temp_dir" ]]; then
    rm -rf -- "$temp_dir" || {
      printf 'Warning: unable to remove temporary directory: %s\n' "$temp_dir" >&2
      [[ $exit_code -ne 0 ]] || exit_code=1
    }
  fi
  exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf '[##--------] 20%% Downloading OpenSSL %s source\n' "$version"
curl --fail --location --show-error --progress-bar "$archive_url" -o "$temp_dir/$archive"

printf '[####------] 40%% Verifying official release SHA-256\n'
if command -v sha256sum >/dev/null 2>&1; then
  actual_sha256=$(sha256sum "$temp_dir/$archive" | awk '{ print $1 }')
elif command -v shasum >/dev/null 2>&1; then
  actual_sha256=$(shasum -a 256 "$temp_dir/$archive" | awk '{ print $1 }')
else
  fail "A SHA-256 utility (sha256sum or shasum) is required."
fi
[[ "$actual_sha256" == "$expected_sha256" ]] ||
  fail "Source checksum mismatch. Expected $expected_sha256; received $actual_sha256."

printf '[######----] 60%% Extracting and configuring OpenSSL %s\n' "$version"
tar -xzf "$temp_dir/$archive" -C "$temp_dir"
source_dir="$temp_dir/openssl-$version"
(
  cd "$source_dir"
  ./Configure --prefix="$install_root" --openssldir="$install_root/ssl" \
    no-shared no-module enable-legacy
)

jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')
[[ "$jobs" =~ ^[0-9]+$ && "$jobs" -gt 0 ]] || jobs=2
printf '[########--] 80%% Building and installing locally (make -j%s)\n' "$jobs"
(
  cd "$source_dir"
  make -j"$jobs"
  make install_sw
)

[[ -x "$openssl_path" ]] || fail "OpenSSL build did not create $openssl_path"
installed_version=$("$openssl_path" version)
[[ "$installed_version" == "OpenSSL $version "* ]] ||
  fail "Installed OpenSSL version could not be verified: $installed_version"

printf '[##########] 100%% OpenSSL %s installed at %s\n' "$version" "$openssl_path"
