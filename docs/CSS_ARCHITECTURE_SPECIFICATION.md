# CSS Theme Architecture Specification

## Overview

This document defines the new CSS architecture for the Eventasaurus theme system that separates universal theme properties (backgrounds, animations) from selective font application (content areas only).

## Core Principles

### 1. Separation of Concerns
- **Universal Elements**: Apply to entire page (backgrounds, CSS variables, animations)
- **Selective Elements**: Apply only to designated content areas (fonts, text styling)
- **Protected Elements**: Never receive theme styling (navbar, footer, notifications)

### 2. Semantic CSS Classes
- Use meaningful, descriptive class names that indicate purpose
- Avoid generic wrapper classes that pollute the DOM
- Clear distinction between layout and theming responsibilities

### 3. CSS Variable Strategy
- All theme properties defined as CSS variables on theme root
- Variables can be used throughout the application
- Font variables only applied to designated content selectors

## Architecture Implementation

### CSS Selector Strategy

#### Universal Theme Application
```css
/* Theme root - defines variables and universal styling */
.theme-cosmic {
  /* CSS Variables available throughout app */
  --color-primary: #6366f1;
  --color-secondary: #8b5cf6;
  --color-accent: #06b6d4;
  --color-background: #0a0a0f;
  --color-text: #f8fafc;
  --color-text-secondary: #cbd5e1;
  --color-border: #334155;
  
  /* Typography variables (for selective application) */
  --font-family: 'Orbitron', 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  --font-family-heading: 'Orbitron', 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  --font-weight-heading: 700;
  
  /* Layout variables */
  --border-radius: 12px;
  --border-radius-large: 16px;
  --shadow-style: 0 4px 12px rgba(99, 102, 241, 0.25);
  --shadow-style-large: 0 8px 32px rgba(99, 102, 241, 0.35);
  
  /* Universal background and effects */
  background: #0a0a0f;
  color: #f8fafc;
  position: relative;
  overflow-x: hidden;
}

/* Universal background animations */
.theme-cosmic::before {
  content: '';
  position: fixed;
  top: 0;
  left: 0;
  width: 200%;
  height: 200%;
  background-image: 
    radial-gradient(2px 2px at 20px 30px, #eee, transparent),
    radial-gradient(2px 2px at 40px 70px, rgba(255,255,255,0.8), transparent),
    radial-gradient(1px 1px at 90px 40px, #fff, transparent),
    radial-gradient(1px 1px at 130px 80px, rgba(255,255,255,0.6), transparent),
    radial-gradient(2px 2px at 160px 30px, #ddd, transparent);
  background-repeat: repeat;
  background-size: 200px 100px;
  animation: cosmicStars 20s linear infinite;
  z-index: -1;
  opacity: 0.6;
}

@keyframes cosmicStars {
  from { transform: translateX(0) translateY(0); }
  to { transform: translateX(-200px) translateY(-100px); }
}
```

#### Selective Font Application
```css
/* Scoped font application - ONLY to designated content areas */
.theme-cosmic .main-content,
.theme-cosmic .event-content,
.theme-cosmic .dashboard-content,
.theme-cosmic .user-content,
.theme-cosmic .auth-content {
  font-family: var(--font-family);
  color: var(--color-text);
}

/* Content area descendants inherit theme fonts */
.theme-cosmic .main-content *,
.theme-cosmic .event-content *,
.theme-cosmic .dashboard-content *,
.theme-cosmic .user-content *,
.theme-cosmic .auth-content * {
  color: var(--color-text) !important;
}

/* Specific element styling within content areas */
.theme-cosmic .main-content h1,
.theme-cosmic .main-content h2,
.theme-cosmic .main-content h3,
.theme-cosmic .event-content h1,
.theme-cosmic .event-content h2,
.theme-cosmic .event-content h3 {
  font-family: var(--font-family-heading);
  font-weight: var(--font-weight-heading);
}
```

### Semantic Class Structure

#### Content Area Classes
```html
<!-- Main content wrapper -->
<main class="flex-grow main-content">
  <!-- Primary page content -->
</main>

<!-- Event-specific content -->
<div class="event-content">
  <!-- Event pages and components -->
</div>

<!-- Dashboard content -->
<div class="dashboard-content">
  <!-- Dashboard and analytics -->
</div>

<!-- User profile content -->
<div class="user-content">
  <!-- User profiles and account pages -->
</div>

<!-- Authentication content -->
<div class="auth-content">
  <!-- Login, register, auth flows -->
</div>
```

#### Protected Area Classes (Never Themed)
```html
<!-- Navigation - maintains Inter font -->
<header class="navbar">
  <!-- Navigation elements -->
</header>

<!-- Footer - maintains Inter font -->
<footer class="footer">
  <!-- Footer content -->
</footer>

<!-- Notifications - maintain Inter font -->
<div class="toast">
  <!-- Toast notifications -->
</div>

<!-- Modal headers - maintain Inter font -->
<div class="modal-header">
  <!-- Modal titles and controls -->
</div>

<!-- System UI - maintain Inter font -->
<div class="system-ui">
  <!-- Loading states, error messages, etc. -->
</div>
```

