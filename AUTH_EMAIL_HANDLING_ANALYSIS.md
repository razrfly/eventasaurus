# Authentication Email Handling Analysis

**Context**: Evaluating email handling for authentication migration from Supabase to either Clerk or roll-your-own solution. Current infrastructure uses **Resend** for email delivery (not Supabase).

## Current Email Infrastructure

**Existing Setup**:
- **Email Library**: Swoosh (`lib/eventasaurus/mailer.ex`)
- **Email Provider**: Resend (for transactional emails)
- **Current Usage**: Guest invitation emails (`lib/eventasaurus/emails.ex`)
- **Job Processing**: Oban for background email jobs with rate limiting

**Key Files**:
- `/lib/eventasaurus/emails.ex` - Email templates with HTML/text formatting
- `/lib/eventasaurus/mailer.ex` - Swoosh mailer configuration
- `/lib/eventasaurus/jobs/email_invitation_job.ex` - Background email processing with rate limiting (600ms delay for Resend's 2/sec limit)

---

## Auth-Related Emails Needed

Based on current Supabase implementation (`/lib/eventasaurus_web/controllers/auth/auth_controller.ex`), these auth emails are required:

### 1. **Password Reset Email**
- **Trigger**: User requests password reset
- **Content**: Link or code to reset password
- **Current Flow**: `Auth.request_password_reset(email)` (handled by Supabase)

### 2. **Email Verification** (Sign-up)
- **Trigger**: New user registration
- **Content**: Verification link or code
- **Purpose**: Confirm email ownership before account activation

### 3. **Email Verification** (Adding New Email)
- **Trigger**: Existing user adds new email address
- **Content**: Verification link or code
- **Purpose**: Confirm ownership of new email before associating with account

### 4. **Magic Link** (Optional/Future)
- **Trigger**: Passwordless authentication
- **Content**: One-time sign-in link
- **Purpose**: Allow users to sign in without password

### 5. **Password Change Confirmation** (Security)
- **Trigger**: User successfully changes password
- **Content**: Notification email
- **Purpose**: Alert user of password change (security measure)

### 6. **OAuth Account Linked** (Optional)
- **Trigger**: User links Google/Facebook account
- **Content**: Notification email
- **Purpose**: Confirm social account connection

---

## Option 1: Clerk Email Handling

### How Clerk Manages Emails

**Default Behavior**: Clerk sends emails automatically using their infrastructure

**Supported Email Types**:
1. ✅ Password reset (code or link)
2. ✅ Email verification (code or link)
3. ✅ Magic link authentication
4. ✅ Multi-factor authentication codes
5. ✅ Account notifications

### Email Delivery Options with Clerk

#### **Option A: Clerk Sends Emails (Default)**

**How It Works**:
- Clerk handles all email sending through their infrastructure
- SPF/DKIM automatically configured
- Email templates customizable via Clerk Dashboard
- No additional code required

**Pros**:
- ✅ Zero implementation work
- ✅ Email deliverability handled by Clerk
- ✅ SPF/DKIM records managed automatically
- ✅ Templates can be customized via dashboard

**Cons**:
- ❌ Less control over email delivery
- ❌ Emails come from Clerk's domain by default
- ❌ Limited customization compared to own infrastructure

**Implementation**: None required - works out of the box

---

#### **Option B: Use Resend with Clerk (Custom Email Delivery)**

**How It Works**:
1. Disable "Delivered by Clerk" in Clerk Dashboard
2. Clerk triggers webhooks when emails need to be sent
3. Your backend listens to webhooks and sends emails via Resend
4. You have full control over email content and delivery

**Clerk Webhook Events for Emails**:
```elixir
# Webhook events that trigger emails
"email.created"              # New email verification needed
"user.created"               # New user registration (welcome email)
"session.created"            # Magic link sign-in
"email.verification.required" # Email needs verification
# Plus custom events for password resets, etc.
```

**Implementation Steps**:

1. **Configure Clerk Webhooks** (Clerk Dashboard):
   ```
   Dashboard → Webhooks → Add Endpoint
   URL: https://yourdomain.com/api/webhooks/clerk
   Events: user.created, email.created, session.created
   ```

2. **Create Webhook Handler** (`lib/eventasaurus_web/controllers/webhooks/clerk_webhook_controller.ex`):
   ```elixir
   defmodule EventasaurusWeb.Webhooks.ClerkWebhookController do
     use EventasaurusWeb, :controller
     alias Eventasaurus.Auth.ClerkEmailHandler

     def handle(conn, params) do
       # Verify webhook signature
       signature = get_req_header(conn, "svix-signature") |> List.first()

       with {:ok, _} <- verify_webhook_signature(signature, params),
            {:ok, _} <- handle_event(params["type"], params["data"]) do
         json(conn, %{success: true})
       else
         {:error, reason} ->
           conn
           |> put_status(400)
           |> json(%{error: reason})
       end
     end

     defp handle_event("email.verification.required", data) do
       ClerkEmailHandler.send_verification_email(data)
     end

     defp handle_event("user.created", data) do
       ClerkEmailHandler.send_welcome_email(data)
     end

     defp handle_event(_type, _data), do: {:ok, :ignored}
   end
   ```

3. **Create Email Handler** (`lib/eventasaurus/auth/clerk_email_handler.ex`):
   ```elixir
   defmodule Eventasaurus.Auth.ClerkEmailHandler do
     alias Eventasaurus.{Emails, Mailer}

     def send_verification_email(%{
       "email_address" => email,
       "verification_token" => token,
       "user_id" => user_id
     }) do
       verification_url = build_verification_url(token)

       Emails.verification_email(email, verification_url)
       |> Mailer.deliver()
     end

     def send_password_reset_email(%{
       "email_address" => email,
       "reset_token" => token
     }) do
       reset_url = build_reset_url(token)

       Emails.password_reset_email(email, reset_url)
       |> Mailer.deliver()
     end

     defp build_verification_url(token) do
       "#{Application.get_env(:eventasaurus, :base_url)}/verify-email?token=#{token}"
     end

     defp build_reset_url(token) do
       "#{Application.get_env(:eventasaurus, :base_url)}/reset-password?token=#{token}"
     end
   end
   ```

4. **Add Email Templates to Existing System** (`lib/eventasaurus/emails.ex`):
   ```elixir
   # Add to existing Emails module

   def verification_email(to_email, verification_url) do
     new()
     |> from(@from_email)
     |> to(to_email)
     |> subject("Verify your email address")
     |> html_body("""
       <h1>Verify your email</h1>
       <p>Click the link below to verify your email address:</p>
       <a href="#{verification_url}">Verify Email</a>
     """)
     |> text_body("""
       Verify your email

       Click the link below to verify your email address:
       #{verification_url}
     """)
   end

   def password_reset_email(to_email, reset_url) do
     new()
     |> from(@from_email)
     |> to(to_email)
     |> subject("Reset your password")
     |> html_body("""
       <h1>Reset your password</h1>
       <p>Click the link below to reset your password:</p>
       <a href="#{reset_url}">Reset Password</a>
       <p>If you didn't request this, you can safely ignore this email.</p>
     """)
     |> text_body("""
       Reset your password

       Click the link below to reset your password:
       #{reset_url}

       If you didn't request this, you can safely ignore this email.
     """)
   end
   ```

5. **Background Job Processing** (Optional - for rate limiting):
   ```elixir
   defmodule Eventasaurus.Jobs.ClerkEmailJob do
     use Oban.Worker, queue: :emails, max_attempts: 3

     @impl Oban.Worker
     def perform(%Oban.Job{args: %{"type" => type, "data" => data}}) do
       # Add 600ms delay for Resend rate limiting (2/sec)
       Process.sleep(600)

       case type do
         "verification" ->
           ClerkEmailHandler.send_verification_email(data)
         "password_reset" ->
           ClerkEmailHandler.send_password_reset_email(data)
         _ ->
           {:ok, :ignored}
       end
     end
   end
   ```

**Pros**:
- ✅ Full control over email content and delivery
- ✅ Leverage existing Resend infrastructure
- ✅ Consistent email branding with existing invitation emails
- ✅ Can reuse existing rate limiting logic
- ✅ Easy to test and debug email delivery

**Cons**:
- ❌ More implementation work (webhook handling + email templates)
- ❌ Need to maintain email templates yourself
- ❌ Responsible for email deliverability (SPF/DKIM setup)

**Estimated Implementation Time**: 2-3 days (webhook handler + 3-4 email templates)

---

### Recommendation for Clerk

**Use Option B (Resend + Webhooks)** for these reasons:

1. **Consistency**: All emails (invitations + auth) sent from same infrastructure
2. **Control**: Full control over email content and branding
3. **Existing Infrastructure**: Already have Swoosh + Resend + Oban setup
4. **Debugging**: Easier to debug and test email delivery
5. **Cost**: Already paying for Resend, no additional Clerk email costs

**Email Template Customization via Clerk Dashboard**:
- Clerk provides WYSIWYG email editor (Revolvapp)
- Handlebars templating for dynamic values: `{{app.name}}`, `{{user.email}}`
- Can revert to default templates or copy between environments
- Templates automatically optimized for spam filters

---

## Option 2: Roll Your Own Email Handling

### Complete Implementation Required

**Libraries Needed**:
- ✅ Swoosh (already have)
- ✅ Resend adapter (already configured)
- ✅ Oban (already have for job processing)
- ➕ Phoenix.Token (built-in, for secure token generation)

### Email Types to Implement

#### 1. **Password Reset Email**

**Implementation** (`lib/eventasaurus/auth/password_reset.ex`):
```elixir
defmodule Eventasaurus.Auth.PasswordReset do
  alias Eventasaurus.{Emails, Mailer, Repo}
  alias Eventasaurus.Accounts.User

  @reset_token_max_age 3600  # 1 hour

  def request_password_reset(email) do
    case Repo.get_by(User, email: email) do
      nil ->
        # Don't reveal if email exists (security)
        {:ok, :email_sent}

      user ->
        token = generate_password_reset_token(user)
        send_password_reset_email(user.email, token)
    end
  end

  defp generate_password_reset_token(user) do
    Phoenix.Token.sign(
      EventasaurusWeb.Endpoint,
      "password_reset",
      user.id
    )
  end

  def verify_reset_token(token) do
    case Phoenix.Token.verify(
      EventasaurusWeb.Endpoint,
      "password_reset",
      token,
      max_age: @reset_token_max_age
    ) do
      {:ok, user_id} -> {:ok, user_id}
      {:error, :expired} -> {:error, :token_expired}
      {:error, _} -> {:error, :invalid_token}
    end
  end

  defp send_password_reset_email(email, token) do
    reset_url = build_reset_url(token)

    Emails.password_reset_email(email, reset_url)
    |> Mailer.deliver()
  end

  defp build_reset_url(token) do
    base_url = Application.get_env(:eventasaurus, :base_url)
    "#{base_url}/reset-password?token=#{token}"
  end
end
```

**Email Template** (`lib/eventasaurus/emails.ex`):
```elixir
def password_reset_email(to_email, reset_url) do
  new()
  |> from({"Wombie", "auth@wombie.com"})
  |> to(to_email)
  |> subject("Reset your Wombie password")
  |> html_body("""
    <!DOCTYPE html>
    <html>
      <body>
        <h1>Reset Your Password</h1>
        <p>You requested to reset your password for your Wombie account.</p>
        <p>
          <a href="#{reset_url}"
             style="background: #007bff; color: white; padding: 12px 24px;
                    text-decoration: none; border-radius: 4px; display: inline-block;">
            Reset Password
          </a>
        </p>
        <p>This link will expire in 1 hour.</p>
        <p>If you didn't request this, you can safely ignore this email.</p>
      </body>
    </html>
  """)
  |> text_body("""
    Reset Your Password

    You requested to reset your password for your Wombie account.

    Click the link below to reset your password:
    #{reset_url}

    This link will expire in 1 hour.

    If you didn't request this, you can safely ignore this email.
  """)
end
```

**Controller Integration** (`lib/eventasaurus_web/controllers/auth/auth_controller.ex`):
```elixir
def request_password_reset(conn, %{"email" => email}) do
  PasswordReset.request_password_reset(email)

  conn
  |> put_flash(:info, "If an account exists with that email, we've sent password reset instructions.")
  |> redirect(to: ~p"/login")
end

def reset_password(conn, %{"token" => token, "password" => password}) do
  case PasswordReset.verify_reset_token(token) do
    {:ok, user_id} ->
      user = Repo.get!(User, user_id)

      case Auth.update_user_password(user, password) do
        {:ok, _user} ->
          conn
          |> put_flash(:info, "Password reset successfully. Please sign in.")
          |> redirect(to: ~p"/login")

        {:error, changeset} ->
          render(conn, "reset_password.html", token: token, changeset: changeset)
      end

    {:error, :token_expired} ->
      conn
      |> put_flash(:error, "Reset link has expired. Please request a new one.")
      |> redirect(to: ~p"/forgot-password")

    {:error, _} ->
      conn
      |> put_flash(:error, "Invalid reset link.")
      |> redirect(to: ~p"/login")
  end
end
```

---

#### 2. **Email Verification**

**Implementation** (`lib/eventasaurus/auth/email_verification.ex`):
```elixir
defmodule Eventasaurus.Auth.EmailVerification do
  alias Eventasaurus.{Emails, Mailer, Repo}
  alias Eventasaurus.Accounts.User

  @verification_token_max_age 86400  # 24 hours

  def send_verification_email(user) do
    token = generate_verification_token(user)

    Emails.verification_email(user.email, token)
    |> Mailer.deliver()
  end

  defp generate_verification_token(user) do
    Phoenix.Token.sign(
      EventasaurusWeb.Endpoint,
      "email_verification",
      user.id
    )
  end

  def verify_email(token) do
    case Phoenix.Token.verify(
      EventasaurusWeb.Endpoint,
      "email_verification",
      token,
      max_age: @verification_token_max_age
    ) do
      {:ok, user_id} ->
        user = Repo.get!(User, user_id)

        user
        |> User.changeset(%{email_verified: true, email_verified_at: DateTime.utc_now()})
        |> Repo.update()

      {:error, :expired} ->
        {:error, :token_expired}

      {:error, _} ->
        {:error, :invalid_token}
    end
  end

  def resend_verification_email(user) do
    if user.email_verified do
      {:error, :already_verified}
    else
      send_verification_email(user)
      {:ok, :email_sent}
    end
  end
end
```

**Email Template**:
```elixir
def verification_email(to_email, token) do
  verification_url = build_verification_url(token)

  new()
  |> from({"Wombie", "auth@wombie.com"})
  |> to(to_email)
  |> subject("Verify your Wombie email address")
  |> html_body("""
    <!DOCTYPE html>
    <html>
      <body>
        <h1>Welcome to Wombie!</h1>
        <p>Please verify your email address to complete your registration.</p>
        <p>
          <a href="#{verification_url}"
             style="background: #28a745; color: white; padding: 12px 24px;
                    text-decoration: none; border-radius: 4px; display: inline-block;">
            Verify Email
          </a>
        </p>
        <p>This link will expire in 24 hours.</p>
      </body>
    </html>
  """)
  |> text_body("""
    Welcome to Wombie!

    Please verify your email address to complete your registration.

    Click the link below:
    #{verification_url}

    This link will expire in 24 hours.
  """)
end

defp build_verification_url(token) do
  base_url = Application.get_env(:eventasaurus, :base_url)
  "#{base_url}/verify-email?token=#{token}"
end
```

---

#### 3. **Password Change Confirmation**

**Email Template**:
```elixir
def password_changed_email(to_email, user_name) do
  new()
  |> from({"Wombie Security", "security@wombie.com"})
  |> to(to_email)
  |> subject("Your Wombie password was changed")
  |> html_body("""
    <!DOCTYPE html>
    <html>
      <body>
        <h1>Password Changed</h1>
        <p>Hi #{user_name},</p>
        <p>Your password was successfully changed on #{format_datetime(DateTime.utc_now())}.</p>
        <p>If you didn't make this change, please contact us immediately at support@wombie.com</p>
      </body>
    </html>
  """)
  |> text_body("""
    Password Changed

    Hi #{user_name},

    Your password was successfully changed on #{format_datetime(DateTime.utc_now())}.

    If you didn't make this change, please contact us immediately at support@wombie.com
  """)
end
```

**Integration** (add to password update function):
```elixir
def update_user_password(user, new_password) do
  changeset = User.password_changeset(user, %{password: new_password})

  case Repo.update(changeset) do
    {:ok, updated_user} ->
      # Send confirmation email
      Emails.password_changed_email(user.email, user.name)
      |> Mailer.deliver()

      {:ok, updated_user}

    {:error, changeset} ->
      {:error, changeset}
  end
end
```

---

#### 4. **Magic Link** (Optional)

**Implementation**:
```elixir
defmodule Eventasaurus.Auth.MagicLink do
  @magic_link_max_age 900  # 15 minutes

  def send_magic_link(email) do
    case Repo.get_by(User, email: email) do
      nil ->
        {:error, :user_not_found}

      user ->
        token = generate_magic_link_token(user)

        Emails.magic_link_email(user.email, token)
        |> Mailer.deliver()

        {:ok, :email_sent}
    end
  end

  defp generate_magic_link_token(user) do
    Phoenix.Token.sign(
      EventasaurusWeb.Endpoint,
      "magic_link",
      user.id
    )
  end

  def verify_magic_link(token) do
    case Phoenix.Token.verify(
      EventasaurusWeb.Endpoint,
      "magic_link",
      token,
      max_age: @magic_link_max_age
    ) do
      {:ok, user_id} ->
        user = Repo.get!(User, user_id)
        {:ok, user}

      {:error, :expired} ->
        {:error, :token_expired}

      {:error, _} ->
        {:error, :invalid_token}
    end
  end
end
```

**Email Template**:
```elixir
def magic_link_email(to_email, token) do
  magic_link_url = build_magic_link_url(token)

  new()
  |> from({"Wombie", "auth@wombie.com"})
  |> to(to_email)
  |> subject("Sign in to Wombie")
  |> html_body("""
    <!DOCTYPE html>
    <html>
      <body>
        <h1>Sign In to Wombie</h1>
        <p>Click the button below to sign in to your account:</p>
        <p>
          <a href="#{magic_link_url}"
             style="background: #007bff; color: white; padding: 12px 24px;
                    text-decoration: none; border-radius: 4px; display: inline-block;">
            Sign In
          </a>
        </p>
        <p>This link will expire in 15 minutes.</p>
        <p>If you didn't request this, you can safely ignore this email.</p>
      </body>
    </html>
  """)
  |> text_body("""
    Sign In to Wombie

    Click the link below to sign in to your account:
    #{magic_link_url}

    This link will expire in 15 minutes.

    If you didn't request this, you can safely ignore this email.
  """)
end
```

---

### Security Considerations for Roll Your Own

1. **Token Security**:
   - Use `Phoenix.Token` with appropriate max_age values
   - Password reset: 1 hour expiry
   - Email verification: 24 hour expiry
   - Magic links: 15 minute expiry

2. **Rate Limiting**:
   - Implement rate limiting on auth endpoints (already have Plug.RateLimiter)
   - Limit password reset requests: 3 per hour per email
   - Limit verification email resends: 5 per day per user

3. **Email Security**:
   - Configure SPF/DKIM records for Resend
   - Validate email addresses before sending
   - Don't reveal whether email exists in system (password reset)
   - XSS prevention in email templates (already implemented)

4. **Token Invalidation**:
   - Password reset tokens should be single-use
   - Invalidate old tokens when new ones are generated
   - Consider storing token hashes in database for single-use validation

**Enhanced Implementation with Token Storage**:
```elixir
# Add to schema
defmodule Eventasaurus.Accounts.User do
  schema "users" do
    field :password_reset_token_hash, :string
    field :password_reset_sent_at, :utc_datetime
    field :email_verification_token_hash, :string
    field :email_verification_sent_at, :utc_datetime
  end
end

# Enhanced password reset
def request_password_reset(email) do
  case Repo.get_by(User, email: email) do
    nil ->
      {:ok, :email_sent}

    user ->
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      token_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

      user
      |> User.changeset(%{
        password_reset_token_hash: token_hash,
        password_reset_sent_at: DateTime.utc_now()
      })
      |> Repo.update()

      send_password_reset_email(user.email, token)
      {:ok, :email_sent}
  end
end

def verify_reset_token(token) do
  token_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  case Repo.get_by(User, password_reset_token_hash: token_hash) do
    nil ->
      {:error, :invalid_token}

    user ->
      # Check if token expired (1 hour)
      sent_at = user.password_reset_sent_at
      expiry = DateTime.add(sent_at, 3600, :second)

      if DateTime.compare(DateTime.utc_now(), expiry) == :gt do
        {:error, :token_expired}
      else
        # Invalidate token after verification
        user
        |> User.changeset(%{
          password_reset_token_hash: nil,
          password_reset_sent_at: nil
        })
        |> Repo.update()

        {:ok, user}
      end
  end
end
```

---

### Implementation Checklist for Roll Your Own

**Week 1-2: Core Email Infrastructure**
- [ ] Implement password reset flow + email template
- [ ] Implement email verification flow + email template
- [ ] Add token storage to User schema
- [ ] Implement token generation and verification
- [ ] Add rate limiting to auth endpoints

**Week 3: Additional Features**
- [ ] Implement password change confirmation email
- [ ] Implement OAuth account linked notification
- [ ] Add email resend functionality
- [ ] Implement magic link authentication (optional)

**Week 4: Security & Testing**
- [ ] Configure SPF/DKIM records for Resend
- [ ] Add comprehensive tests for all email flows
- [ ] Security audit (token expiry, rate limiting, XSS)
- [ ] Test email deliverability across providers (Gmail, Outlook, etc.)
- [ ] Add logging and monitoring for email delivery failures

**Week 5-6: Migration & Documentation**
- [ ] Create migration path from Supabase email verification states
- [ ] Document email templates and flows
- [ ] Create admin dashboard for email monitoring
- [ ] Deploy and monitor

**Estimated Total Time**: 4-6 weeks for production-ready implementation

---

## Comparison Matrix

| Feature | Clerk (Default) | Clerk (Resend) | Roll Your Own |
|---------|-----------------|----------------|---------------|
| **Implementation Time** | 0 days | 2-3 days | 4-6 weeks |
| **Email Control** | Low | High | Full |
| **Customization** | Dashboard only | Full templates | Full templates |
| **Deliverability** | Clerk-managed | Resend | Resend + SPF/DKIM |
| **Cost** | Included in Clerk | Resend only | Resend only |
| **Maintenance** | None | Low | Medium-High |
| **Testing** | Easy | Easy | Complex |
| **Security** | Clerk-managed | Clerk tokens + own delivery | Full responsibility |
| **Email Types** | All standard | All standard | All standard |
| **Rate Limiting** | Automatic | Manual | Manual |
| **Monitoring** | Clerk dashboard | Own + Resend | Own + Resend |

---

## Recommendations

### For Clerk Migration

**Recommended Approach**: Use Clerk with Resend (Option B - Custom Email Delivery)

**Rationale**:
1. ✅ Consistent infrastructure - all emails from Resend
2. ✅ Full control over branding and content
3. ✅ Reuse existing Swoosh + Oban + rate limiting setup
4. ✅ Easy to test and debug
5. ✅ Only 2-3 days implementation (webhook handler + 3-4 templates)
6. ✅ Clerk handles security (token generation, validation)
7. ✅ You control delivery (email content, timing, tracking)

**Implementation Effort**: 2-3 days
- Day 1: Webhook handler + verification email
- Day 2: Password reset + other auth emails
- Day 3: Testing + deployment

**Email Templates Needed**:
1. Email verification (sign-up)
2. Password reset
3. Email verification (new email)
4. Password change confirmation
5. Optional: Magic link, MFA codes

---

### For Roll Your Own Migration

**If Rolling Your Own**: Expect 4-6 weeks of focused development

**Rationale**:
1. ✅ No vendor lock-in
2. ✅ Zero monthly costs
3. ✅ Full control over everything
4. ❌ Significant development time
5. ❌ Security responsibility (token management, expiry, rate limiting)
6. ❌ Ongoing maintenance burden

**Implementation Priority**:
1. **Week 1-2**: Password reset + email verification (critical for auth)
2. **Week 3**: Security features + additional emails
3. **Week 4**: Testing + security audit
4. **Week 5-6**: Migration + documentation

**Key Dependencies**:
- Phoenix.Token (built-in) for secure token generation
- Swoosh + Resend (already have)
- Oban (already have) for background jobs
- Rate limiting (already have Plug.RateLimiter)

---

## Email Template Design Guidelines

Regardless of which option you choose, follow these email best practices:

### Deliverability
- Keep HTML simple, avoid complex CSS
- Include both HTML and plain text versions
- Use inline styles, not external CSS
- Test with Gmail, Outlook, Apple Mail
- Include unsubscribe link (for marketing emails, not auth emails)

### Security
- Use HTTPS for all links
- Make expiry times clear in email copy
- Don't include sensitive information
- Use secure token generation
- Implement single-use tokens where appropriate

### User Experience
- Clear call-to-action button
- Mobile-responsive design
- Consistent branding with existing emails
- Clear expiry information
- Alternative contact info if issues

### Template Consistency
Match existing invitation email style from `/lib/eventasaurus/emails.ex`:
- From: `{"Wombie", "auth@wombie.com"}`
- Color scheme: Match event invitation emails
- Logo/branding: Use existing CDN images
- Footer: Consistent footer across all emails

---

## Migration Path

### From Supabase to Clerk (with Resend)

1. **Pre-Migration**:
   - Document all current auth email flows
   - Test Clerk webhook integration in development
   - Implement email templates matching Supabase design
   - Set up monitoring for email delivery

2. **Migration**:
   - Configure Clerk webhooks
   - Deploy webhook handler
   - Run both systems in parallel (1 week)
   - Monitor email delivery rates
   - Gradually switch users to new system

3. **Post-Migration**:
   - Deprecate Supabase email handling
   - Monitor email deliverability
   - Gather user feedback
   - Iterate on email templates

**Risk**: Low - webhooks provide reliable email triggers

---

### From Supabase to Roll Your Own

1. **Pre-Migration**:
   - Implement all email flows
   - Comprehensive testing (unit + integration)
   - Security audit
   - Load testing for email delivery
   - Configure SPF/DKIM records

2. **Migration**:
   - Export user verification states from Supabase
   - Migrate unverified users to new system
   - Trigger re-verification for critical accounts
   - Run both systems in parallel (2 weeks)
   - Monitor closely for issues

3. **Post-Migration**:
   - Deprecate Supabase
   - Monitor error rates
   - Respond to user feedback
   - Ongoing security updates

**Risk**: Medium-High - more complex implementation, more potential issues

---

## Conclusion

**For Clerk**: Use custom email delivery with Resend for best balance of control and simplicity (2-3 days implementation)

**For Roll Your Own**: Budget 4-6 weeks for production-ready implementation with full email system

**Current Infrastructure**: Already have 80% of what you need (Swoosh + Resend + Oban + rate limiting) - just need to add auth-specific templates and token management.

---

## Next Steps

1. **Decide on auth migration approach** (Clerk vs Roll Your Own)
2. **If Clerk**: Decide on Clerk-managed emails vs. Resend integration
3. **Review email templates** needed for chosen approach
4. **Create implementation plan** with timeline
5. **Set up development environment** for testing
6. **Implement and test** email flows

---

**Related Documents**:
- Main evaluation: `AUTH_MIGRATION_EVALUATION.md`
- GitHub Issue: #2440 - Authentication Migration Evaluation
