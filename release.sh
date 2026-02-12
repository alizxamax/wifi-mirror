#!/bin/bash
set -euo pipefail

# Create and push a git tag that matches pubspec.yaml version.
# Usage:
#   ./release.sh                # uses pubspec version (e.g. 1.2.0 -> v1.2.0)
#   ./release.sh v1.2.1         # override tag explicitly

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [tag]"
  exit 1
fi

if [[ $# -eq 1 ]]; then
  TAG="$1"
else
  VERSION=$(awk '/^version:/ {split($2,a,"+"); print a[1]; exit}' pubspec.yaml)
  if [[ -z "${VERSION:-}" ]]; then
    echo "Could not parse version from pubspec.yaml"
    exit 1
  fi
  TAG="v${VERSION}"
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists locally."
  exit 1
fi

echo "Creating release tag: $TAG"
git tag "$TAG"
git push origin "$TAG"

echo "Done. GitHub Actions release workflow should trigger for $TAG."