### Layout Structure Changes

#### Remove .theme-content Wrapper

**Before (Problematic):**
```html
<body class="theme-cosmic">
  <header class="navbar"><!-- Protected --></header>
  <main class="flex-grow">
    <div class="theme-content">  <!-- REMOVE THIS WRAPPER -->
      <%= @inner_content %>
    </div>
  </main>
  <footer class="footer"><!-- Protected --></footer>
</body>
```

**After (Clean):**
```html
<body class="theme-cosmic">
  <header class="navbar"><!-- Protected --></header>
  <main class="flex-grow main-content">  <!-- Direct semantic class -->
    <%= @inner_content %>
  </main>
  <footer class="footer"><!-- Protected --></footer>
</body>
```

#### Template-Specific Content Classes
```html
<!-- Event show/edit pages -->
<div class="event-content">
  <div class="container mx-auto px-4 py-8">
    <!-- Event content here -->
  </div>
</div>

<!-- Dashboard pages -->
<div class="dashboard-content">
  <div class="container mx-auto px-4 py-8">
    <!-- Dashboard content here -->
  </div>
</div>

<!-- User profile pages -->
<div class="user-content">
  <div class="container mx-auto px-4 py-8">
    <!-- Profile content here -->
  </div>
</div>
```

## Theme-Specific Implementations

### Cosmic Theme (Space/Sci-Fi)
```css
.theme-cosmic {
  /* Universal variables and background */
  --font-family: 'Orbitron', 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  --color-primary: #6366f1;
  --color-background: #0a0a0f;
  
  background: #0a0a0f;
  /* Starfield animation */
}

/* Selective font application */
.theme-cosmic .main-content,
.theme-cosmic .event-content,
.theme-cosmic .dashboard-content {
  font-family: var(--font-family);
}

/* Content-specific effects */
.theme-cosmic .main-content .bg-white {
  background: rgba(30, 41, 59, 0.8) !important;
  backdrop-filter: blur(8px);
  border: 1px solid rgba(99, 102, 241, 0.3) !important;
}
```

### Professional Theme (Corporate)
```css
.theme-professional {
  /* Universal variables and background */
  --font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  --color-primary: #1f2937;
  --color-background: #ffffff;
  
  background: linear-gradient(to bottom, #f8fafc, #e2e8f0);
}

/* Selective font application - minimal change since using Inter */
.theme-professional .main-content,
.theme-professional .event-content,
.theme-professional .dashboard-content {
  font-family: var(--font-family);
}
```

### Retro Theme (80s/Neon)
```css
.theme-retro {
  /* Universal variables and background */
  --font-family: 'Courier New', 'SF Mono', Monaco, 'Cascadia Code', monospace;
  --color-primary: #ff6b6b;
  --color-background: #1a1a2e;
  
  background: linear-gradient(45deg, #1a1a2e, #16213e);
}

/* Selective font application with retro effects */
.theme-retro .main-content,
.theme-retro .event-content,
.theme-retro .dashboard-content {
  font-family: var(--font-family);
  text-shadow: 0 0 10px var(--color-accent);
}
```

## CSS Specificity and Inheritance

### Inheritance Chain
1. **HTML/Body**: Default Inter font from Tailwind
2. **Theme Root** (`.theme-cosmic`): Defines CSS variables, applies universal background
3. **Protected Elements**: Inherit Inter font from body, never overridden
4. **Content Areas**: Apply theme font via CSS variables
5. **Content Descendants**: Inherit theme font from content area parent

### Specificity Management
```css
/* Low specificity - CSS variables */
.theme-cosmic { --font-family: 'Orbitron'; }

/* Medium specificity - Content selectors */
.theme-cosmic .main-content { font-family: var(--font-family); }

/* High specificity - Override when needed */
.theme-cosmic .main-content .override { font-family: 'Inter' !important; }

/* Utility classes maintain highest specificity */
.font-inter { font-family: 'Inter' !important; }
```

## Benefits of This Architecture

### 1. Clean Separation
- Universal backgrounds provide visual cohesion
- Selective fonts maintain UI consistency
- Protected elements never break

### 2. Maintainable CSS
- Clear, semantic class names
- No DOM pollution with wrapper divs
- Easy to add new themes

### 3. Performance
- No additional DOM elements
- Efficient CSS selectors
- Minimal specificity conflicts

### 4. Future-Proof
- Easy to add new content areas
- Simple theme addition process
- Clear extension patterns

## Implementation Checklist

- [ ] Update `assets/css/app.css` with base architecture
- [ ] Refactor all theme files in `assets/css/themes/`
- [ ] Update `root.html.heex` layout structure
- [ ] Add semantic classes to LiveView templates
- [ ] Remove `.theme-content` wrapper references
- [ ] Test all themes with new architecture
- [ ] Verify protected elements remain unaffected 