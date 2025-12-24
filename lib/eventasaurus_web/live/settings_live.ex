defmodule EventasaurusWeb.SettingsLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Accounts.UserPreferences
  alias EventasaurusApp.Stripe
  alias EventasaurusWeb.Live.UsernameHelper

  def mount(params, _session, socket) do
    tab = Map.get(params, "tab", "account")

    # User is already assigned by AuthHooks via :require_authenticated_user
    user = socket.assigns.user
    form = User.profile_changeset(user, %{}) |> to_form()

    # Get Stripe Connect account for payments tab
    connect_account = if tab == "payments", do: Stripe.get_connect_account(user.id), else: nil

    # Get user preferences for privacy tab
    preferences = Accounts.get_preferences_or_defaults(user)
    preferences_form = build_preferences_form(user, preferences)

    {:ok,
     socket
     |> assign(:active_tab, tab)
     |> assign(:form, form)
     |> assign(:form_data, %{})
     |> assign(:connect_account, connect_account)
     |> assign(:preferences, preferences)
     |> assign(:preferences_form, preferences_form)
     |> assign(:page_title, "Settings")
     |> UsernameHelper.enable_username_checking()}
  end

  defp build_preferences_form(user, preferences) do
    # Get or create actual preferences struct for changeset
    # Convert preferences struct to map for cast/3 compatibility
    attrs = Map.take(preferences, [:connection_permission, :show_on_attendee_lists, :discoverable_in_suggestions])

    case Accounts.get_preferences(user) do
      nil ->
        %UserPreferences{user_id: user.id}
        |> UserPreferences.changeset(attrs)
        |> to_form()

      prefs ->
        prefs
        |> UserPreferences.update_changeset(%{})
        |> to_form()
    end
  end

  def handle_params(%{"tab" => tab}, _uri, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_params(_, _uri, socket) do
    {:noreply, assign(socket, :active_tab, "account")}
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> User.profile_changeset(user_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(form: to_form(changeset))
     |> assign(form_data: user_params)}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case update_user_profile(socket.assigns.user, user_params) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:form, User.profile_changeset(updated_user, %{}) |> to_form())
         |> put_flash(:info, "Profile updated successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, "Failed to update profile. Please check the errors below.")}
    end
  end

  def handle_event("validate_preferences", %{"user_preferences" => prefs_params}, socket) do
    user = socket.assigns.user

    changeset =
      case Accounts.get_preferences(user) do
        nil ->
          %UserPreferences{user_id: user.id}
          |> UserPreferences.changeset(prefs_params)

        prefs ->
          prefs
          |> UserPreferences.update_changeset(prefs_params)
      end
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :preferences_form, to_form(changeset))}
  end

  def handle_event("save_preferences", %{"user_preferences" => prefs_params}, socket) do
    user = socket.assigns.user

    case Accounts.update_user_preferences(user, prefs_params) do
      {:ok, updated_prefs} ->
        {:noreply,
         socket
         |> assign(:preferences, Map.from_struct(updated_prefs))
         |> assign(:preferences_form, build_preferences_form(user, Map.from_struct(updated_prefs)))
         |> put_flash(:info, "Privacy settings updated successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:preferences_form, to_form(changeset))
         |> put_flash(:error, "Failed to update privacy settings.")}
    end
  end

  # Handle async username check requests
  def handle_info({:check_username_async, username, component_id}, socket) do
    UsernameHelper.handle_username_check_async(username, component_id, socket)
  end

  # Handle username check task completion
  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) do
    case socket.assigns[:username_check_task] do
      {%Task{ref: task_ref}, username, component_id} when task_ref == ref ->
        UsernameHelper.handle_username_check_complete(socket, username, component_id)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({ref, result}, socket) when is_reference(ref) do
    case socket.assigns[:username_check_task] do
      {%Task{ref: ^ref}, username, component_id} ->
        UsernameHelper.handle_username_check_result(socket, result, username, component_id)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:timezone_selected, timezone}, socket) do
    # Update the form with the selected timezone
    current_params = socket.assigns.form_data || %{}
    updated_params = Map.put(current_params, "timezone", timezone)

    changeset =
      socket.assigns.user
      |> User.profile_changeset(updated_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(form: to_form(changeset))
     |> assign(form_data: updated_params)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div class="px-4 py-6 sm:px-0">
      <div class="rounded-lg bg-white p-6 shadow">
        <h1 class="text-2xl font-bold mb-6">Settings</h1>

        <!-- Tab Navigation -->
        <div class="border-b border-gray-200 mb-6">
          <nav class="-mb-px flex space-x-8" aria-label="Tabs">
            <.link
              patch={~p"/settings/account"}
              class={[
                "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm",
                if(@active_tab == "account",
                  do: "border-indigo-500 text-indigo-600",
                  else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
                )
              ]}
            >
              Account
            </.link>

            <.link
              patch={~p"/settings/payments"}
              class={[
                "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm",
                if(@active_tab == "payments",
                  do: "border-indigo-500 text-indigo-600",
                  else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
                )
              ]}
            >
              Payments
            </.link>

            <.link
              patch={~p"/settings/privacy"}
              class={[
                "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm",
                if(@active_tab == "privacy",
                  do: "border-indigo-500 text-indigo-600",
                  else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
                )
              ]}
            >
              Privacy
            </.link>
          </nav>
        </div>

        <%= if @active_tab == "account" do %>
          <!-- Two-column layout: Form on left, Preview on right -->
          <div class="grid grid-cols-1 xl:grid-cols-3 gap-6">
            <!-- Form Column (2/3 width on large screens) -->
            <div class="xl:col-span-2 space-y-6">
              <!-- Profile Information -->
              <div class="bg-white border border-gray-200 rounded-lg p-6">
              <div class="flex items-center mb-6">
                <%= avatar_img_size(@user, :lg, class: "mr-4") %>
                <div>
                  <h2 class="text-xl font-semibold">Profile Information</h2>
                  <p class="text-gray-600">Update your account's profile information and social links.</p>
                </div>
              </div>

              <.form
                for={@form}
                phx-change="validate"
                phx-submit="save"
                class="space-y-6"
              >
                <!-- Basic Information -->
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <.input field={@form[:name]} type="text" label="Full Name" placeholder="Enter your full name" />
                  </div>
                  <div>
                    <.input field={@form[:email]} type="email" label="Email Address" value={@user.email} disabled placeholder="Enter your email" />
                    <p class="mt-1 text-sm text-gray-500">Email cannot be changed from here</p>
                  </div>
                </div>

                <!-- Username and Website -->
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <.live_component
                      module={EventasaurusWeb.UsernameInputComponent}
                      id="username-input"
                      field={@form[:username]}
                      placeholder="Choose a unique username"
                      debounce={500}
                    />
                  </div>
                  <div>
                    <.input field={@form[:website_url]} type="url" label="Website" placeholder="https://your-website.com" />
                  </div>
                </div>

                <!-- Bio -->
                <div>
                  <.input field={@form[:bio]} type="textarea" label="Bio" placeholder="Tell people about yourself..." />
                  <p class="mt-1 text-sm text-gray-500">Max 500 characters</p>
                </div>

                <!-- Social Media Handles -->
                <div class="border-t border-gray-200 pt-6">
                  <h3 class="text-lg font-medium text-gray-900 mb-4">Social Media</h3>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <label class="block text-sm font-semibold leading-6 text-zinc-800">Instagram</label>
                      <div class="mt-1 flex rounded-md shadow-sm">
                        <span class="inline-flex items-center px-3 rounded-l-md border border-r-0 border-gray-300 bg-gray-50 text-gray-500 text-sm">@</span>
                        <.input field={@form[:instagram_handle]} type="text" placeholder="username" class="rounded-l-none border-l-0" />
                      </div>
                    </div>

                    <div>
                      <label class="block text-sm font-semibold leading-6 text-zinc-800">X</label>
                      <div class="mt-1 flex rounded-md shadow-sm">
                        <span class="inline-flex items-center px-3 rounded-l-md border border-r-0 border-gray-300 bg-gray-50 text-gray-500 text-sm">@</span>
                        <.input field={@form[:x_handle]} type="text" placeholder="username" class="rounded-l-none border-l-0" />
                      </div>
                    </div>

                    <div>
                      <.input field={@form[:youtube_handle]} type="text" label="YouTube" placeholder="Channel handle or URL" />
                    </div>

                    <div>
                      <label class="block text-sm font-semibold leading-6 text-zinc-800">TikTok</label>
                      <div class="mt-1 flex rounded-md shadow-sm">
                        <span class="inline-flex items-center px-3 rounded-l-md border border-r-0 border-gray-300 bg-gray-50 text-gray-500 text-sm">@</span>
                        <.input field={@form[:tiktok_handle]} type="text" placeholder="username" class="rounded-l-none border-l-0" />
                      </div>
                    </div>

                    <div>
                      <.input field={@form[:linkedin_handle]} type="text" label="LinkedIn" placeholder="Profile URL or username" />
                    </div>
                  </div>
                </div>

                <!-- Preferences -->
                <div class="border-t border-gray-200 pt-6">
                  <h3 class="text-lg font-medium text-gray-900 mb-4">Preferences</h3>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <label class="block text-sm font-semibold leading-6 text-zinc-800 mb-2">Default Currency</label>
                      <.currency_select
                        name="user[default_currency]"
                        id="user_default_currency"
                        value={Phoenix.HTML.Form.input_value(@form, :default_currency)}
                        prompt="Select Currency"
                      />
                    </div>

                    <div>
                                    <!-- Timezone Selector -->
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Timezone</label>
                <.live_component
                  module={EventasaurusWeb.TimezoneSelectorComponent}
                  id="timezone-selector"
                  field={@form[:timezone]}
                  selected_timezone={Phoenix.HTML.Form.input_value(@form, :timezone)}
                />
                <p class="mt-1 text-sm text-gray-500">Your local timezone</p>
              </div>
                    </div>
                  </div>
                </div>

                <!-- Privacy Settings -->
                <div class="border-t border-gray-200 pt-6">
                  <h3 class="text-lg font-medium text-gray-900 mb-4">Privacy</h3>
                  <div class="flex items-center">
                    <.input field={@form[:profile_public]} type="checkbox" label="Make my profile public" />
                  </div>
                  <p class="mt-2 text-sm text-gray-500">Allow others to view your public profile page</p>
                </div>

                <div class="flex justify-end">
                  <.button type="submit" class="bg-indigo-600 hover:bg-indigo-700 text-white">
                    Save Changes
                  </.button>
                </div>
              </.form>
            </div>
            </div>

            <!-- Preview Column (1/3 width on large screens) -->
            <div class="xl:col-span-1">
              <.live_component
                module={EventasaurusWeb.ProfilePreviewComponent}
                id="profile-preview"
                user={@user}
                form_data={@form_data}
              />
            </div>
          </div>
        <% end %>

        <%= if @active_tab == "payments" do %>
          <div class="space-y-6">
            <div class="bg-white border border-gray-200 rounded-lg p-6">
              <h2 class="text-xl font-semibold text-gray-900 mb-6">Payment Settings</h2>

              <%= if @connect_account do %>
                <div class="bg-green-50 border border-green-200 rounded-lg p-6 mb-6">
                  <div class="flex items-center">
                    <svg class="w-6 h-6 text-green-500 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                    </svg>
                    <h3 class="text-xl font-semibold text-green-800">Connected to Stripe</h3>
                  </div>

                  <div class="mt-4 text-green-700">
                    <p><strong>Account ID:</strong> <%= @connect_account.stripe_user_id %></p>
                    <p><strong>Connected on:</strong> <%= Calendar.strftime(@connect_account.connected_at, "%B %d, %Y at %I:%M %p") %></p>
                  </div>

                  <div class="mt-6">
                    <p class="text-green-700 mb-4">
                      Your Stripe account is connected and ready to receive payments! When customers purchase tickets to your events, the funds will be transferred directly to your Stripe account.
                    </p>

                    <form action="/stripe/disconnect" method="post" onsubmit="return confirm('Are you sure you want to disconnect your Stripe account? You won\\'t be able to receive payments until you reconnect.')">
                      <button type="submit" class="bg-red-600 hover:bg-red-700 text-white font-medium py-2 px-4 rounded-lg transition-colors cursor-pointer">
                        Disconnect Stripe Account
                      </button>
                    </form>
                  </div>
                </div>
              <% else %>
                <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-6 mb-6">
                  <div class="flex items-center">
                    <svg class="w-6 h-6 text-yellow-500 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.96-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
                    </svg>
                    <h3 class="text-xl font-semibold text-yellow-800">Stripe Account Not Connected</h3>
                  </div>

                  <div class="mt-4 text-yellow-700">
                    <p class="mb-4">
                      To receive payments for your events, you need to connect your Stripe account. This allows customers to pay you directly, and Eventasaurus will handle the payment processing.
                    </p>

                    <h4 class="font-semibold mb-2">What happens when you connect:</h4>
                    <ul class="list-disc list-inside space-y-1 mb-6">
                      <li>Customer payments go directly to your Stripe account</li>
                      <li>Eventasaurus takes a small platform fee</li>
                      <li>You control your own payout schedule and settings</li>
                      <li>Full transparency through your Stripe dashboard</li>
                    </ul>

                    <a href="/stripe/connect"
                       class="inline-flex items-center px-6 py-3 bg-purple-600 hover:bg-purple-700 text-white font-medium rounded-lg transition-colors">
                      <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"></path>
                      </svg>
                      Connect Your Stripe Account
                    </a>
                  </div>
                </div>
              <% end %>

              <div class="bg-gray-50 border border-gray-200 rounded-lg p-6">
                <h4 class="text-lg font-semibold text-gray-900 mb-3">Need Help?</h4>
                <p class="text-gray-700 mb-4">
                  If you have questions about connecting your Stripe account or receiving payments, check out our help documentation or contact support.
                </p>
                <div class="flex space-x-4">
                  <a href="/help/payments" class="text-purple-600 hover:text-purple-700 font-medium">Payment Help</a>
                  <a href="/support" class="text-purple-600 hover:text-purple-700 font-medium">Contact Support</a>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @active_tab == "privacy" do %>
          <div class="space-y-6">
            <div class="bg-white border border-gray-200 rounded-lg p-6">
              <h2 class="text-xl font-semibold text-gray-900 mb-2">Privacy Settings</h2>
              <p class="text-gray-600 mb-6">Control how others can interact with you on Eventasaurus.</p>

              <.form
                for={@preferences_form}
                phx-change="validate_preferences"
                phx-submit="save_preferences"
                class="space-y-6"
              >
                <!-- Who Can Reach Out -->
                <div class="border-t border-gray-200 pt-6">
                  <h3 class="text-lg font-medium text-gray-900 mb-4">Who can reach out to you?</h3>
                  <p class="text-sm text-gray-600 mb-4">
                    Choose who can add you to their people. This doesn't affect existing relationships.
                  </p>

                  <div class="space-y-4">
                    <label class={[
                      "flex items-start p-4 border rounded-lg cursor-pointer transition-colors",
                      if(get_preference_value(@preferences_form, :connection_permission) == :closed,
                        do: "border-indigo-500 bg-indigo-50",
                        else: "border-gray-200 hover:border-gray-300"
                      )
                    ]}>
                      <input
                        type="radio"
                        name={@preferences_form[:connection_permission].name}
                        value="closed"
                        checked={get_preference_value(@preferences_form, :connection_permission) == :closed}
                        class="mt-1 h-4 w-4 text-indigo-600 focus:ring-indigo-500"
                      />
                      <div class="ml-3">
                        <span class="block text-sm font-medium text-gray-900">
                          Let me reach out first
                        </span>
                        <span class="block text-sm text-gray-500">
                          Only you can reach out first. Others will see a disabled button.
                        </span>
                      </div>
                    </label>

                    <label class={[
                      "flex items-start p-4 border rounded-lg cursor-pointer transition-colors",
                      if(get_preference_value(@preferences_form, :connection_permission) == :event_attendees,
                        do: "border-indigo-500 bg-indigo-50",
                        else: "border-gray-200 hover:border-gray-300"
                      )
                    ]}>
                      <input
                        type="radio"
                        name={@preferences_form[:connection_permission].name}
                        value="event_attendees"
                        checked={get_preference_value(@preferences_form, :connection_permission) == :event_attendees}
                        class="mt-1 h-4 w-4 text-indigo-600 focus:ring-indigo-500"
                      />
                      <div class="ml-3">
                        <span class="block text-sm font-medium text-gray-900">
                          People I've been to events with
                        </span>
                        <span class="block text-sm text-gray-500">
                          Only people who have attended the same events as you can reach out. This is the default.
                        </span>
                      </div>
                    </label>

                    <label class={[
                      "flex items-start p-4 border rounded-lg cursor-pointer transition-colors",
                      if(get_preference_value(@preferences_form, :connection_permission) == :extended_network,
                        do: "border-indigo-500 bg-indigo-50",
                        else: "border-gray-200 hover:border-gray-300"
                      )
                    ]}>
                      <input
                        type="radio"
                        name={@preferences_form[:connection_permission].name}
                        value="extended_network"
                        checked={get_preference_value(@preferences_form, :connection_permission) == :extended_network}
                        class="mt-1 h-4 w-4 text-indigo-600 focus:ring-indigo-500"
                      />
                      <div class="ml-3">
                        <span class="block text-sm font-medium text-gray-900">
                          Friends of friends
                        </span>
                        <span class="block text-sm text-gray-500">
                          People who are connected to someone you're connected with can reach out.
                        </span>
                      </div>
                    </label>

                    <label class={[
                      "flex items-start p-4 border rounded-lg cursor-pointer transition-colors",
                      if(get_preference_value(@preferences_form, :connection_permission) == :open,
                        do: "border-indigo-500 bg-indigo-50",
                        else: "border-gray-200 hover:border-gray-300"
                      )
                    ]}>
                      <input
                        type="radio"
                        name={@preferences_form[:connection_permission].name}
                        value="open"
                        checked={get_preference_value(@preferences_form, :connection_permission) == :open}
                        class="mt-1 h-4 w-4 text-indigo-600 focus:ring-indigo-500"
                      />
                      <div class="ml-3">
                        <span class="block text-sm font-medium text-gray-900">
                          Open to everyone
                        </span>
                        <span class="block text-sm text-gray-500">
                          Anyone on Eventasaurus can reach out to you.
                        </span>
                      </div>
                    </label>
                  </div>
                </div>

                <div class="flex justify-end pt-4">
                  <.button type="submit" class="bg-indigo-600 hover:bg-indigo-700 text-white">
                    Save Privacy Settings
                  </.button>
                </div>
              </.form>
            </div>

            <!-- Future placeholder for additional privacy settings -->
            <div class="bg-gray-50 border border-gray-200 rounded-lg p-6">
              <h4 class="text-lg font-semibold text-gray-900 mb-3">More privacy controls coming soon</h4>
              <p class="text-gray-700">
                We're working on additional privacy features including visibility controls for attendee lists
                and discovery settings.
              </p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Get the current value of a preference field
  defp get_preference_value(form, field) do
    Phoenix.HTML.Form.input_value(form, field)
  end

  # Helper functions
  defp update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> EventasaurusApp.Repo.update()
  end
end
