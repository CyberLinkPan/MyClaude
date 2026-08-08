#!/bin/bash
# 构建 MyClaude.app（仅需 Command Line Tools，无需 Xcode）
set -e
cd "$(dirname "$0")"

APP="MyClaude.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 修复 CLT 混装问题：用 VFS overlay 屏蔽残留的 swift/module.modulemap（SwiftBridging 重复定义），
# 并用显式模块构建让 overlay 传递到所有模块子编译。
FIX_DIR="$(cd "$(dirname "$0")" && pwd)/toolchain-fix"
mkdir -p "$FIX_DIR"
printf '// 空文件：SwiftBridging 已由 bridging.modulemap 定义（修复 CLT 混装残留）\n' > "$FIX_DIR/empty.modulemap"
cat > "$FIX_DIR/overlay.yaml" <<EOF
{
  "version": 0,
  "case-sensitive": "false",
  "roots": [
    {
      "name": "/Library/Developer/CommandLineTools/usr/include/swift",
      "type": "directory",
      "contents": [
        { "name": "module.modulemap", "type": "file", "external-contents": "$FIX_DIR/empty.modulemap" }
      ]
    }
  ]
}
EOF

swiftc -O -explicit-module-build -Xcc -ivfsoverlay -Xcc "$FIX_DIR/overlay.yaml" \
    -o "$APP/Contents/MacOS/MyClaude" Sources/*.swift

# 生成 App 图标（Clawd）和菜单栏图标
ICON_TMP="$FIX_DIR/icons"
rm -rf "$ICON_TMP"; mkdir -p "$ICON_TMP"
"$APP/Contents/MacOS/MyClaude" --icon "$ICON_TMP" >/dev/null
ICONSET="$ICON_TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s*2))
    sips -z $d $d "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$ICON_TMP/menubar.png" "$APP/Contents/Resources/MenuIcon.png"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MyClaude</string>
    <key>CFBundleIdentifier</key><string>local.myclaude</string>
    <key>CFBundleName</key><string>MyClaude</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force -s - "$APP" 2>/dev/null || true
echo "构建完成: $PWD/$APP"
