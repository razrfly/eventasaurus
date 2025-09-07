#!/bin/bash

# Image optimization script for Docker build size reduction
# Converts large PNG files to WebP format with 80% quality

set -e

IMAGES_DIR="/Users/holdenthomas/Code/paid-projects-2025/eventasaurus/priv/static/images"
MIN_SIZE="500k"
WEBP_QUALITY=80
BACKUP_DIR="${IMAGES_DIR}/../backup_original_images"

echo "🖼️ Starting image optimization..."
echo "Images directory: $IMAGES_DIR"
echo "Minimum size threshold: $MIN_SIZE"
echo "WebP quality: ${WEBP_QUALITY}%"

# Create backup directory
if [ ! -d "$BACKUP_DIR" ]; then
    echo "📁 Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi

# Find large PNG files
echo "🔍 Finding PNG files larger than $MIN_SIZE..."
LARGE_PNGS=$(find "$IMAGES_DIR" -name "*.png" -size +$MIN_SIZE)

if [ -z "$LARGE_PNGS" ]; then
    echo "✅ No large PNG files found."
    exit 0
fi

echo "📊 Found $(echo "$LARGE_PNGS" | wc -l) large PNG files to optimize"

# Track savings
TOTAL_BEFORE=0
TOTAL_AFTER=0

# Process each large PNG
while IFS= read -r png_file; do
    if [ -f "$png_file" ]; then
        echo "🔄 Processing: $(basename "$png_file")"
        
        # Get original size
        ORIGINAL_SIZE=$(stat -f%z "$png_file" 2>/dev/null || stat -c%s "$png_file" 2>/dev/null)
        TOTAL_BEFORE=$((TOTAL_BEFORE + ORIGINAL_SIZE))
        
        # Create WebP filename
        WEBP_FILE="${png_file%.png}.webp"
        
        # Skip if WebP already exists and is newer
        if [ -f "$WEBP_FILE" ] && [ "$WEBP_FILE" -nt "$png_file" ]; then
            echo "  ⏭️ WebP already exists and is newer, skipping"
            continue
        fi
        
        # Convert to WebP
        if cwebp -q $WEBP_QUALITY "$png_file" -o "$WEBP_FILE" >/dev/null 2>&1; then
            WEBP_SIZE=$(stat -f%z "$WEBP_FILE" 2>/dev/null || stat -c%s "$WEBP_FILE" 2>/dev/null)
            TOTAL_AFTER=$((TOTAL_AFTER + WEBP_SIZE))
            
            # Calculate savings for this file
            SAVINGS=$((ORIGINAL_SIZE - WEBP_SIZE))
            SAVINGS_PCT=$((SAVINGS * 100 / ORIGINAL_SIZE))
            
            echo "  ✅ $(basename "$png_file") → $(basename "$WEBP_FILE")"
            echo "     Size: $(numfmt --to=iec $ORIGINAL_SIZE) → $(numfmt --to=iec $WEBP_SIZE) (${SAVINGS_PCT}% reduction)"
            
            # Move original to backup (instead of deleting)
            BACKUP_PATH="$BACKUP_DIR/$(basename "$png_file")"
            if [ ! -f "$BACKUP_PATH" ]; then
                cp "$png_file" "$BACKUP_PATH"
                echo "     📦 Backed up original to: $(basename "$BACKUP_PATH")"
            fi
            
        else
            echo "  ❌ Failed to convert $(basename "$png_file")"
        fi
    fi
done <<< "$LARGE_PNGS"

# Calculate total savings
if [ $TOTAL_BEFORE -gt 0 ] && [ $TOTAL_AFTER -gt 0 ]; then
    TOTAL_SAVINGS=$((TOTAL_BEFORE - TOTAL_AFTER))
    TOTAL_SAVINGS_PCT=$((TOTAL_SAVINGS * 100 / TOTAL_BEFORE))
    
    echo ""
    echo "📈 OPTIMIZATION SUMMARY:"
    echo "   Original total: $(numfmt --to=iec $TOTAL_BEFORE)"
    echo "   Optimized total: $(numfmt --to=iec $TOTAL_AFTER)"
    echo "   Total savings: $(numfmt --to=iec $TOTAL_SAVINGS) (${TOTAL_SAVINGS_PCT}%)"
    echo ""
    echo "✨ Optimization complete!"
    echo "💡 Remember to update your templates to use .webp files instead of .png"
    echo "📦 Original files backed up to: $BACKUP_DIR"
else
    echo "📊 No files were processed."
fi