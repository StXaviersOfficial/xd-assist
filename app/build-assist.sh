#!/bin/bash
# build-assist.sh — build the XD Assist APK (com.stxaviers.assist 1.0.2 / code 3).
# Flat pipeline, NO Gradle, NO dependencies (framework + org.json only):
#   aapt2 compile+link → javac → d8 → zip → zipalign → apksigner
set -e

# S26: portable paths — PROJ is always the folder this script lives in,
# SDK/JDK/keystore can be overridden via env (works on any machine).
SDK="${ANDROID_SDK:-/tmp/my-project/android-sdk}"
BT=$SDK/build-tools/35.0.0
PLATFORM=$SDK/platforms/android-34/android.jar
JDK="${JAVA_HOME:-/usr}"
PROJ="$(cd "$(dirname "$0")" && pwd)"
OUT=$PROJ/build
KS="${XD_KEYSTORE:-/home/z/my-project/.secure/upload-keystore.jks}"
if [ ! -f "$KS" ] && [ -f /home/z/my-project/.secure/keystore.jks ]; then
  KS=/home/z/my-project/.secure/keystore.jks
fi
KSPASS="${XD_KEYSTORE_PASS:-$(cat /home/z/my-project/.secure/keystore.password)}"

rm -rf "$OUT"
mkdir -p "$OUT/compiled" "$OUT/gen" "$OUT/classes"

echo "[1/5] aapt2 compile + link…"
"$BT/aapt2" compile --dir "$PROJ/res" -o "$OUT/res.zip"
"$BT/aapt2" link -o "$OUT/base.apk" \
    -I "$PLATFORM" \
    --manifest "$PROJ/AndroidManifest.xml" \
    --java "$OUT/gen" \
    --auto-add-overlay \
    "$OUT/res.zip"

echo "[2/5] javac…"
find "$PROJ/src" -name "*.java" > "$OUT/sources.txt"
"$JDK/bin/javac" --release 8 -nowarn \
    -classpath "$PLATFORM" \
    -d "$OUT/classes" \
    @"$OUT/sources.txt" "$OUT/gen/com/stxaviers/assist/R.java"

echo "[3/5] d8…"
find "$OUT/classes" -name "*.class" > "$OUT/classes.txt"
"$BT/d8" --release --min-api 24 --lib "$PLATFORM" \
    --output "$OUT" \
    $(cat "$OUT/classes.txt")

echo "[4/5] package + zipalign…"
cp "$OUT/base.apk" "$OUT/assist-unsigned.apk"
cd "$OUT" && zip -q -j assist-unsigned.apk classes.dex
"$BT/zipalign" -f 4 "$OUT/assist-unsigned.apk" "$OUT/assist-aligned.apk"

echo "[5/5] apksigner…"
"$BT/apksigner" sign \
    --ks "$KS" --ks-pass "pass:$KSPASS" \
    --ks-key-alias stxaviers-upload \
    --out "$OUT/xdassist-1.0.2.apk" \
    "$OUT/assist-aligned.apk"
"$BT/apksigner" verify --print-certs "$OUT/xdassist-1.0.2.apk" | head -4

echo "DONE: $OUT/xdassist-1.0.2.apk ($(stat -c%s "$OUT/xdassist-1.0.2.apk") bytes)"
sha256sum "$OUT/xdassist-1.0.2.apk"
