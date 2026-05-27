#!/bin/bash
set -e

# Configuration
APP_NAME="SpotifyLyricsAssistant"
PLIST_PATH="${APP_NAME}/Resources/Info.plist"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"

# Print usage
if [ "$#" -ne 1 ]; then
    echo "用法: $0 <版本号>"
    echo "示例: $0 1.0.5"
    exit 1
fi

NEW_VERSION=$1

echo "========================================"
echo "🚀 开始构建 ${APP_NAME} v${NEW_VERSION}"
echo "========================================"

# 1. Update Info.plist version
echo "📝 更新版本号为 ${NEW_VERSION}..."
# Use PlistBuddy to safely update values
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_VERSION}" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "${PLIST_PATH}"

# 2. Build and Archive
echo "🔨 正在使用 xcodebuild 归档 (Release)..."
xcodebuild -project ${APP_NAME}.xcodeproj \
           -scheme ${APP_NAME} \
           -configuration Release \
           clean build archive \
           -archivePath "${ARCHIVE_PATH}" | xcpretty || xcodebuild -project ${APP_NAME}.xcodeproj -scheme ${APP_NAME} -configuration Release clean build archive -archivePath "${ARCHIVE_PATH}" > /dev/null

# 3. Create DMG
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${NEW_VERSION}.dmg"
echo "📦 正在生成 DMG 安装包..."

# Remove old dmg if exists
rm -f "${DMG_PATH}"

if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "${APP_NAME}" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 150 190 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 450 190 \
        "${DMG_PATH}" \
        "${APP_PATH}"
else
    echo "⚠️  未检测到 create-dmg，使用 macOS 自带 hdiutil 打包..."
    hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_PATH}" -ov -format UDZO "${DMG_PATH}"
fi

echo "========================================"
echo "✅ 构建成功!"
echo "📂 DMG 路径: ${DMG_PATH}"
echo "========================================"
