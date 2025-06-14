# Anti-Social Authentication Integration PRD

## Executive Summary

This document outlines the implementation of Facebook and Twitter OAuth authentication for Eventasaurus using Supabase, with a playful "anti-social" UI theme that contrasts these mainstream platforms with our genuinely social event platform.

## Project Context

**Current State:**
- Supabase is fully configured with environment variables
- Facebook and Twitter OAuth providers are already set up in Supabase Dashboard
- Email/password authentication is implemented
- All redirect URLs and OAuth apps are properly configured

**Objective:**
Add Facebook and Twitter sign-up/sign-in options across all authentication touchpoints while implementing a humorous "anti-social" branding approach and maintaining design consistency.

## Technical Implementation Strategy

### 1. Core OAuth Implementation

Based on Supabase documentation audit, the implementation requires:

#### Client-Side OAuth Initiation
```javascript
// Facebook Authentication
const signInWithFacebook = async () => {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'facebook',
    options: {
      redirectTo: `${window.location.origin}/auth/callback`
    }
  })
}

// Twitter Authentication  
const signInWithTwitter = async () => {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'twitter',
    options: {
      redirectTo: `${window.location.origin}/auth/callback`
    }
  })
}
```

#### Callback Handler Implementation
Create `/auth/callback` route to handle OAuth returns:

**Next.js App Router:** `app/auth/callback/route.ts`
```typescript
import { NextResponse } from 'next/server'
import { createClient } from '@/utils/supabase/server'

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const next = searchParams.get('next') ?? '/'

  if (code) {
    const supabase = await createClient()
    const { error } = await supabase.auth.exchangeCodeForSession(code)
    if (!error) {
      return NextResponse.redirect(`${origin}${next}`)
    }
  }

  return NextResponse.redirect(`${origin}/auth/auth-code-error`)
}
```

#### Error Handling Implementation
```javascript
// Error state management
const [authError, setAuthError] = useState(null)
const [loading, setLoading] = useState(false)

const handleSocialAuth = async (provider) => {
  try {
    setLoading(true)
    setAuthError(null)
    
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider,
      options: {
        redirectTo: `${window.location.origin}/auth/callback`
      }
    })
    
    if (error) throw error
  } catch (error) {
    setAuthError(error.message)
  } finally {
    setLoading(false)
  }
}
```

### 2. Reusable Component Architecture

#### SocialAuthButtons Component
```typescript
interface SocialAuthButtonsProps {
  redirectTo?: string
  className?: string
  showAntiSocialCopy?: boolean
}

const SocialAuthButtons = ({ 
  redirectTo = '/dashboard',
  className = '',
  showAntiSocialCopy = true 
}: SocialAuthButtonsProps) => {
  const supabase = createClient()
  
  return (
    <div className={`social-auth-container ${className}`}>
      {showAntiSocialCopy && (
        <div className="anti-social-intro">
          <p className="text-gray-600 text-sm mb-2">
            Or if you want to be anti-social...
          </p>
          <div className="flex items-center mb-4">
            <ArrowDownIcon className="w-4 h-4 text-gray-400 mr-2" />
            <span className="text-xs text-gray-500">
              (We're the social ones, they're not)
            </span>
          </div>
        </div>
      )}
      
      <div className="social-buttons-grid">
        <FacebookAuthButton onSuccess={() => router.push(redirectTo)} />
        <TwitterAuthButton onSuccess={() => router.push(redirectTo)} />
      </div>
    </div>
  )
}
```

#### Individual Provider Components
```typescript
// FacebookAuthButton.tsx
const FacebookAuthButton = ({ onSuccess, disabled = false }) => {
  const [loading, setLoading] = useState(false)
  const supabase = createClient()
  
  const handleFacebookAuth = async () => {
    setLoading(true)
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'facebook'
      })
      if (!error) onSuccess?.()
    } catch (err) {
      console.error('Facebook auth error:', err)
    } finally {
      setLoading(false)
    }
  }
  
  return (
    <button
      onClick={handleFacebookAuth}
      disabled={disabled || loading}
      className="social-btn social-btn-facebook"
    >
      <FacebookIcon className="w-5 h-5 mr-2" />
      {loading ? 'Connecting...' : 'Continue with Facebook'}
    </button>
  )
}

// TwitterAuthButton.tsx  
const TwitterAuthButton = ({ onSuccess, disabled = false }) => {
  const [loading, setLoading] = useState(false)
  const supabase = createClient()
  
  const handleTwitterAuth = async () => {
    setLoading(true)
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'twitter'
      })
      if (!error) onSuccess?.()
    } catch (err) {
      console.error('Twitter auth error:', err)
    } finally {
      setLoading(false)
    }
  }
  
  return (
    <button
      onClick={handleTwitterAuth}
      disabled={disabled || loading}
      className="social-btn social-btn-twitter"
    >
      <TwitterIcon className="w-5 h-5 mr-2" />
      {loading ? 'Connecting...' : 'Continue with Twitter'}
    </button>
  )
}
```

