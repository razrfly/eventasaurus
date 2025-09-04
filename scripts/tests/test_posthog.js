// Test script to verify PostHog analytics tracking
console.log('Testing PostHog Analytics Integration...');

// Check if PostHog is loaded
if (typeof window !== 'undefined' && window.posthog) {
    console.log('✅ PostHog is loaded');
    
    // Check PostHog configuration
    const config = window.posthog.config;
    console.log('PostHog Config:', {
        api_host: config?.api_host,
        token: config?.token ? '***' + config.token.substr(-4) : 'NOT SET',
        capture_pageview: config?.capture_pageview,
        opt_out_capturing: config?.opt_out_capturing_by_default
    });
    
    // Test event capture
    console.log('\nTesting event capture...');
    window.posthog.capture('test_event', {
        test_property: 'test_value',
        timestamp: new Date().toISOString()
    });
    
    // Check if user is identified
    const distinctId = window.posthog.get_distinct_id();
    console.log('Distinct ID:', distinctId);
    
    // Check feature flags
    console.log('\nFeature Flags Enabled:', window.posthog.isFeatureEnabled ? 'Yes' : 'No');
    
} else {
    console.error('❌ PostHog is NOT loaded');
    
    // Check for window.POSTHOG_API_KEY
    if (typeof window !== 'undefined') {
        console.log('window.POSTHOG_API_KEY:', window.POSTHOG_API_KEY || 'NOT SET');
        console.log('window.POSTHOG_HOST:', window.POSTHOG_HOST || 'NOT SET');
    }
}