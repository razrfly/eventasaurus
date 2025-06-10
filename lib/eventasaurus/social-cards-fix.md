# Social Card Image Rendering Issue - FIXED ✅

## Problem Summary

Social card images work correctly with **external images** (Unsplash, movie database URLs) but **local filesystem images fail to render** in the generated PNG output.

**STATUS: FIXED** - The issue has been resolved by implementing base64 data URL embedding.

## Root Cause Identified

The issue was that `rsvg-convert` does **not process `file://` URL references** in SVG when converting to PNG. While the SVG was generated correctly with the proper file paths, the conversion step failed to include the actual image content.

## Solution Implemented

**Base64 Data URL Embedding**: Instead of using `file://` URLs, local images are now converted to base64 data URLs and embedded directly in the SVG. This approach:

1. ✅ Works with `rsvg-convert` 
2. ✅ Handles both local and external images
3. ✅ Eliminates file path dependencies
4. ✅ Maintains image quality
5. ✅ Provides proper cleanup of temporary files

## Code Changes Made

### 1. New Function in `SocialCardView`
Added `local_image_data_url/1` function that:
- Reads image files from filesystem
- Converts to base64 encoding
- Creates proper data URLs with MIME type detection
- Cleans up temporary downloaded files

### 2. Updated Controller Logic
Modified `EventSocialCardController` to use data URLs instead of file paths:
```elixir
# Before (broken)
<image href="file://#{local_path}" ... />

# After (working)  
<image href="#{data_url}" ... />
```

## Results

### Before Fix
- **File Size**: 29KB (image not included)
- **Status**: ❌ Broken - only background and text rendered

### After Fix  
- **File Size**: 204KB (image properly included)
- **Status**: ✅ Working - full social card with image

## Test Results

All scenarios now work correctly:
1. ✅ **Local Images**: 2.6MB data URL generated successfully
2. ✅ **External Images**: 37KB data URL generated successfully  
3. ✅ **Invalid Images**: Graceful fallback to "No Image" placeholder
4. ✅ **No Images**: Proper handling of nil values

## Files Modified

1. `lib/eventasaurus_web/views/social_card_view.ex`
   - Added `local_image_data_url/1` function
   - Added automatic cleanup for temporary files

2. `lib/eventasaurus_web/controllers/event_social_card_controller.ex`
   - Updated image section generation to use data URLs
   - Updated comments to reflect the fix

## Performance Considerations

- **Memory Usage**: Base64 encoding increases data size by ~33%, but this is acceptable for social card generation
- **Processing Time**: Slight increase due to base64 conversion, but negligible for the use case
- **Cleanup**: Temporary downloaded files are automatically cleaned up after conversion

## Backward Compatibility

✅ **Fully backward compatible** - no changes needed to existing event data or image URLs.

---

## Original Investigation Details

### What Works vs What Doesn't Work

### ✅ Working: External Images
- External URLs from Unsplash, movie databases, etc.
- Images are downloaded locally and processed correctly
- Final PNG contains the actual image content
- Larger file sizes reflecting the image content

### ❌ Not Working: Local Images  
- Local images stored in `/priv/static/images/events/` # eg /invites
- Images exist on filesystem (verified 2.2MB files)
- SVG generation includes correct `<image href="file://...">` tags
- Final PNG does NOT contain the image content (small file size ~22-29KB)

## Technical Investigation Findings

### File Locations
- **Controller**: `lib/eventasaurus_web/controllers/event_social_card_controller.ex`
- **View Helpers**: `lib/eventasaurus_web/views/social_card_view.ex`
- **Local Image Path**: `/Users/holdenthomas/Code/paid-projects-2025/eventasaurus/priv/static/images/events/invites/u6742974658_Create_abstract_invitation_related_images_--ar_11_9838e417-fe6a-4f2e-bcab-8537775ca423_1.png`

### Test Event Details
- **Event Slug**: `h5ijwt8dtx`
- **Event Title**: "Monkey town"
- **Theme**: `:minimal`
- **Local Image File Size**: 2,275,764 bytes (2.2MB)
- **Current Social Card URL**: `http://localhost:4000/events/h5ijwt8dtx/social-card-70fc02ee.png`

### Code Flow Verification

1. **Image Detection**: ✅ `has_image?(event)` returns `true`
2. **Path Resolution**: ✅ `local_image_path(event)` returns correct filesystem path
3. **File Existence**: ✅ File exists at resolved path
4. **SVG Generation**: ✅ SVG contains proper `<image href="file://[full_path]">` tag
5. **PNG Conversion**: ⚠️ `rsvg-convert` succeeds but produces small output

### Evidence

#### Generated SVG Content (Correct)
```xml
<image href="file:///Users/holdenthomas/Code/paid-projects-2025/eventasaurus/priv/static/images/events/invites/u6742974658_Create_abstract_invitation_related_images_--ar_11_9838e417-fe6a-4f2e-bcab-8537775ca423_1.png"
       x="418" y="32"
       width="350" height="350"
       clip-path="url(#imageClip)"
       preserveAspectRatio="xMidYMid slice"/>
```

#### File Size Comparison
- **Expected**: Large file size (should reflect 2.2MB source image)
- **Actual**: 29,195 bytes (29KB) - indicates image not rendered
- **External Images**: Produce appropriately larger file sizes

#### Server Response
```
HTTP/1.1 200 OK
content-type: image/png; charset=utf-8
content-length: 29195
```

### Root Cause Analysis

The issue appears to be that `rsvg-convert` is **not processing the `file://` URL references** in the SVG when converting to PNG. While the SVG is generated correctly with the proper file paths, the conversion step fails to include the actual image content.

### Potential Solutions

1. **Base64 Embedding**: Convert local images to base64 data URLs in SVG instead of file paths
2. **HTTP Serving**: Serve local images via HTTP URLs instead of file paths
3. **Copy to Temp**: Copy images to temporary directory with simpler paths
4. **rsvg-convert Debugging**: Investigate rsvg-convert command-line options for file handling

### Code References

#### Controller Logic (Line ~89-103)
```elixir
image_section = if has_image?(event) do
  case local_image_path(event) do
    nil ->
      # Fallback to "No Image"
    local_path ->
      """
      <image href="file://#{local_path}"
             x="418" y="32"
             width="350" height="350"
             clip-path="url(#imageClip)"
             preserveAspectRatio="xMidYMid slice"/>
      """
  end
```

#### Helper Function (SocialCardView, Line 124-154)
```elixir
def local_image_path(%{cover_image_url: url}) do
  case Sanitizer.validate_image_url(url) do
    nil -> nil
    valid_url ->
      if String.starts_with?(valid_url, "/") do
        # Handle local static file path with security validation
        # Returns canonical filesystem path
      else
        # Handle external URL - download it
      end
  end
end
```

## Next Steps

1. **Investigate rsvg-convert behavior** with file:// URLs
2. **Implement base64 embedding** for local images
3. **Test with simplified file paths** 
4. **Add proper error handling** for image conversion failures
5. **Consider alternative SVG to PNG conversion methods**

## Environment Details

- **OS**: macOS (Darwin 24.5.0)
- **Elixir**: 1.18.3
- **Phoenix**: Current version
- **rsvg-convert**: Installed and functional
- **Project**: Eventasaurus social card generation 