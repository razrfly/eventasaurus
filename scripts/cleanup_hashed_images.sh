#!/bin/bash

# Script to remove hashed image files from the static assets directory
# These are created by mix assets.deploy but should not be in version control

# Check if directory exists
if [ ! -d "priv/static/images/events" ]; then
    echo "Error: Directory priv/static/images/events not found"
    echo "Please run this script from the project root directory"
    exit 1
fi

echo "Finding and removing hashed image files..."

# Pattern matches files with 32-character hex hash before the extension
# Example: high-five-dino-f63c0c4dafcc5578b3ed557795297793.png

# Dry-run mode if --dry-run is passed
if [ "$1" = "--dry-run" ]; then
    echo "Dry-run mode: Files that would be deleted:"
    find priv/static/images/events -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" -o -name "*.webp" -o -name "*.svg" \) | grep -E "\-[a-f0-9]{32}\."
else
    find priv/static/images/events -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" -o -name "*.webp" -o -name "*.svg" \) | grep -E "\-[a-f0-9]{32}\." | xargs -r rm -f
fi

echo "Cleanup complete!"
echo ""
echo "To prevent this issue in the future:"
echo "1. Add these patterns to .gitignore"
echo "2. Only commit original image files"
echo "3. Let Phoenix handle asset fingerprinting in production"