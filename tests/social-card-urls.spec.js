import { test, expect } from '@playwright/test';

test.describe('Social Card URL Generation', () => {
  test.beforeEach(async ({ page }) => {
    // Listen for console logs to debug any issues
    page.on('console', msg => {
      if (msg.type() === 'log' || msg.type() === 'error') {
        console.log(`[${msg.type()}] ${msg.text()}`);
      }
    });
  });

  test('Event page generates correct external social card URL', async ({ page }) => {
    // Navigate to a test event page
    // Note: This test requires a real event to exist.
    // You may need to adjust the slug based on your test data
    const eventSlug = '4xgm6g6x9e'; // Use actual test event slug

    await page.goto(`http://localhost:4000/${eventSlug}`);
    await page.waitForLoadState('networkidle');

    // Get the og:image meta tag
    const ogImage = await page.locator('meta[property="og:image"]').getAttribute('content');

    console.log(`Event og:image URL: ${ogImage}`);

    // Check if the URL is valid
    expect(ogImage).toBeTruthy();

    // Verify URL pattern matches expected format: /:event-slug/social-card-:hash.png
    expect(ogImage).toMatch(new RegExp(`/${eventSlug}/social-card-[a-f0-9]{8}\\.png$`));

    // Most importantly: check that it does NOT use localhost when BASE_URL is set
    if (process.env.BASE_URL) {
      expect(ogImage).not.toContain('localhost');
      expect(ogImage).toContain(process.env.BASE_URL);
      console.log('✅ Event page uses external BASE_URL correctly');
    }

    // Verify the social card URL is actually accessible
    const response = await page.request.get(ogImage);
    expect(response.status()).toBe(200);
    expect(response.headers()['content-type']).toBe('image/png');
    console.log('✅ Event social card URL is accessible and returns PNG');
  });

  test('Poll page generates correct external social card URL', async ({ page }) => {
    // Navigate to a test poll page
    // Note: This test requires a real event with a poll to exist
    const eventSlug = '4xgm6g6x9e'; // Use actual test event slug
    const pollNumber = 1; // Use actual poll number

    await page.goto(`http://localhost:4000/${eventSlug}/polls/${pollNumber}`);
    await page.waitForLoadState('networkidle');

    // Get the og:image meta tag
    const ogImage = await page.locator('meta[property="og:image"]').getAttribute('content');

    console.log(`Poll og:image URL: ${ogImage}`);

    // Check if the URL is valid
    expect(ogImage).toBeTruthy();

    // Verify URL pattern matches expected format: /:event-slug/polls/:poll-number/social-card-:hash.png
    expect(ogImage).toMatch(new RegExp(`/${eventSlug}/polls/${pollNumber}/social-card-[a-f0-9]{8}\\.png$`));

    // Most importantly: check that it does NOT use localhost when BASE_URL is set
    if (process.env.BASE_URL) {
      expect(ogImage).not.toContain('localhost');
      expect(ogImage).toContain(process.env.BASE_URL);
      console.log('✅ Poll page uses external BASE_URL correctly');
    }

    // Verify the social card URL is actually accessible
    const response = await page.request.get(ogImage);
    expect(response.status()).toBe(200);
    expect(response.headers()['content-type']).toBe('image/png');
    console.log('✅ Poll social card URL is accessible and returns PNG');
  });

  test('Event and poll pages use consistent URL generation method', async ({ page }) => {
    const eventSlug = '4xgm6g6x9e';
    const pollNumber = 1;

    // Get event page og:image
    await page.goto(`http://localhost:4000/${eventSlug}`);
    await page.waitForLoadState('networkidle');
    const eventOgImage = await page.locator('meta[property="og:image"]').getAttribute('content');

    // Get poll page og:image
    await page.goto(`http://localhost:4000/${eventSlug}/polls/${pollNumber}`);
    await page.waitForLoadState('networkidle');
    const pollOgImage = await page.locator('meta[property="og:image"]').getAttribute('content');

    console.log(`Event og:image: ${eventOgImage}`);
    console.log(`Poll og:image: ${pollOgImage}`);

    // Extract the base URL from both
    const eventBaseUrl = new URL(eventOgImage).origin;
    const pollBaseUrl = new URL(pollOgImage).origin;

    // Both should use the same base URL (either both localhost or both external domain)
    expect(eventBaseUrl).toBe(pollBaseUrl);
    console.log(`✅ Both pages use consistent base URL: ${eventBaseUrl}`);

    // If BASE_URL env var is set, both should use it
    if (process.env.BASE_URL) {
      const expectedBaseUrl = new URL(process.env.BASE_URL).origin;
      expect(eventBaseUrl).toBe(expectedBaseUrl);
      expect(pollBaseUrl).toBe(expectedBaseUrl);
      console.log('✅ Both pages respect BASE_URL environment variable');
    }
  });

  test('Social card URLs use hash-based cache busting', async ({ page }) => {
    const eventSlug = '4xgm6g6x9e';

    await page.goto(`http://localhost:4000/${eventSlug}`);
    await page.waitForLoadState('networkidle');

    const ogImage = await page.locator('meta[property="og:image"]').getAttribute('content');

    // Verify hash format (8 hexadecimal characters)
    const hashMatch = ogImage.match(/social-card-([a-f0-9]{8})\.png/);
    expect(hashMatch).toBeTruthy();

    const hash = hashMatch[1];
    console.log(`✅ Social card URL contains valid 8-character hash: ${hash}`);

    // Verify the URL includes the hash
    expect(ogImage).toContain(`social-card-${hash}.png`);
  });

  test('Social card URLs have proper cache headers', async ({ page }) => {
    const eventSlug = '4xgm6g6x9e';

    await page.goto(`http://localhost:4000/${eventSlug}`);
    await page.waitForLoadState('networkidle');

    const ogImage = await page.locator('meta[property="og:image"]').getAttribute('content');

    // Fetch the social card and check cache headers
    const response = await page.request.get(ogImage);

    expect(response.status()).toBe(200);

    const cacheControl = response.headers()['cache-control'];
    console.log(`Cache-Control header: ${cacheControl}`);

    // Should have long cache time for immutable content
    expect(cacheControl).toContain('public');
    expect(cacheControl).toContain('max-age=31536000'); // 1 year
    expect(cacheControl).toContain('immutable');

    console.log('✅ Social card has proper cache headers for immutable content');
  });

  test('Social card URLs are valid Open Graph format', async ({ page }) => {
    const eventSlug = '4xgm6g6x9e';

    await page.goto(`http://localhost:4000/${eventSlug}`);
    await page.waitForLoadState('networkidle');

    // Check all required Open Graph meta tags
    const ogImage = await page.locator('meta[property="og:image"]').getAttribute('content');
    const ogTitle = await page.locator('meta[property="og:title"]').getAttribute('content');
    const ogDescription = await page.locator('meta[property="og:description"]').getAttribute('content');
    const ogUrl = await page.locator('meta[property="og:url"]').getAttribute('content');

    // All should be present
    expect(ogImage).toBeTruthy();
    expect(ogTitle).toBeTruthy();
    expect(ogDescription).toBeTruthy();
    expect(ogUrl).toBeTruthy();

    console.log('Open Graph tags present:');
    console.log(`  og:image: ${ogImage}`);
    console.log(`  og:title: ${ogTitle}`);
    console.log(`  og:description: ${ogDescription}`);
    console.log(`  og:url: ${ogUrl}`);

    // og:image should be absolute URL
    expect(ogImage).toMatch(/^https?:\/\//);
    console.log('✅ All Open Graph tags are properly formatted');
  });
});
