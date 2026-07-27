#!/usr/bin/env bash
set -euo pipefail

# ZenithAudio CI/CD Secrets Setup
# Run this locally to generate signing material and upload to GitHub Secrets via gh CLI.

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI is not installed. Install from https://cli.github.com/" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Error: gh is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

REPO="NecoArc-Chaos/ZenithAudio"
SECRETS_DIR=".build-secrets"
mkdir -p "$SECRETS_DIR"

echo "=== Android Keystore ==="
read -p "Enter keystore password (press Enter to generate a new one): " KS_PASS
KS_PASS="${KS_PASS:-$(openssl rand -base64 24 | tr -d '/+=')}"
KEY_ALIAS="upload"
KEY_PASS="$KS_PASS"

if [ ! -f "$SECRETS_DIR/upload-keystore.jks" ]; then
  echo "Generating new upload keystore..."
  keytool -genkeypair -v \
    -keystore "$SECRETS_DIR/upload-keystore.jks" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias "$KEY_ALIAS" \
    -storepass "$KS_PASS" \
    -keypass "$KEY_PASS" \
    -dname "CN=ZenithAudio, OU=Dev, O=NecoArc, L=, S=, C=US"
else
  echo "Using existing keystore at $SECRETS_DIR/upload-keystore.jks"
fi

echo "Uploading Android secrets..."
BASE64_KEYSTORE=$(base64 -i "$SECRETS_DIR/upload-keystore.jks" | tr -d '\n')
gh secret set ANDROID_KEYSTORE_BASE64 --repo "$REPO" --body "$BASE64_KEYSTORE"
gh secret set ANDROID_KEY_ALIAS --repo "$REPO" --body "$KEY_ALIAS"
gh secret set ANDROID_KEY_STORE_PASSWORD --repo "$REPO" --body "$KS_PASS"
gh secret set ANDROID_KEY_PASSWORD --repo "$REPO" --body "$KEY_PASS"

echo ""
echo "=== iOS/macOS Signing ==="
echo "You need:"
echo "  1. Apple Developer certificate (exported as .p12)"
echo "  2. Provisioning profile (.mobileprovision)"
echo ""
read -p "Path to .p12 certificate: " CERT_P12
read -p "Password for .p12: " CERT_PASS
read -p "Path to .mobileprovision: " PROV_PROFILE
read -p "Provisioning profile UUID (from filename or 'grep UUID -A1 <file>'): " PROFILE_UUID

if [ -n "$CERT_P12" ] && [ -f "$CERT_P12" ]; then
  echo "Uploading iOS/macOS secrets..."
  BASE64_CERT=$(base64 -i "$CERT_P12" | tr -d '\n')
  BASE64_PROFILE=$(base64 -i "$PROV_PROFILE" | tr -d '\n')
  gh secret set IOS_CERT_P12_BASE64 --repo "$REPO" --body "$BASE64_CERT"
  gh secret set IOS_CERT_PASSWORD --repo "$REPO" --body "$CERT_PASS"
  gh secret set IOS_PROVISIONING_PROFILE_BASE64 --repo "$REPO" --body "$BASE64_PROFILE"
  gh secret set IOS_PROVISIONING_PROFILE_UUID --repo "$REPO" --body "$PROFILE_UUID"
else
  echo "Skipping iOS/macOS signing (no .p12 provided)."
fi

echo ""
echo "=== Windows Signing (Optional) ==="
read -p "Path to Windows .pfx certificate (optional, press Enter to skip): " WIN_CERT
if [ -n "$WIN_CERT" ] && [ -f "$WIN_CERT" ]; then
  read -s -p "Password for .pfx: " WIN_CERT_PASS
  echo ""
  BASE64_WIN_CERT=$(base64 -i "$WIN_CERT" | tr -d '\n')
  gh secret set WIN_CERT_PFX_BASE64 --repo "$REPO" --body "$BASE64_WIN_CERT"
  gh secret set WIN_CERT_PASSWORD --repo "$REPO" --body "$WIN_CERT_PASS"
else
  echo "Skipping Windows signing."
fi

echo ""
echo "=== Done ==="
echo "Secrets uploaded to $REPO"
echo "Keystore backup saved to: $SECRETS_DIR/upload-keystore.jks"
echo "KEEP THIS BACKUP SAFE. Without it, you cannot update your app."
echo ""
echo "Verify with: gh secret list --repo $REPO"
