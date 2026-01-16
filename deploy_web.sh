#!/bin/bash

# Build the web app
flutter build web --base-href "/wifi-mirror/" --release

# Navigate to build output
cd build/web

# Initialize a new git repo for deployment
git init
git add .
git commit -m "Deploy to GitHub Pages"
git branch -M gh-pages

# Add remote and push
git remote remove origin 2>/dev/null || true
git remote add origin https://github.com/navneetprajapati26/wifi-mirror.git
git push -f origin gh-pages

# Return to root
cd ../..

echo "Deployed to https://navneetprajapati26.github.io/wifi-mirror/"
