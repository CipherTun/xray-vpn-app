#!/usr/bin/env bash
# Generates android/ + ios/ with the io.surprise.vpn identity, then overlays the
# hand-written native code from native/. Run from anywhere. Needs Flutter on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  flutter create --org io.surprise --project-name vpn --platforms android,ios --no-pub .
fi
rm -f test/widget_test.dart

# ---- Android overlay (manifest, MainActivity, VpnService) ----
cp -r native/android/. android/
mkdir -p android/app/libs

python3 - <<'PY'
import os, re
kts, groovy = 'android/app/build.gradle.kts', 'android/app/build.gradle'
if os.path.exists(kts):
    s = open(kts).read()
    s = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 26', s)
    if 'fileTree' not in s:
        s += '\ndependencies {\n    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar", "*.jar"))))\n}\n'
    open(kts, 'w').write(s)
elif os.path.exists(groovy):
    s = open(groovy).read()
    s = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 26', s)
    if 'fileTree' not in s:
        s += "\ndependencies {\n    implementation fileTree(dir: 'libs', include: ['*.aar', '*.jar'])\n}\n"
    open(groovy, 'w').write(s)
print('android gradle patched')
PY

echo "Bootstrap done. Put libXray.aar in android/app/libs/ before building."
