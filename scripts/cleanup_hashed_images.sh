#!/bin/bash

# Script to remove hashed image files from the static assets directory
# These are created by mix assets.deploy but should not be in version control

echo "Finding and removing hashed image files..."

# Pattern matches files with 32-character hex hash before the extension
# Example: high-five-dino-f63c0c4dafcc5578b3ed557795297793.png

find priv/static/images/events -type f -regex ".*-[a-f0-9]\{32\}\.\(png\|jpg\|jpeg\|gif\|webp\)" -print -delete

echo "Cleanup complete!"
echo ""
echo "To prevent this issue in the future:"
echo "1. Add these patterns to .gitignore"
echo "2. Only commit original image files"
echo "3. Let Phoenix handle asset fingerprinting in production"