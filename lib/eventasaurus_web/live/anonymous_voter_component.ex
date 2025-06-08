defmodule EventasaurusWeb.AnonymousVoterComponent do
  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Events

  def update(assigns, socket) do
    initial_data = %{"name" => "", "email" => ""}
    form = to_form(initial_data)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)
     |> assign(:form_data, initial_data)
     |> assign(:loading, false)
     |> assign(:errors, [])
    }
  end

  def handle_event("validate", %{"voter" => params}, socket) do
    # Merge new params with existing form data to preserve all fields
    existing_data = socket.assigns.form_data
    merged_data = Map.merge(existing_data, params)

    # Basic client-side validation
    errors = validate_voter_params(merged_data)
    form = to_form(merged_data, errors: errors)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:form_data, merged_data)
    }
  end

  def handle_event("submit", %{"voter" => params}, socket) do
    # Use the stored form data merged with final params
    existing_data = socket.assigns.form_data
    final_data = Map.merge(existing_data, params)
    %{"name" => name, "email" => email} = final_data

    # Check if this is a "save all votes" submission or single vote
    temp_votes = Map.get(socket.assigns, :temp_votes, %{})

    if map_size(temp_votes) > 0 do
      # This is a "save all votes" submission
      case validate_voter_params(final_data) do
        errors when map_size(errors) == 0 ->
          # Valid input, save all votes
          socket = assign(socket, :loading, true)
          send(self(), {:save_all_votes_for_user, socket.assigns.event.id, name, email, temp_votes, socket.assigns.date_options})
          {:noreply, socket}

        errors ->
          # Invalid input, show errors
          {:noreply, assign(socket, :errors, Map.values(errors))}
      end
    else
      # This is a single vote submission (legacy flow)
      # Validate inputs
      case validate_voter_params(final_data) do
        errors when map_size(errors) == 0 ->
          # Valid input, proceed with voting
          socket = assign(socket, :loading, true)

          # Get the pending vote from socket assigns
          pending_vote = socket.assigns.pending_vote
          option = Enum.find(socket.assigns.date_options, &(&1.id == pending_vote.option_id))

          if option do
            case Events.register_voter_and_cast_vote(socket.assigns.event.id, name, email, option, pending_vote.vote_type) do
              {:ok, :new_voter, _participant, _vote} ->
                send(self(), {:vote_success, :new_voter, name, email})
                {:noreply, assign(socket, :loading, false)}

              {:ok, :existing_user_voted, _participant, _vote} ->
                send(self(), {:vote_success, :existing_user_voted, name, email})
                {:noreply, assign(socket, :loading, false)}

              {:error, reason} ->
                send(self(), {:vote_error, reason})
                {:noreply, assign(socket, :loading, false)}
            end
          else
            send(self(), {:vote_error, :option_not_found})
            {:noreply, assign(socket, :loading, false)}
          end

        errors ->
          # Invalid input, show errors
          form = to_form(final_data, errors: errors)
          {:noreply, assign(socket, :form, form)}
      end
    end
  end

  def handle_event("close", _params, socket) do
    send(self(), :close_vote_modal)
    {:noreply, socket}
  end

  def handle_event("stop_propagation", _params, socket) do
    # This handler exists to prevent click event propagation
    # When someone clicks inside the modal, this stops the event from
    # bubbling up to the overlay's close handler
    {:noreply, socket}
  end

  defp validate_voter_params(%{"name" => name, "email" => email}) do
    errors = %{}

    errors = if name == nil or String.trim(name) == "" do
      Map.put(errors, :name, "Name is required")
    else
      errors
    end

    errors = if email == nil or String.trim(email) == "" do
      Map.put(errors, :email, "Email is required")
    else
      # Basic email validation
      if String.match?(email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/) do
        errors
      else
        Map.put(errors, :email, "Please enter a valid email address")
      end
    end

    errors
  end

  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50" phx-click="close" phx-target={@myself}>
      <div class="relative top-20 mx-auto p-5 border w-96 shadow-lg rounded-md bg-white" phx-click="stop_propagation" phx-target={@myself}>
        <div class="mt-3">
          <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-blue-100">
            <svg class="h-6 w-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
          </div>

          <h3 class="text-lg font-medium text-gray-900 text-center mt-4">
            Save Your Votes
          </h3>

          <!-- Vote Summary -->
          <div class="mt-4 p-3 bg-gray-50 rounded-lg">
            <h4 class="text-sm font-medium text-gray-900 mb-2">Your votes:</h4>
            <%= for {option_id, vote_type} <- @temp_votes do %>
              <% option = Enum.find(@date_options, &(&1.id == option_id)) %>
              <%= if option do %>
                <div class="flex justify-between items-center text-sm py-1">
                  <span class="text-gray-700">
                    <%= Calendar.strftime(option.date, "%b %d") %>
                  </span>
                  <span class={"font-medium " <>
                    case vote_type do
                      :yes -> "text-green-700"
                      :if_need_be -> "text-yellow-700"
                      :no -> "text-red-700"
                    end
                  }>
                    <%= case vote_type do
                      :yes -> "👍 Yes"
                      :if_need_be -> "🤷 If needed"
                      :no -> "👎 No"
                    end %>
                  </span>
                </div>
              <% end %>
            <% end %>
          </div>

          <p class="text-sm text-gray-500 text-center mt-4">
            Enter your details to save these votes. You'll receive a magic link via email to create your account.
          </p>

          <form phx-submit="submit" phx-target={@myself} class="mt-4">
            <div class="mb-4">
              <label for="voter_name" class="block text-sm font-medium text-gray-700">Name</label>
              <input
                type="text"
                name="voter[name]"
                id="voter_name"
                value={@form_data["name"]}
                phx-change="validate"
                phx-target={@myself}
                required
                class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                placeholder="Your full name"
              />
            </div>

            <div class="mb-4">
              <label for="voter_email" class="block text-sm font-medium text-gray-700">Email</label>
              <input
                type="email"
                name="voter[email]"
                id="voter_email"
                value={@form_data["email"]}
                phx-change="validate"
                phx-target={@myself}
                required
                class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                placeholder="your@email.com"
              />
            </div>

            <%= if @errors != [] do %>
              <div class="mb-4 text-red-600 text-sm">
                <%= for error <- @errors do %>
                  <p><%= error %></p>
                <% end %>
              </div>
            <% end %>

            <div class="flex gap-3">
              <button
                type="button"
                phx-click="close"
                phx-target={@myself}
                class="flex-1 bg-gray-300 hover:bg-gray-400 text-gray-800 font-medium py-2 px-4 rounded"
                disabled={@loading}
              >
                Cancel
              </button>

              <button
                type="submit"
                class="flex-1 bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded disabled:opacity-50"
                disabled={@loading}
              >
                <%= if @loading, do: "Saving...", else: "Save All Votes" %>
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
