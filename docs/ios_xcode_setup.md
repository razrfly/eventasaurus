# Xcode Setup Guide for Eventasaurus iOS App

## Prerequisites

- macOS 13.0 or later
- Xcode 15.0 or later (free from Mac App Store)
- iOS 16.0+ SDK (comes with Xcode)
- Apple Developer Account (free for development, $99/year for App Store)

## Step 1: Install LiveView Native Dependencies

First, add LiveView Native to your Phoenix project:

```bash
# In your Eventasaurus project root
cd /Users/holdenthomas/Code/paid-projects-2025/eventasaurus

# Add dependencies to mix.exs
mix deps.get
```

## Step 2: Create iOS Project Structure

```bash
# Create the native directory structure
mkdir -p native/swiftui
cd native/swiftui

# Clone the LiveView Native iOS template
git clone https://github.com/liveview-native/liveview-client-swiftui.git EventasaurusApp
cd EventasaurusApp

# Remove git history from template
rm -rf .git

# Open in Xcode
open EventasaurusApp.xcodeproj
```

## Step 3: Configure the iOS Project in Xcode

### 3.1 Project Settings
1. Open Xcode and select the project file
2. Change the following settings:
   - **Product Name**: EventasaurusApp
   - **Organization Identifier**: com.eventasaurus
   - **Bundle Identifier**: com.eventasaurus.app
   - **Deployment Target**: iOS 16.0

### 3.2 Add LiveView Native Package
1. In Xcode: File → Add Package Dependencies
2. Add: `https://github.com/liveview-native/liveview-client-swiftui`
3. Version: Up to Next Major Version: 0.3.0

### 3.3 Configure Info.plist
Add these entries for permissions and configurations:

```xml
<key>NSCameraUsageDescription</key>
<string>Eventasaurus needs camera access to take event photos</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Eventasaurus needs photo library access to select event images</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Eventasaurus uses your location to show nearby events</string>

<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

## Step 4: Create the Main App Structure

### 4.1 EventasaurusApp.swift
```swift
import SwiftUI
import LiveViewNative

@main
struct EventasaurusApp: App {
    @State private var connectivityState: ConnectivityState = .connected
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.liveViewServerURL, URL(string: "http://localhost:4000")!)
                .environment(\.connectivityState, connectivityState)
        }
    }
}
```

### 4.2 ContentView.swift
```swift
import SwiftUI
import LiveViewNative

struct ContentView: View {
    @Environment(\.liveViewServerURL) var serverURL
    
    var body: some View {
        TabView {
            // Events Tab
            LiveView(
                path: "/mobile/events",
                serverURL: serverURL
            )
            .tabItem {
                Label("Events", systemImage: "calendar")
            }
            
            // Create Tab
            LiveView(
                path: "/mobile/events/new",
                serverURL: serverURL
            )
            .tabItem {
                Label("Create", systemImage: "plus.circle.fill")
            }
            
            // Tickets Tab
            LiveView(
                path: "/mobile/tickets",
                serverURL: serverURL
            )
            .tabItem {
                Label("Tickets", systemImage: "ticket")
            }
            
            // Profile Tab
            LiveView(
                path: "/mobile/profile",
                serverURL: serverURL
            )
            .tabItem {
                Label("Profile", systemImage: "person.circle")
            }
        }
    }
}
```

## Step 5: Development Workflow

### 5.1 Running Both Servers

You'll need two terminal windows:

**Terminal 1 - Phoenix Server:**
```bash
cd /Users/holdenthomas/Code/paid-projects-2025/eventasaurus
mix phx.server
```

**Terminal 2 - iOS Simulator:**
1. Open Xcode
2. Select target device (iPhone 15 Pro recommended)
3. Press ⌘+R or click the Play button

### 5.2 Live Reload Setup

For hot reloading during development:

1. In Phoenix `config/dev.exs`:
```elixir
config :eventasaurus, EventasaurusWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/eventasaurus_web/(controllers|live|components)/.*(ex|heex|swiftui\.neex)$"
    ]
  ]
```

2. In Xcode, enable automatic refresh:
   - Product → Scheme → Edit Scheme
   - Run → Options → Enable "Allow Location Simulation"

### 5.3 Debugging

**Phoenix Side:**
- Use `IO.inspect/2` in your LiveView modules
- Check `mix phx.routes` for mobile routes
- Monitor WebSocket connections in browser DevTools

**Xcode Side:**
- Use breakpoints in Swift code
- View Console output (Shift+⌘+C)
- Use Network Link Conditioner for testing

## Step 6: Testing Configurations

### 6.1 Simulator Testing
- Test on multiple device sizes
- Use Device → Rotate for orientation
- Test with slow network (Developer menu)

### 6.2 Physical Device Testing
1. Connect iPhone via USB
2. Select your device in Xcode
3. Trust the developer certificate on device
4. Run the app

### 6.3 TestFlight Setup (Later)
1. Archive the app (Product → Archive)
2. Upload to App Store Connect
3. Configure TestFlight beta testing

## Common Development Tasks

### Adding a New Screen

1. **Phoenix Side:**
```elixir
# lib/eventasaurus_web/live/mobile/event_detail_live.ex
defmodule EventasaurusWeb.Mobile.EventDetailLive do
  use EventasaurusWeb, :live_view
  use LiveViewNative.LiveView
  
  @impl true
  def render(%{native: %{platform: :swiftui}} = assigns) do
    # This will use event_detail_live.swiftui.neex
    ~H""
  end
  
  @impl true
  def render(assigns) do
    # Fallback for web
    ~H"<div>Event Detail</div>"
  end
end
```

2. **Template File:**
Create `lib/eventasaurus_web/live/mobile/event_detail_live.swiftui.neex`:
```heex
<VStack>
  <Text font="title"><%= @event.title %></Text>
  <Image url={@event.cover_image_url} />
  <Button phx-click="rsvp">RSVP</Button>
</VStack>
```

3. **Route:**
```elixir
# In router.ex
live "/mobile/events/:slug", Mobile.EventDetailLive, :show
```

### Handling Platform-Specific Features

```elixir
# In your LiveView
def handle_event("take_photo", _params, socket) do
  {:noreply, push_event(socket, "camera:open", %{
    source: "camera",
    quality: 0.8
  })}
end

def handle_event("photo_captured", %{"data" => base64_data}, socket) do
  # Process the photo
  {:noreply, socket}
end
```

## Troubleshooting

### Common Issues

1. **"Could not connect to Phoenix"**
   - Ensure Phoenix is running on port 4000
   - Check Info.plist allows localhost connections
   - Verify firewall settings

2. **"Module not found: LiveViewNative"**
   - Run `mix deps.get` again
   - Clean build folder in Xcode (⇧⌘K)
   - Reset package caches

3. **Layout issues**
   - Use `.swiftui.neex` extension for templates
   - Check LiveView Native documentation for supported modifiers
   - Use Xcode's view hierarchy debugger

### Useful Xcode Shortcuts

- ⌘+R: Run app
- ⌘+.: Stop app
- ⌘+⇧+K: Clean build folder
- ⌘+⇧+O: Open quickly (file search)
- ⌃+⌘+R: Run without building
- ⌘+K: Clear console

## Resources

- [LiveView Native Docs](https://github.com/liveview-native/live_view_native)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Xcode User Guide](https://developer.apple.com/documentation/xcode)
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)

## Next Steps

1. Set up push notifications (requires Apple Developer account)
2. Configure App Store Connect for distribution
3. Implement iOS-specific features (Apple Pay, Wallet)
4. Set up CI/CD with Fastlane