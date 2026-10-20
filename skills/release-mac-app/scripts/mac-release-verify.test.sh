#!/usr/bin/env bash
# Appcast checks are synthetic; the Darwin-only crypto checks use ephemeral keys.
set -euo pipefail

if [[ "${1:-}" != --isolated ]]; then
  exec /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash "$0" --isolated "$@"
fi
shift
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
library=${1:-$script_dir/lib/mac_release.sh}
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

cat >"$test_root/runner" <<'RUNNER'
#!/bin/bash -p
set -euo pipefail
source "$LIBRARY"
ROOT="$FIXTURE/repo"

record() { printf '%s\n' "$*" >>"$FIXTURE/events"; }
forbidden() {
  printf '%s must not be called\n' "$1" >&2
  record "forbidden $1"
  return 97
}
generate_keys() {
  if [[ "$SCENARIO" == missing-key* ]]; then
    [[ "$*" == -p ]]
    record missing-key
    printf 'ERROR: No existing signing key found!\n'
    return 1
  fi
  forbidden generate_keys
}
sign_update() { forbidden sign_update; }
op() { forbidden op; }
security() { forbidden security; }
mktemp() {
  if [[ "${1:-}" == -d ]]; then
    command mktemp -d "$FIXTURE/tmp/dir.XXXXXX"
  else
    command mktemp "$FIXTURE/tmp/file.XXXXXX"
  fi
}
curl() {
  local dest= arg
  [[ "${!#}" == https://example.invalid/Fixture.zip ]]
  while [[ $# -gt 0 ]]; do
    arg=$1
    shift
    if [[ "$arg" == --output ]]; then dest=$1; shift; fi
  done
  [[ -n "$dest" ]]
  printf abcdef >"$dest"
  record download
  printf 200
}
stat() {
  [[ "$1" == -f%z ]]
  wc -c <"$2" | tr -d ' '
}
ditto() {
  [[ "$1 $2 $3" == '-x -k --norsrc' && "$(<"$4")" == abcdef ]]
  mkdir "$5/Fixture.app"
  record extract
}
# The production helper uses an absolute path; keep that call synthetic too.
/usr/bin/ditto() { ditto "$@"; }
codesign() {
  [[ "$1 $2 $3 $4" == '--verify --deep --strict --verbose=2' && -d "$5" ]]
  record codesign
}
syspolicy_check() {
  [[ "$1" == distribution && -d "$2" ]]
  record syspolicy_check
}
spctl() {
  [[ "$1 $2 $3 $4" == '--assess --type execute --verbose' && -d "$5" ]]
  record spctl
}
stapler() {
  [[ "$1" == validate && -d "$2" ]]
  record stapler
}
mac_release_verify_ed_signature() {
  [[ "$1" == fixture-public-key && "$2" == fixture-signature && "$(<"$3")" == abcdef ]]
  record signature
}

if [[ "$SCENARIO" == missing-key ]]; then
  # Prove failure also removes any process-owned temporary keys.
  _MAC_RELEASE_OWNED_SPARKLE_RAW_FILE="$FIXTURE/tmp/raw-key"
  _MAC_RELEASE_OWNED_SPARKLE_CLEAN_FILE="$FIXTURE/tmp/clean-key"
  touch "$_MAC_RELEASE_OWNED_SPARKLE_RAW_FILE" "$_MAC_RELEASE_OWNED_SPARKLE_CLEAN_FILE"
  mac_release_key_args_and_validate KEY_ARGS key_file
elif [[ "$SCENARIO" == missing-key-status ]]; then
  mac_release_sparkle_key_status keychain
else
  if [[ "$SCENARIO" == spctl ]]; then
    unset -f syspolicy_check
    command() {
      if [[ "$*" == '-v syspolicy_check' ]]; then return 1; fi
      builtin command "$@"
    }
  fi
  mac_release_verify_appcast 1.2.3
fi
RUNNER
chmod +x "$test_root/runner"

for scenario in syspolicy_check spctl missing-key missing-key-status; do
  fixture="$test_root/$scenario"
  mkdir -p "$fixture/repo" "$fixture/tmp"
  cat >"$fixture/repo/.mac-release.env" <<'MANIFEST'
MAC_RELEASE_APP_NAME=Fixture
MAC_RELEASE_REPO=fixture/release
MAC_RELEASE_BUNDLE_ID=example.fixture
MAC_RELEASE_VERSION_FILE=version.env
MAC_RELEASE_APPCAST=appcast.xml
MAC_RELEASE_FEED_URL=https://example.invalid/appcast.xml
MAC_RELEASE_DOWNLOAD_URL_PREFIX=https://example.invalid/
MAC_RELEASE_APP_ZIP=Fixture.zip
MAC_RELEASE_SUPUBLIC_ED_KEY=fixture-public-key
MANIFEST
  printf 'MARKETING_VERSION=1.2.3\nBUILD_NUMBER=123\n' >"$fixture/repo/version.env"
  cat >"$fixture/repo/appcast.xml" <<'APPCAST'
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
<enclosure url="https://example.invalid/Fixture.zip" sparkle:edSignature="fixture-signature" length="6"/>
</item></channel></rss>
APPCAST
  result=0
  LIBRARY="$library" FIXTURE="$fixture" SCENARIO="$scenario" \
    "$test_root/runner" >"$fixture/output" 2>"$fixture/error" || result=$?
  if [[ "$scenario" == missing-key ]]; then
    [[ "$result" != 0 && ! -s "$fixture/output" ]]
    grep -Fq 'No usable Sparkle signing key from Keychain service' "$fixture/error"
    grep -Fq 'run mac-release sparkle-key-status' "$fixture/error"
    [[ ! -e "$fixture/tmp/raw-key" && ! -e "$fixture/tmp/clean-key" ]]
    printf 'missing-key\n' >"$fixture/expected-events"
  elif [[ "$scenario" == missing-key-status ]]; then
    [[ "$result" != 0 ]]
    grep -Fq 'signing public key: unavailable' "$fixture/output"
    grep -Fq 'status: missing' "$fixture/error"
    grep -Fq 'No usable Sparkle signing key' "$fixture/error"
    printf 'missing-key\n' >"$fixture/expected-events"
  else
    [[ "$result" == 0 ]] || { cat "$fixture/error" >&2; exit 1; }
    grep -Fq 'Appcast entry 1.2.3 verified (signature & length).' "$fixture/output"
    grep -Fq 'Codesign/system-policy/stapler verification OK for Fixture.app' "$fixture/output"
    printf '%s\n' download signature download extract codesign "$scenario" stapler >"$fixture/expected-events"
  fi
  cmp "$fixture/expected-events" "$fixture/events"
done

if [[ "$(uname -s)" == Darwin ]] && command -v swift >/dev/null 2>&1; then
  # shellcheck disable=SC1090 # optional library under test
  source "$library"
  export CLANG_MODULE_CACHE_PATH="$test_root/clang-cache"
  export SWIFT_MODULE_CACHE_PATH="$test_root/swift-cache"
  printf abcdef >"$test_root/payload"
  swift - "$test_root/payload" >"$test_root/crypto" <<'SWIFT'
import CryptoKit
import Foundation

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let key = Curve25519.Signing.PrivateKey()
print(key.publicKey.rawRepresentation.base64EncodedString())
print(try key.signature(for: data).base64EncodedString())
print(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString())
SWIFT
  public_key=$(sed -n '1p' "$test_root/crypto")
  signature=$(sed -n '2p' "$test_root/crypto")
  other_key=$(sed -n '3p' "$test_root/crypto")
  mac_release_verify_ed_signature "$public_key" "$signature" "$test_root/payload" >"$test_root/crypto-output"
  [[ ! -s "$test_root/crypto-output" ]]
  printf tampered >"$test_root/tampered"
  for scenario in tampered other-key malformed-key short-key empty-key malformed-signature short-signature empty-signature; do
    key=$public_key sig=$signature file="$test_root/payload"
    case "$scenario" in
      tampered) file="$test_root/tampered" ;;
      other-key) key=$other_key ;;
      malformed-key) key=not-base64 ;;
      short-key) key=YWJj ;;
      empty-key) key= ;;
      malformed-signature) sig=not-base64 ;;
      short-signature) sig=YWJj ;;
      empty-signature) sig= ;;
    esac
    if mac_release_verify_ed_signature "$key" "$sig" "$file" >"$test_root/crypto-output" 2>"$test_root/crypto-error"; then
      echo "$scenario signature verification unexpectedly succeeded" >&2
      exit 1
    fi
    [[ ! -s "$test_root/crypto-output" && -s "$test_root/crypto-error" ]]
    case "$scenario" in
      tampered|other-key) grep -Fq 'EdDSA signature does not match SUPublicEDKey' "$test_root/crypto-error" ;;
      *key) grep -Fq 'Invalid public key' "$test_root/crypto-error" ;;
      *signature) grep -Fq 'Invalid signature' "$test_root/crypto-error" ;;
    esac
  done
  echo 'mac release real-crypto tests passed'
else
  echo 'mac release real-crypto tests skipped (requires Darwin and swift)'
fi

echo 'mac release verify tests passed'
