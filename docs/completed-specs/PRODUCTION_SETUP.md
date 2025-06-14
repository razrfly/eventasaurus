# Production Setup Guide

## Required System Dependencies

The social card generation feature requires `rsvg-convert` to be installed on the production server.

### Installing rsvg-convert

**For Ubuntu/Debian servers:**
```bash
sudo apt-get update
sudo apt-get install librsvg2-bin
```

**For Alpine Linux (common in Docker):**
```bash
apk add --no-cache librsvg
```

**For CentOS/RHEL/Amazon Linux:**
```bash
sudo yum install librsvg2-tools
# or for newer versions:
sudo dnf install librsvg2-tools
```

**For macOS (development):**
```bash
brew install librsvg
```

### Verification

After installation, verify the command is available:
```bash
rsvg-convert --version
```

Expected output should show version information like:
```
rsvg-convert 2.56.3
```

### Current Production Error

The app is failing with:
```
** (ErlangError) Erlang error: :enoent
System.cmd("rsvg-convert", [...])
```

This indicates `rsvg-convert` is not installed on the production server.

### Testing Social Cards

After installing the dependency, test a social card URL:
```bash
curl -I https://eventasaur.us/events/[event-slug]/social-card-[hash].png
```

Should return `200 OK` with `content-type: image/png`.

### Error Handling

The app now includes better error handling:
- Missing `rsvg-convert` returns "Social card generation unavailable" instead of crashing
- Proper dependency checking before attempting conversion
- Graceful fallback with appropriate HTTP error codes

### Fly.io Deployment

✅ **FIXED**: The `Dockerfile` has been updated to include `librsvg2-bin` in the runtime dependencies.

The fix is in this line:
```dockerfile
apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates librsvg2-bin
```

To deploy the fix:
```bash
fly deploy
```

This will rebuild the Docker image with `rsvg-convert` available, fixing the social card generation issue. 