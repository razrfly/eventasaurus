# Theme System Audit & Fix Specification

## Executive Summary

The Eventasaurus theme system is currently broken due to architectural conflicts between the Radiant base theme and the 7-theme system. While the infrastructure exists for distinct themes (minimal, cosmic, velocity, retro, celebration, nature, professional), only the minimal theme works correctly. The other 6 themes are not applying their distinct styling due to CSS loading conflicts, missing theme application logic, and incomplete integration between the theme selection and rendering systems.

## Current State Analysis

### ✅ What's Working
1. **Theme Infrastructure**: All 7 themes are properly defined in `EventasaurusApp.Themes` module
2. **Theme Selection**: Event creation form includes theme dropdown with all options
3. **CSS Definitions**: Individual theme CSS files exist with distinct styling
4. **Database Schema**: Events table has `theme` enum field and `theme_customizations` JSONB field
5. **Minimal Theme**: Works correctly (uses default Radiant styling)

### ❌ What's Broken
1. **Theme Application**: Event themes are not being applied to public event pages
2. **CSS Loading Conflicts**: Duplicate theme definitions in `app.css` and individual theme files
3. **Missing Theme Context**: Public event pages don't receive theme information
4. **Font Loading**: Google Fonts for themes not properly applied
5. **Animation Systems**: Theme-specific animations not activating

## Root Cause Analysis

### 1. Theme Application Gap
**Issue**: Public event pages don't apply event-specific themes
- `PublicEventLive` loads event data but doesn't apply theme to layout
- `AuthHooks.assign_auth_user_and_theme` only assigns generic "light" theme
- No connection between `event.theme` and page rendering

### 2. CSS Architecture Conflicts
**Issue**: Competing CSS definitions causing specificity problems
- `app.css` contains complete theme definitions (lines 200-344)
- Individual theme files in `assets/css/themes/` have separate implementations
- Root layout conditionally loads theme CSS files, but `app.css` already loaded
- CSS custom properties system not properly utilized

### 3. Missing Theme Context Propagation
**Issue**: Theme information doesn't flow from event to layout
- Root layout expects `assigns[:theme]` and `assigns[:theme_class]`
- Public event pages don't set these assigns
- No mechanism to pass event theme to root layout

## Detailed Technical Analysis

### Current CSS Structure
```
app.css (always loaded)
├── Base Radiant styles
├── CSS custom properties system
└── Complete theme definitions for all 7 themes

themes/[theme].css (conditionally loaded)
├── Duplicate theme definitions
├── Some unique animations
└── Conflicting specificity
```

### Current Theme Flow
```
Event Creation → theme selected → stored in DB
                                      ↓
Public Event Page → event loaded → theme ignored
                                      ↓
Root Layout → generic "light" theme → Radiant default
```

### Expected Theme Flow
```
Event Creation → theme selected → stored in DB
                                      ↓
Public Event Page → event loaded → theme applied to layout
                                      ↓
Root Layout → event theme → distinct styling + animations
```

## Fix Specification

### Phase 1: CSS Architecture Consolidation

#### 1.1 Consolidate Theme Definitions
- **Action**: Move all theme definitions to individual theme files
- **Remove**: Theme definitions from `app.css` (lines 200-344)
- **Keep**: Base CSS custom properties system in `app.css`
- **Result**: Single source of truth for each theme

#### 1.2 Standardize CSS Custom Properties
Each theme file should define:
```css
.theme-[name] {
  /* Core Colors */
  --color-primary: #value;
  --color-secondary: #value;
  --color-accent: #value;
  --color-background: #value;
  --color-text: #value;
  --color-text-secondary: #value;
  --color-border: #value;
  
  /* Typography */
  --font-family: "Font Name";
  --font-family-heading: "Heading Font";
  --font-weight-heading: 600;
  --font-size-body: 16px;
  --font-weight-body: 400;
  
  /* Layout */
  --border-radius: 8px;
  --border-radius-large: 16px;
  --button-border-radius: 8px;
  --card-border-radius: 16px;
  --input-border-radius: 6px;
}
```

#### 1.3 Theme-Specific Features
Each theme should include:
- **Cosmic**: Animated starfield background, swirling galaxies, glow effects
- **Velocity**: Dynamic gradients, transform animations, tech aesthetics
- **Retro**: Vintage color schemes, serif fonts, warm glow animations
- **Celebration**: Bright colors, floating confetti animations, festive elements
- **Nature**: Earth tones, organic patterns, subtle nature animations
- **Professional**: Clean corporate styling, conservative colors, minimal animations