### 3. Integration Points Implementation

#### Authentication Pages
Update existing auth forms to include social options:

```typescript
// components/AuthForm.tsx
const AuthForm = ({ mode = 'signin', redirectTo = '/dashboard' }) => {
  return (
    <div className="auth-form">
      {/* Existing email/password form */}
      <form className="traditional-auth">
        <EmailField />
        <PasswordField />
        {mode === 'signup' && <NameField />}
        <SubmitButton />
      </form>
      
      {/* Social auth section */}
      <div className="auth-divider">
        <span>Or</span>
      </div>
      
      <SocialAuthButtons 
        redirectTo={redirectTo}
        showAntiSocialCopy={true}
      />
    </div>
  )
}
```

#### Event Registration Integration
```typescript
// components/EventRegistration.tsx
const EventRegistrationModal = ({ eventId, isOpen, onClose }) => {
  const [user, setUser] = useState(null)
  
  useEffect(() => {
    const checkUser = async () => {
      const { data } = await supabase.auth.getUser()
      setUser(data.user)
    }
    checkUser()
  }, [])
  
  if (!user) {
    return (
      <Modal isOpen={isOpen} onClose={onClose}>
        <div className="registration-auth">
          <h2>Join this event</h2>
          <p>Sign up quickly to register for this event</p>
          
          <SocialAuthButtons 
            redirectTo={`/events/${eventId}/register`}
            showAntiSocialCopy={true}
          />
          
          <div className="traditional-option">
            <p>Or use email:</p>
            <AuthForm mode="signup" redirectTo={`/events/${eventId}/register`} />
          </div>
        </div>
      </Modal>
    )
  }
  
  return <EventRegistrationForm eventId={eventId} user={user} />
}
```

#### Quick Voting Authentication
```typescript
// components/VoteButton.tsx
const VoteButton = ({ eventId, voteType }) => {
  const [user, setUser] = useState(null)
  const [showAuthModal, setShowAuthModal] = useState(false)
  
  const handleVote = async () => {
    if (!user) {
      setShowAuthModal(true)
      return
    }
    
    // Process vote
    await submitVote(eventId, voteType, user.id)
  }
  
  return (
    <>
      <button onClick={handleVote} className="vote-btn">
        Vote {voteType}
      </button>
      
      <Modal isOpen={showAuthModal} onClose={() => setShowAuthModal(false)}>
        <div className="vote-auth">
          <h3>Quick sign-in to vote</h3>
          <SocialAuthButtons 
            redirectTo={`/events/${eventId}?voted=${voteType}`}
            showAntiSocialCopy={false} // Shorter for quick actions
          />
          <AuthForm mode="signin" redirectTo={`/events/${eventId}?voted=${voteType}`} />
        </div>
      </Modal>
    </>
  )
}
```

### 4. UI/UX Design Specifications

#### Anti-Social Theme Elements
```css
/* CSS for anti-social theme */
.anti-social-intro {
  text-align: center;
  margin-bottom: 1rem;
}

.anti-social-intro p {
  font-style: italic;
  color: #6B7280;
}

.social-buttons-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.75rem;
  margin-top: 1rem;
}

.social-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0.75rem 1rem;
  border-radius: 0.5rem;
  font-weight: 500;
  transition: all 0.2s;
  border: 1px solid transparent;
}

.social-btn-facebook {
  background-color: #1877F2;
  color: white;
}

.social-btn-facebook:hover {
  background-color: #166FE5;
}

.social-btn-twitter {
  background-color: #000000;
  color: white;
}

.social-btn-twitter:hover {
  background-color: #1a1a1a;
}

.auth-divider {
  position: relative;
  text-align: center;
  margin: 1.5rem 0;
}

.auth-divider::before {
  content: '';
  position: absolute;
  top: 50%;
  left: 0;
  right: 0;
  height: 1px;
  background-color: #E5E7EB;
}

.auth-divider span {
  background-color: white;
  padding: 0 1rem;
  color: #6B7280;
  font-size: 0.875rem;
}
```

