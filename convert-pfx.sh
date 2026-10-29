#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf 'Usage: %s <input.pfx> <output.pfx> [chain.pem]\n' "${0##*/}"
  printf 'Converts a legacy PFX to an OpenSSL 3-compatible PFX.\n'
  printf 'OpenSSL interactively prompts for source, key, and output passwords.\n'
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 2
fi

input_pfx=$1
output_pfx=$2
chain_file=${3:-}

[[ -f "$input_pfx" ]] || fail "Input PFX not found: $input_pfx"
[[ ! -e "$output_pfx" && ! -L "$output_pfx" ]] || fail "Output already exists: $output_pfx"
if [[ -n "$chain_file" ]]; then
  [[ -f "$chain_file" ]] || fail "Chain file not found: $chain_file"
fi

output_dir=$(dirname -- "$output_pfx")
[[ -d "$output_dir" ]] || fail "Output directory not found: $output_dir"

local_openssl="$HOME/.local/pfx-upgrade/openssl-3.5.9/bin/openssl"
if [[ -x "$local_openssl" ]]; then
  openssl_path=$local_openssl
else
  openssl_path=$(command -v openssl) ||
    fail "OpenSSL was not found. Run setup-openssl.sh or add OpenSSL 3 to PATH."
fi
version_output=$("$openssl_path" version 2>&1) || fail "Unable to determine the OpenSSL version."
[[ "$version_output" =~ ^OpenSSL[[:space:]]+3\. ]] ||
  fail "OpenSSL 3.x is required for -legacy support; found: $version_output"

umask 077
temp_dir=$(mktemp -d "$output_dir/.pfx-upgrade.XXXXXX") ||
  fail "Unable to create a temporary directory in: $output_dir"

cleanup() {
  local exit_code=$?
  trap - EXIT HUP INT TERM
  if [[ -n "${temp_dir:-}" && -d "$temp_dir" ]]; then
    if ! rm -rf -- "$temp_dir"; then
      printf 'Warning: unable to remove temporary directory: %s\n' "$temp_dir" >&2
      [[ $exit_code -ne 0 ]] || exit_code=1
    fi
  fi
  exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

show_progress() {
  local percent=$1
  local label=$2
  local filled=$((percent / 10))
  local bar
  printf -v bar '%*s' "$filled" ''
  bar=${bar// /#}
  printf '[%-10s] %3d%% %s\n' "$bar" "$percent" "$label"
}

show_progress 10 "Extracting certificate (OpenSSL may prompt for the PFX password)"
"$openssl_path" pkcs12 -legacy -in "$input_pfx" -clcerts -nokeys \
  -out "$temp_dir/cert.pem" ||
  fail "Certificate extraction failed."

show_progress 40 "Extracting encrypted private key (OpenSSL will prompt for passwords)"
"$openssl_path" pkcs12 -legacy -in "$input_pfx" -nocerts \
  -out "$temp_dir/key.pem" ||
  fail "Private-key extraction failed."

export_args=(-export -in "$temp_dir/cert.pem" -inkey "$temp_dir/key.pem" \
  -out "$temp_dir/new.pfx")
if [[ -n "$chain_file" ]]; then
  export_args+=(-certfile "$chain_file")
fi

show_progress 75 "Exporting new PFX (OpenSSL will prompt for passwords)"
"$openssl_path" pkcs12 "${export_args[@]}" ||
  fail "PFX export failed."

if ! mv -n -- "$temp_dir/new.pfx" "$output_pfx"; then
  fail "Unable to create output PFX: $output_pfx"
fi
[[ ! -e "$temp_dir/new.pfx" ]] ||
  fail "Output appeared during conversion and was not overwritten: $output_pfx"
[[ -f "$output_pfx" ]] || fail "Output PFX was not created: $output_pfx"

show_progress 100 "Conversion complete: $output_pfx"
