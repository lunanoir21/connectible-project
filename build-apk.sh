#!/usr/bin/env bash
set -euo pipefail

# Connectible Mobile - Robust APK Build Script
# Run from repo root: ./build-apk.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_DIR="$REPO_ROOT/mobile-rn/mobile"
ANDROID_DIR="$MOBILE_DIR/android"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()   { echo -e "${RED}[ERR]${NC}  $*"; }
log_step()  { echo -e "\n${BLUE}>>>${NC} $*"; }

die() { log_err "$*"; exit 1; }

check_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Command '$1' not found. Install it first."
}

# ========== PRE-CHECKS ==========
log_step "Pre-flight checks"

check_cmd node
check_cmd npx
check_cmd pnpm
check_cmd sdkmanager

# Java 17
if [[ -d "/usr/lib/jvm/java-17-openjdk" ]]; then
  export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
elif [[ -d "$HOME/jdk/jdk-17.0.2.jdk/Contents/Home" ]]; then
  export JAVA_HOME="$HOME/jdk/jdk-17.0.2.jdk/Contents/Home"
else
  die "Java 17 not found. Install: yay -S jdk17-openjdk"
fi
log_ok "JAVA_HOME=$JAVA_HOME"
"$JAVA_HOME/bin/java" -version 2>&1 | head -1

# Android SDK
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

if [[ ! -d "$ANDROID_HOME" ]]; then
  die "ANDROID_HOME not found at $ANDROID_HOME. Run: mkdir -p ~/Android/Sdk && curl -L 'https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip' -o /tmp/cmd.zip && unzip -q /tmp/cmd.zip -d ~/Android/Sdk/cmdline-tools && mv ~/Android/Sdk/cmdline-tools/cmdline-tools ~/Android/Sdk/cmdline-tools/latest"
fi
log_ok "ANDROID_HOME=$ANDROID_HOME"

# Verify sdkmanager exists
[[ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]] || die "sdkmanager not found at $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager. Install command-line tools first."
log_ok "sdkmanager found"

# Verify mobile dir
[[ -f "$MOBILE_DIR/package.json" ]] || die "Mobile dir not found: $MOBILE_DIR"
log_ok "Mobile dir: $MOBILE_DIR"

# ========== SDK COMPONENTS ==========
log_step "Ensuring SDK components"

SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"

# ========== SDK COMPONENTS ==========
log_step "Ensuring SDK components"

SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"

# Get installed packages list once
INSTALLED=$("$SDKMANAGER" --list_installed 2>/dev/null | tail -n +5 | awk '{print $1}' | sort -u)

REQUIRED_SDK=(
  "platforms;android-36"
  "build-tools;36.0.0"
  "ndk;27.1.12297006"
  "cmake;3.22.1"
)

for pkg in "${REQUIRED_SDK[@]}"; do
  if echo "$INSTALLED" | grep -q "^${pkg}$"; then
    log_ok "Already installed: $pkg"
  else
    log_warn "Installing $pkg..."
    yes | "$SDKMANAGER" "$pkg" >/dev/null || die "Failed to install $pkg"
  fi
done

# Accept licenses
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || log_warn "License acceptance may need manual intervention"

# ========== LOCAL.PROPERTIES ==========
log_step "Checking local.properties"
if [[ ! -f "$ANDROID_DIR/local.properties" ]] || ! grep -q "sdk.dir" "$ANDROID_DIR/local.properties" 2>/dev/null; then
  log_warn "Creating local.properties..."
  mkdir -p "$ANDROID_DIR"
  echo "sdk.dir=$ANDROID_HOME" > "$ANDROID_DIR/local.properties"
else
  log_ok "local.properties exists"
fi

# ========== ASSETS CHECK ==========
log_step "Verifying assets"
for asset in icon.png adaptive-icon.png splash-icon.png; do
  [[ -f "$MOBILE_DIR/assets/$asset" ]] || die "Missing asset: assets/$asset"
done
log_ok "All assets present"

# ========== PREBUILD ==========
log_step "Expo prebuild"
cd "$MOBILE_DIR"

if [[ ! -d "$ANDROID_DIR" ]] || [[ -z "$(ls -A "$ANDROID_DIR" 2>/dev/null)" ]]; then
  log_warn "Android dir empty, running prebuild..."
  npx expo prebuild --platform android --clean || die "Prebuild failed"
else
  log_ok "Android dir exists, skipping prebuild (use --clean to force)"
fi

# ========== GRADLE BUILD ==========
log_step "Building APK"
cd "$ANDROID_DIR"

# Check gradle wrapper
[[ -x ./gradlew ]] || die "gradlew not executable"

# Clean if requested
if [[ "${1:-}" == "--clean" ]]; then
  log_warn "Cleaning..."
  ./gradlew clean --no-daemon || die "Clean failed"
fi

log_info "Starting Gradle build (this takes a few minutes first time)..."
./gradlew assembleDebug --no-daemon || {
  log_err "Build failed. Common fixes:"
  echo "  1. Check JAVA_HOME points to Java 17 (not 21+): $JAVA_HOME"
  echo "  2. Run: ./gradlew clean && ./gradlew assembleDebug"
  echo "  3. Delete android/ and re-run script"
  echo "  4. Check NDK version in gradle.properties matches installed"
  die "Gradle build failed"
}

# ========== VERIFY OUTPUT ==========
APK_PATH="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
APK_ALIGNED="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug-aligned.apk"

if [[ -f "$APK_PATH" ]]; then
  log_ok "APK built successfully!"
  ls -lh "$APK_PATH"
  
  # Try zipalign if available
  if command -v zipalign >/dev/null 2>&1; then
    zipalign -f -p 4 "$APK_PATH" "$APK_ALIGNED" 2>/dev/null && log_ok "Aligned APK: $APK_ALIGNED"
  fi
  
  echo
  echo "=== INSTALL ON DEVICE ==="
  echo "adb install -r \"$APK_PATH\""
  echo
  echo "=== OR COPY TO PHONE ==="
  echo "cp \"$APK_PATH\" /path/to/phone/Download/"
else
  die "APK not found at $APK_PATH"
fi