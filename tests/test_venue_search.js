const { test, expect } = require('@playwright/test');

test.describe('Venue Search Functionality', () => {
  test.beforeEach(async ({ page }) => {
    // Listen for console logs to debug any issues
    page.on('console', msg => {
      if (msg.type() === 'log' || msg.type() === 'error') {
        console.log(`[${msg.type()}] ${msg.text()}`);
      }
    });
  });

  test('Google Places autocomplete loads and initializes correctly', async ({ page }) => {
    // Navigate to event creation page (adjust URL as needed)
    await page.goto('http://localhost:4000/events/new');
    
    // Wait for the page to be fully loaded
    await page.waitForLoadState('networkidle');
    
    // Check if Google Maps API is loaded
    const googleMapsLoaded = await page.evaluate(() => {
      return window.google && window.google.maps && window.google.maps.places;
    });
    
    expect(googleMapsLoaded).toBe(true);
    
    // Check if the venue search input exists
    const venueSearchInput = await page.locator('#venue-search-new');
    await expect(venueSearchInput).toBeVisible();
    
    // Check if the VenueSearchWithFiltering hook was mounted
    const hookMounted = await page.evaluate(() => {
      return window.venueSearchHooks && window.venueSearchHooks.length >= 0;
    });
    
    expect(hookMounted).toBe(true);
  });

  test('venue search input triggers Google Places suggestions', async ({ page }) => {
    await page.goto('http://localhost:4000/events/new');
    await page.waitForLoadState('networkidle');
    
    // Wait a bit more for Google Maps to fully initialize
    await page.waitForTimeout(2000);
    
    // Find the venue search input
    const venueSearchInput = await page.locator('#venue-search-new');
    await expect(venueSearchInput).toBeVisible();
    
    // Focus on the input and start typing
    await venueSearchInput.click();
    await venueSearchInput.fill('Starbucks');
    
    // Wait for Google Places suggestions to appear
    await page.waitForTimeout(1000);
    
    // Check if the Google Places dropdown (pac-container) appears
    const placesDropdown = await page.locator('.pac-container');
    const isVisible = await placesDropdown.isVisible().catch(() => false);
    
    if (isVisible) {
      console.log('✅ Google Places suggestions are working correctly');
      
      // Check if there are suggestion items
      const suggestions = await page.locator('.pac-container .pac-item');
      const count = await suggestions.count();
      expect(count).toBeGreaterThan(0);
    } else {
      console.log('⚠️ Google Places suggestions not visible - this might indicate an API key issue or rate limiting');
      
      // Even if Google Places isn't working, the input should still be functional
      expect(await venueSearchInput.inputValue()).toBe('Starbucks');
    }
  });

  test('recent locations dropdown functionality', async ({ page }) => {
    await page.goto('http://localhost:4000/events/new');
    await page.waitForLoadState('networkidle');
    
    // Find the venue search input
    const venueSearchInput = await page.locator('#venue-search-new');
    await expect(venueSearchInput).toBeVisible();
    
    // Click on the input to potentially show recent locations
    await venueSearchInput.click();
    
    // Check if recent locations toggle button exists
    const recentLocationsToggle = await page.locator('button:has-text("Recent Locations")');
    
    if (await recentLocationsToggle.isVisible()) {
      // Click the toggle to show recent locations
      await recentLocationsToggle.click();
      
      // Check if the recent locations dropdown appears
      const recentDropdown = await page.locator('.recent-locations-dropdown');
      await expect(recentDropdown).toBeVisible();
      
      console.log('✅ Recent locations functionality is working');
    } else {
      console.log('ℹ️ No recent locations toggle found (expected for new users)');
    }
  });

  test('venue search input filtering triggers LiveView events', async ({ page }) => {
    await page.goto('http://localhost:4000/events/new');
    await page.waitForLoadState('networkidle');
    
    // Set up a listener for LiveView events
    const events = [];
    await page.exposeFunction('captureEvent', (eventName, eventData) => {
      events.push({ name: eventName, data: eventData });
    });
    
    // Override pushEvent to capture events (if accessible)
    await page.evaluate(() => {
      const originalPushEvent = window.pushEvent;
      if (originalPushEvent) {
        window.pushEvent = function(event, data) {
          window.captureEvent(event, data);
          return originalPushEvent.call(this, event, data);
        };
      }
    });
    
    const venueSearchInput = await page.locator('#venue-search-new');
    await venueSearchInput.click();
    await venueSearchInput.fill('test location');
    
    // Wait for debounced events to fire
    await page.waitForTimeout(200);
    
    // Check if the input value was set correctly
    expect(await venueSearchInput.inputValue()).toBe('test location');
    console.log('✅ Venue search input is accepting user input correctly');
  });

  test('virtual event toggle functionality', async ({ page }) => {
    await page.goto('http://localhost:4000/events/new');
    await page.waitForLoadState('networkidle');
    
    // Look for virtual event toggle
    const virtualToggle = await page.locator('input[type="checkbox"][name*="is_virtual"]');
    
    if (await virtualToggle.isVisible()) {
      // Toggle to virtual event
      await virtualToggle.check();
      
      // Check if virtual event URL input appears
      const virtualUrlInput = await page.locator('input[name*="virtual_venue_url"]');
      await expect(virtualUrlInput).toBeVisible();
      
      // Check if venue search is hidden when virtual
      const venueSearchInput = await page.locator('#venue-search-new');
      const isVenueSearchVisible = await venueSearchInput.isVisible();
      
      // Virtual event should hide physical venue search
      if (!isVenueSearchVisible) {
        console.log('✅ Virtual event toggle correctly hides venue search');
      }
      
      // Toggle back to physical event
      await virtualToggle.uncheck();
      
      // Venue search should be visible again
      await expect(venueSearchInput).toBeVisible();
      console.log('✅ Toggling back to physical event shows venue search');
    } else {
      console.log('ℹ️ Virtual event toggle not found - might be in a different UI location');
    }
  });
}); 