#!/bin/bash

# Build Flutter Web and copy to assets folder
# This script builds the web version and copies it to assets/web_app for serving via local HTTP server

echo "🔨 Building Flutter Web..."

# Build web with optimizations
flutter build web --release

if [ $? -ne 0 ]; then
    echo "❌ Web build failed!"
    exit 1
fi

echo "✅ Web build completed!"

# Create assets/web_app directory if it doesn't exist
mkdir -p assets/web_app

# Remove old web app files
echo "🧹 Cleaning old web app assets..."
rm -rf assets/web_app/*

# Copy the web build to assets
echo "📦 Copying web build to assets/web_app..."
cp -r build/web/* assets/web_app/

if [ $? -ne 0 ]; then
    echo "❌ Failed to copy web build!"
    exit 1
fi

# Generate a manifest file listing all files for reliable extraction at runtime
echo "📋 Generating file manifest..."
cd assets/web_app
find . -type f | sed 's|^\./||' > web_app_manifest.txt
cd ../..

echo "✅ Web app copied to assets/web_app/"
echo ""
echo "📝 Next steps:"
echo "   1. The pubspec.yaml should already include the web_app assets"
echo "   2. Run 'flutter pub get' to refresh assets"
echo "   3. Build the native app (Mac/Android) to include the web app"
echo ""
echo "🎉 Done! The web app is ready to be served from the native app."
