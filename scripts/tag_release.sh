#!/bin/bash

# Tag a new release version and push to GitHub

set -e

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v0.6.1"
    exit 1
fi

# Validate version format (v followed by semver)
if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid version format. Expected v0.0.0, got: $VERSION"
    exit 1
fi

echo "Creating tag: $VERSION"
git tag "$VERSION"

echo "Pushing tag to origin..."
git push origin "$VERSION"

echo "✓ Released $VERSION"