#### Responsive Design Considerations
```css
/* Mobile-first responsive design */
@media (max-width: 640px) {
  .social-buttons-grid {
    grid-template-columns: 1fr;
    gap: 0.5rem;
  }
  
  .social-btn {
    padding: 0.875rem 1rem;
    font-size: 0.875rem;
  }
}

@media (min-width: 768px) {
  .anti-social-intro {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 1rem;
  }
  
  .anti-social-intro p {
    margin-bottom: 0;
  }
}
```

### 5. User Experience Flows

#### Primary Registration Flow
1. User visits registration page
2. Sees traditional email/password form prominently displayed
3. Below form: "Or if you want to be anti-social..." with playful arrow
4. Social buttons displayed with provider icons
5. User clicks social provider → redirects to OAuth
6. After OAuth success → returns to app with session
7. User redirected to appropriate post-auth destination

#### Error Handling UX
```typescript
const AuthErrorDisplay = ({ error, onRetry }) => {
  const getErrorMessage = (error) => {
    if (error?.message?.includes('popup_closed')) {
      return "Looks like you closed the window. Want to try again?"
    }
    if (error?.message?.includes('network')) {
      return "Network issue detected. Check your connection and try again."
    }
    return "Something went wrong with authentication. Please try again."
  }
  
  return (
    <div className="auth-error">
      <p>{getErrorMessage(error)}</p>
      <button onClick={onRetry} className="retry-btn">
        Try Again
      </button>
    </div>
  )
}
```

### 6. Session Management

#### User Session Handling
```typescript
// hooks/useAuth.ts
export const useAuth = () => {
  const [user, setUser] = useState(null)
  const [loading, setLoading] = useState(true)
  const supabase = createClient()
  
  useEffect(() => {
    // Get initial session
    const getSession = async () => {
      const { data: { session } } = await supabase.auth.getSession()
      setUser(session?.user ?? null)
      setLoading(false)
    }
    
    getSession()
    
    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        setUser(session?.user ?? null)
        setLoading(false)
      }
    )
    
    return () => subscription.unsubscribe()
  }, [])
  
  return { user, loading }
}
```

#### Profile Data Management
```typescript
// Handle social provider profile data
const handleSocialProfileData = async (user) => {
  const { data: existingProfile } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', user.id)
    .single()
    
  if (!existingProfile) {
    // Create profile from social data
    const profileData = {
      id: user.id,
      email: user.email,
      full_name: user.user_metadata.full_name || user.user_metadata.name,
      avatar_url: user.user_metadata.avatar_url || user.user_metadata.picture,
      provider: user.app_metadata.provider,
      created_at: new Date().toISOString()
    }
    
    await supabase.from('profiles').insert(profileData)
  }
}
```

### 7. Testing Requirements

#### Unit Testing
```typescript
// __tests__/SocialAuthButtons.test.tsx
import { render, fireEvent, waitFor } from '@testing-library/react'
import { SocialAuthButtons } from '@/components/SocialAuthButtons'

jest.mock('@/utils/supabase/client')

describe('SocialAuthButtons', () => {
  it('renders Facebook and Twitter buttons', () => {
    const { getByText } = render(<SocialAuthButtons />)
    
    expect(getByText('Continue with Facebook')).toBeInTheDocument()
    expect(getByText('Continue with Twitter')).toBeInTheDocument()
  })
  
  it('shows anti-social copy by default', () => {
    const { getByText } = render(<SocialAuthButtons />)
    
    expect(getByText(/anti-social/i)).toBeInTheDocument()
  })
  
  it('handles Facebook OAuth correctly', async () => {
    const mockSignInWithOAuth = jest.fn().mockResolvedValue({ error: null })
    const { getByText } = render(<SocialAuthButtons />)
    
    fireEvent.click(getByText('Continue with Facebook'))
    
    await waitFor(() => {
      expect(mockSignInWithOAuth).toHaveBeenCalledWith({
        provider: 'facebook'
      })
    })
  })
})
```

#### Integration Testing
```typescript
// __tests__/auth-flow.integration.test.tsx
describe('Social Auth Integration', () => {
  it('completes full Facebook auth flow', async () => {
    // Mock OAuth success
    const mockOAuthResponse = {
      data: { url: 'https://facebook.com/oauth...' },
      error: null
    }
    
    // Test full flow from button click to callback handling
    // Verify session creation and redirect
  })
  
  it('handles OAuth cancellation gracefully', async () => {
    // Test user closing OAuth popup
    // Verify error handling and retry options
  })
})
```

### 8. Analytics & Monitoring

