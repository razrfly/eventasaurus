defmodule EventasaurusWeb.Auth.ClerkAuthHTML do
  @moduledoc """
  HTML templates for Clerk authentication pages.

  These templates render Clerk's pre-built UI components for sign-in,
  sign-up, and user profile management.
  """
  use EventasaurusWeb, :html

  # Import dev components - the component itself checks if dev mode
  import EventasaurusWeb.Dev.DevAuthComponent

  @doc """
  Clerk sign-in page.
  Renders Clerk's SignIn component.
  """
  def clerk_login(assigns) do
    ~H"""
    <div class="mx-auto max-w-md">
      <.header class="text-center mb-8">
        Sign in to your account
        <:subtitle>
          Don't have an account?
          <.link navigate={~p"/auth/register"} class="font-semibold text-brand hover:underline">
            Sign up
          </.link>
          for an account now.
        </:subtitle>
      </.header>

      <!-- Clerk SignIn component container - phx-update="ignore" prevents LiveView from touching this -->
      <div id="clerk-sign-in" class="flex justify-center" phx-update="ignore">
        <!-- Clerk.js will mount the SignIn component here -->
        <div class="text-center text-gray-500 py-8">
          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900 mx-auto mb-4"></div>
          Loading sign-in...
        </div>
      </div>

      <script>
        // Initialize Clerk SignIn component
        // Waits for both DOM and Clerk.js to be ready
        (function() {
          const containerId = 'clerk-sign-in';
          let mounted = false;

          async function initClerkSignIn() {
            if (mounted) return;

            const container = document.getElementById(containerId);
            if (!container) return;

            // Wait for Clerk.js to be loaded
            if (!window.Clerk) {
              setTimeout(initClerkSignIn, 100);
              return;
            }

            try {
              await window.Clerk.load();

              // Check if already signed in
              if (window.Clerk.user) {
                window.location.href = '<%= ~p"/dashboard" %>';
                return;
              }

              // Only mount if not already mounted
              if (!mounted) {
                mounted = true;
                container.innerHTML = ''; // Clear loading state
                // Build callback URL with return_to param (CDN-safe, doesn't rely on session)
                const returnTo = <%= Jason.encode!(@return_to) %>;
                const callbackUrl = returnTo
                  ? '/auth/callback?return_to=' + encodeURIComponent(returnTo)
                  : '/auth/callback';

                window.Clerk.mountSignIn(container, {
                  afterSignInUrl: callbackUrl,
                  afterSignUpUrl: callbackUrl,
                  signUpUrl: '<%= ~p"/auth/register" %>',
                  appearance: {
                    elements: {
                      rootBox: 'w-full flex justify-center',
                      card: 'shadow-none border border-gray-200 rounded-lg',
                      headerTitle: 'hidden',
                      headerSubtitle: 'hidden',
                      socialButtonsBlockButton: 'border border-gray-300 hover:bg-gray-50',
                      formButtonPrimary: 'bg-gray-950 hover:bg-gray-800',
                      footerAction: 'hidden'
                    }
                  }
                });
              }
            } catch (error) {
              console.error('Error mounting Clerk SignIn:', error);
            }
          }

          // Initialize based on document state
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initClerkSignIn);
          } else {
            // DOM already ready, init immediately
            initClerkSignIn();
          }
        })();
      </script>

      <.quick_login_section users={EventasaurusWeb.Dev.DevAuth.list_quick_login_users()} />
    </div>
    """
  end

  @doc """
  Clerk sign-up page.
  Renders Clerk's SignUp component.
  """
  def clerk_register(assigns) do
    ~H"""
    <div class="mx-auto max-w-md">
      <.header class="text-center mb-8">
        <%= if @event do %>
          Create your account
        <% else %>
          Create an account
        <% end %>
        <:subtitle>
          <%= if @event do %>
            You've been invited to create an account for <strong><%= @event.title %></strong>!
          <% else %>
            Already have an account?
            <.link navigate={~p"/auth/login"} class="font-semibold text-brand hover:underline">
              Sign in
            </.link>
            instead.
          <% end %>
        </:subtitle>
      </.header>

      <!-- Clerk SignUp component container - phx-update="ignore" prevents LiveView from touching this -->
      <div id="clerk-sign-up" class="flex justify-center" phx-update="ignore">
        <!-- Clerk.js will mount the SignUp component here -->
        <div class="text-center text-gray-500 py-8">
          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900 mx-auto mb-4"></div>
          Loading registration...
        </div>
      </div>

      <script>
        // Initialize Clerk SignUp component
        // Uses IIFE pattern matching SignIn for consistency
        (function() {
          const containerId = 'clerk-sign-up';
          let mounted = false;

          async function initClerkSignUp() {
            if (mounted) return;

            const container = document.getElementById(containerId);
            if (!container) return;

            // Wait for Clerk.js to be loaded
            if (!window.Clerk) {
              setTimeout(initClerkSignUp, 100);
              return;
            }

            try {
              await window.Clerk.load();

              // Check if already signed in
              if (window.Clerk.user) {
                window.location.href = '<%= ~p"/dashboard" %>';
                return;
              }

              // Only mount if not already mounted
              if (!mounted) {
                mounted = true;
                container.innerHTML = ''; // Clear loading state
                window.Clerk.mountSignUp(container, {
                  afterSignInUrl: '<%= ~p"/auth/callback" %>',
                  afterSignUpUrl: '<%= ~p"/auth/callback" %>',
                  signInUrl: '<%= ~p"/auth/login" %>',
                  appearance: {
                    elements: {
                      rootBox: 'w-full flex justify-center',
                      card: 'shadow-none border border-gray-200 rounded-lg',
                      headerTitle: 'hidden',
                      headerSubtitle: 'hidden',
                      socialButtonsBlockButton: 'border border-gray-300 hover:bg-gray-50',
                      formButtonPrimary: 'bg-gray-950 hover:bg-gray-800',
                      footerAction: 'hidden'
                    }
                  }
                });
              }
            } catch (error) {
              console.error('Error mounting Clerk SignUp:', error);
            }
          }

          // Initialize based on document state
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initClerkSignUp);
          } else {
            // DOM already ready, init immediately
            initClerkSignUp();
          }
        })();
      </script>

      <%= if @event do %>
        <div class="mt-6 text-center text-sm text-gray-500">
          Creating an account for: <strong><%= @event.title %></strong>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Clerk user profile page.
  Renders Clerk's UserProfile component.
  """
  def clerk_profile(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header class="mb-8">
        Account Settings
        <:subtitle>Manage your account settings and profile</:subtitle>
      </.header>

      <!-- Clerk UserProfile component container - phx-update="ignore" prevents LiveView from touching this -->
      <div id="clerk-user-profile" class="flex justify-center" phx-update="ignore">
        <!-- Clerk.js will mount the UserProfile component here -->
        <div class="text-center text-gray-500 py-8">
          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900 mx-auto mb-4"></div>
          Loading profile...
        </div>
      </div>

      <script>
        // Initialize Clerk UserProfile component
        // Uses IIFE pattern matching SignIn for consistency
        (function() {
          const containerId = 'clerk-user-profile';
          let mounted = false;

          async function initClerkUserProfile() {
            if (mounted) return;

            const container = document.getElementById(containerId);
            if (!container) return;

            // Wait for Clerk.js to be loaded
            if (!window.Clerk) {
              setTimeout(initClerkUserProfile, 100);
              return;
            }

            try {
              await window.Clerk.load();

              // Check if signed in
              if (!window.Clerk.user) {
                window.location.href = '<%= ~p"/auth/login" %>';
                return;
              }

              // Only mount if not already mounted
              if (!mounted) {
                mounted = true;
                container.innerHTML = ''; // Clear loading state
                window.Clerk.mountUserProfile(container, {
                  appearance: {
                    elements: {
                      rootBox: 'w-full',
                      card: 'shadow-none border border-gray-200 rounded-lg',
                    }
                  }
                });
              }
            } catch (error) {
              console.error('Error mounting Clerk UserProfile:', error);
            }
          }

          // Initialize based on document state
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initClerkUserProfile);
          } else {
            // DOM already ready, init immediately
            initClerkUserProfile();
          }
        })();
      </script>
    </div>
    """
  end
end