### Phase 2: Theme Application Logic

#### 2.1 Update PublicEventLive
```elixir
def mount(%{"slug" => slug}, _session, socket) do
  case Events.get_event_by_slug(slug) do
    %Event{theme: theme} = event ->
      socket
      |> assign(:event, event)
      |> assign(:theme, theme)
      |> assign(:theme_class, Themes.get_theme_css_class(theme))
      |> assign(:css_variables, Themes.get_theme_css_variables(theme))
      # ... other assigns
  end
end
```

#### 2.2 Update Root Layout Theme Application
```heex
<body class={[
    "bg-white antialiased overflow-x-hidden min-h-screen flex flex-col",
    assigns[:theme_class] || "theme-minimal"
  ]}
  style={assigns[:css_variables]}
>
```

#### 2.3 Enhanced Theme Helpers
```elixir
defmodule EventasaurusWeb.ThemeHelpers do
  def get_theme_css_variables(theme) do
    customizations = Themes.get_default_customizations(theme)
    # Convert to CSS custom properties string
  end
  
  def get_theme_font_links(theme) do
    # Return Google Fonts links for theme
  end
  
  def get_theme_animations(theme) do
    # Return theme-specific animation classes
  end
end
```

### Phase 3: Enhanced Theme Features

#### 3.1 Background Systems
- **Cosmic**: Animated starfield with CSS animations
- **Velocity**: Dynamic gradient backgrounds
- **Retro**: Textured backgrounds with warm overlays
- **Celebration**: Animated confetti or floating elements
- **Nature**: Subtle organic patterns
- **Professional**: Clean gradients or solid colors

#### 3.2 Animation Integration
```css
/* Cosmic Theme Animations */
.theme-cosmic .cosmic-background {
  animation: cosmicSwirl 20s linear infinite;
}

@keyframes cosmicSwirl {
  0% { transform: rotate(0deg) scale(1); }
  50% { transform: rotate(180deg) scale(1.1); }
  100% { transform: rotate(360deg) scale(1); }
}
```

#### 3.3 Font Loading Optimization
```elixir
def theme_font_links() do
  fonts = %{
    cosmic: "Orbitron:400,700",
    velocity: "Exo+2:400,600,700",
    retro: "Georgia", # System font
    celebration: "Inter:400,600,700",
    nature: "Inter:400,600",
    professional: "Inter:400,600"
  }
  # Generate Google Fonts links
end
```

### Phase 4: Testing & Validation

#### 4.1 Theme Validation Tests
- Each theme renders with distinct colors
- Fonts load correctly for each theme
- Animations work as expected
- CSS custom properties apply correctly
- No CSS conflicts between themes

#### 4.2 Integration Tests
- Event creation saves theme correctly
- Public event pages apply event theme
- Theme switching works in real-time
- Fallback to minimal theme works

## Implementation Priority

### High Priority (Fix Core Functionality)
1. Remove duplicate CSS definitions from `app.css`
2. Update `PublicEventLive` to apply event themes
3. Fix root layout theme application
4. Ensure minimal theme continues working

### Medium Priority (Enhance Features)
1. Implement theme-specific animations
2. Optimize font loading
3. Add CSS custom properties system
4. Create theme preview system

### Low Priority (Polish)
1. Add theme customization interface
2. Implement theme inheritance
3. Add dark mode variants
4. Create theme migration tools

## Success Criteria

1. **Functional**: All 7 themes render with distinct appearance
2. **Performance**: No CSS conflicts or loading issues
3. **Maintainable**: Single source of truth for each theme
4. **Extensible**: Easy to add new themes or modify existing ones
5. **Backward Compatible**: Existing events continue working

## Risk Mitigation

1. **CSS Conflicts**: Test thoroughly in different browsers
2. **Performance**: Monitor CSS bundle size and loading times
3. **Accessibility**: Ensure all themes meet WCAG guidelines
4. **Mobile**: Test responsive behavior for all themes
5. **Fallbacks**: Ensure graceful degradation when themes fail to load

## Next Steps

1. Create backup of current CSS files
2. Implement Phase 1 (CSS consolidation)
3. Test minimal theme still works
4. Implement Phase 2 (theme application)
5. Test all themes render correctly
6. Implement Phase 3 (enhanced features)
7. Comprehensive testing across all themes
8. Deploy and monitor for issues

This specification provides a complete roadmap to restore the 7-theme system while maintaining the Radiant base design and ensuring each theme has distinct, functional characteristics. 