#### Event Tracking
```typescript
// Track social auth events
const trackSocialAuth = (provider, event, metadata = {}) => {
  analytics.track(`Social Auth ${event}`, {
    provider,
    timestamp: new Date().toISOString(),
    user_agent: navigator.userAgent,
    ...metadata
  })
}

// Usage in components
const handleFacebookAuth = async () => {
  trackSocialAuth('facebook', 'Initiated')
  
  try {
    const result = await supabase.auth.signInWithOAuth({
      provider: 'facebook'
    })
    
    if (result.error) {
      trackSocialAuth('facebook', 'Failed', { error: result.error.message })
    } else {
      trackSocialAuth('facebook', 'Success')
    }
  } catch (error) {
    trackSocialAuth('facebook', 'Error', { error: error.message })
  }
}
```

### 9. Performance Optimization

#### Code Splitting
```typescript
// Lazy load social auth components
const SocialAuthButtons = lazy(() => import('@/components/SocialAuthButtons'))

// Usage with fallback
<Suspense fallback={<AuthButtonsSkeleton />}>
  <SocialAuthButtons />
</Suspense>
```

#### Loading States
```typescript
const AuthButton = ({ provider, onClick, loading }) => (
  <button
    onClick={onClick}
    disabled={loading}
    className={`social-btn social-btn-${provider}`}
  >
    {loading ? (
      <>
        <Spinner className="w-4 h-4 mr-2" />
        Connecting...
      </>
    ) : (
      <>
        <ProviderIcon provider={provider} className="w-5 h-5 mr-2" />
        Continue with {provider}
      </>
    )}
  </button>
)
```

### 10. Security Implementation

#### CSRF Protection
```typescript
// Generate and validate state parameter
const generateAuthState = () => {
  const state = crypto.randomUUID()
  sessionStorage.setItem('oauth_state', state)
  return state
}

const validateAuthState = (returnedState) => {
  const storedState = sessionStorage.getItem('oauth_state')
  sessionStorage.removeItem('oauth_state')
  return storedState === returnedState
}
```

#### Content Security Policy
```typescript
// Add to next.config.js
const securityHeaders = [
  {
    key: 'Content-Security-Policy',
    value: `
      default-src 'self';
      connect-src 'self' https://*.supabase.co https://graph.facebook.com https://api.twitter.com;
      frame-src https://www.facebook.com https://twitter.com;
    `.replace(/\s{2,}/g, ' ').trim()
  }
]
```

## Implementation Timeline

### Phase 1: Core Implementation (Week 1)
- [ ] Implement SocialAuthButtons component
- [ ] Create individual provider button components
- [ ] Set up OAuth callback handler
- [ ] Implement basic error handling

### Phase 2: Integration (Week 2)
- [ ] Integrate into registration pages
- [ ] Add to event registration flows
- [ ] Implement quick vote authentication
- [ ] Add loading states and UX polish

### Phase 3: Testing & Refinement (Week 3)
- [ ] Comprehensive testing suite
- [ ] Performance optimization
- [ ] Analytics implementation
- [ ] UI/UX refinements based on feedback

### Phase 4: Launch & Monitor (Week 4)
- [ ] Feature flag rollout
- [ ] A/B testing setup
- [ ] Monitor adoption rates
- [ ] Performance monitoring

## Success Metrics

### Primary KPIs
- **Social Auth Adoption Rate:** Target 30% of new registrations
- **Conversion Rate Improvement:** Target 15% increase
- **Time to Registration:** Target 40% reduction for social auth users
- **User Retention:** Compare 30-day retention between auth methods

### Secondary Metrics
- **Provider Performance:** Facebook vs Twitter conversion rates
- **Error Rate:** Target <2% OAuth failure rate
- **User Feedback:** NPS scores on auth experience
- **Support Tickets:** Reduction in password-related issues

## Risk Mitigation

### Technical Risks
- **OAuth Provider Outages:** Implement graceful fallbacks to email auth
- **Rate Limiting:** Monitor API usage and implement queueing if needed
- **Session Management:** Robust error handling for session edge cases

### UX Risks
- **User Confusion:** Clear labeling and help text for social options
- **Privacy Concerns:** Transparent data usage disclosure
- **Mobile Experience:** Thorough testing across devices and browsers

## Conclusion

This implementation provides a comprehensive social authentication solution that:
- Leverages existing Supabase OAuth configuration
- Maintains design consistency across the application
- Implements the playful "anti-social" branding
- Provides robust error handling and security
- Enables detailed analytics and monitoring
- Follows best practices for performance and accessibility

The modular component architecture ensures easy maintenance and future expansion to additional OAuth providers while maintaining the unique brand personality that sets Eventasaurus apart from other platforms. 