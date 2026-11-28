#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "Validating SoulSync production build configuration..."

# 1. Fail if any private IP URL appears anywhere in lib/
if grep -rnE "https?://(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)" "$ROOT_DIR/lib/" ; then
  echo "ERROR: Private IP URL found in lib/!"
  exit 1
fi

# 1b. Fail if localhost/127.0.0.1 appears outside ApiConfig.defaultDevUrl
if grep -rnE "https?://(127\.0\.0\.1|localhost)" "$ROOT_DIR/lib/" | grep -v "defaultDevUrl" ; then
  echo "ERROR: Hardcoded localhost URL found outside ApiConfig.defaultDevUrl!"
  exit 1
fi

# 2. Fail if any secrets or dev_otp references exist in frontend lib/
if grep -rnE "dev_otp|SMTP_PASS|AIzaSy" "$ROOT_DIR/lib/" ; then
  echo "ERROR: Sensitive credential or dev_otp found in lib/!"
  exit 1
fi

# 3. Ensure ApiConfig production URL is HTTPS and non-private
if ! grep -q "https://" "$ROOT_DIR/lib/core/config/api_config.dart"; then
  echo "ERROR: ApiConfig missing HTTPS production URL!"
  exit 1
fi

echo "PASS: Production build configuration validated cleanly."
