defmodule EventasaurusWeb.AnonymousVoterComponent do
  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Events

  def update(assigns, socket) do
    initial_data = %{"name" => "", "email" => ""}
    form = to_form(initial_data)

    # Determine poll type and options based on assigns
    {poll_type, poll_options} = determine_poll_context(assigns)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)
     |> assign(:form_data, initial_data)
     |> assign(:loading, false)
     |> assign(:errors, [])
     |> assign(:poll_type, poll_type)
     |> assign(:poll_options, poll_options)}
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
     |> assign(:form_data, merged_data)}
  end

  def handle_event("submit", %{"voter" => params}, socket) do
    # Use the stored form data merged with final params
    existing_data = socket.assigns.form_data
    final_data = Map.merge(existing_data, params)
    %{"name" => name, "email" => email} = final_data

    # Check if this is a "save all votes" submission or single vote
    temp_votes = Map.get(socket.assigns, :temp_votes, %{})

    if has_temp_votes?(temp_votes) do
      # This is a "save all votes" submission
      case validate_voter_params(final_data) do
        errors when map_size(errors) == 0 ->
          # Valid input, save all votes
          socket = assign(socket, :loading, true)

          # Send appropriate message based on poll type
          case socket.assigns.poll_type do
            :date_poll ->
              send(
                self(),
                {:save_all_votes_for_user, socket.assigns.event.id, name, email, temp_votes,
                 socket.assigns.poll_options}
              )

            :generic_poll ->
              send(
                self(),
                {:save_all_poll_votes_for_user, socket.assigns.poll.id, name, email, temp_votes,
                 socket.assigns.poll_options}
              )
          end

          {:noreply, socket}

        errors ->
          # Invalid input, show errors
          {:noreply, assign(socket, :errors, Map.values(errors))}
      end
    else
      # This is a single vote submission (legacy flow)
      handle_single_vote_submission(socket, final_data, name, email)
    end
  end

  def handle_event("close", _params, socket) do
    case socket.assigns.poll_type do
      :generic_poll ->
        send(self(), :close_generic_vote_modal)
      _ ->
        send(self(), :close_vote_modal)
    end
    {:noreply, socket}
  end

  def handle_event("stop_propagation", _params, socket) do
    # This handler exists to prevent click event propagation
    # When someone clicks inside the modal, this stops the event from
    # bubbling up to the overlay's close handler
    {:noreply, socket}
  end

  # Private helper functions

  defp determine_poll_context(assigns) do
    cond do
      # Date polling context (backward compatibility)
      Map.has_key?(assigns, :date_options) ->
        {:date_poll, assigns.date_options}

      # Generic polling context
      Map.has_key?(assigns, :poll) and Map.has_key?(assigns, :poll_options) ->
        {:generic_poll, assigns.poll_options}

      # Fallback - try to infer from available data
      true ->
        {:date_poll, Map.get(assigns, :date_options, [])}
    end
  end

  defp has_temp_votes?(temp_votes) when is_map(temp_votes) do
    case temp_votes do
      # Handle new format with poll_type (check this first!)
      %{poll_type: _type, votes: votes} when is_map(votes) ->
        map_size(votes) > 0

      # Handle legacy format (simple map)
      votes when is_map(votes) ->
        map_size(votes) > 0

      _ ->
        false
    end
  end

  defp handle_single_vote_submission(socket, final_data, name, email) do
    # Validate inputs
    case validate_voter_params(final_data) do
      errors when map_size(errors) == 0 ->
        # Valid input, proceed with voting
        socket = assign(socket, :loading, true)

        # Get the pending vote from socket assigns
        pending_vote = socket.assigns.pending_vote
        option = Enum.find(socket.assigns.poll_options, &(&1.id == pending_vote.option_id))

        if option do
          case socket.assigns.poll_type do
            :date_poll ->
              handle_date_poll_single_vote(socket, name, email, option, pending_vote)

            :generic_poll ->
              handle_generic_poll_single_vote(socket, name, email, option, pending_vote)
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

  defp handle_date_poll_single_vote(socket, name, email, option, pending_vote) do
    case Events.register_voter_and_cast_vote(
           socket.assigns.event.id,
           name,
           email,
           option,
           pending_vote.vote_type
         ) do
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
  end

  defp handle_generic_poll_single_vote(socket, name, email, option, pending_vote) do
    # For generic polls, we'll need to implement the equivalent service
    # This would call Events.register_voter_and_cast_poll_vote or similar
    case Events.register_voter_and_cast_poll_vote(
           socket.assigns.poll.id,
           name,
           email,
           option,
           pending_vote.vote_value
         ) do
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
  end

  defp validate_voter_params(%{"name" => name, "email" => email}) do
    errors = %{}

    errors =
      if name == nil or String.trim(name) == "" do
        Map.put(errors, :name, "Name is required")
      else
        errors
      end

    errors =
      if email == nil or String.trim(email) == "" do
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
    <div class="fixed inset-0 bg-gray-900 bg-opacity-75 overflow-y-auto h-full w-full z-50" phx-click="close" phx-target={@myself}>
      <div class="relative top-20 mx-auto p-5 border border-gray-200 dark:border-gray-700 w-96 shadow-lg rounded-md bg-white dark:bg-gray-800" phx-click="stop_propagation" phx-target={@myself}>
        <div class="mt-3">
          <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-blue-600">
            <svg class="h-6 w-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
          </div>

          <h3 class="text-lg font-medium text-gray-900 dark:text-white text-center mt-4">
            Save Your Votes
          </h3>

          <!-- Vote Summary -->
          <div class="mt-4 p-3 bg-gray-50 dark:bg-gray-700 rounded-lg border border-gray-200 dark:border-gray-600">
            <h4 class="text-sm font-medium text-gray-900 dark:text-white mb-2">Your votes:</h4>
            <%= render_vote_summary(assigns) %>
          </div>

          <p class="text-sm text-gray-500 dark:text-gray-400 text-center mt-4">
            Enter your details to save these votes. You'll receive a magic link via email to create your account.
          </p>

          <form phx-submit="submit" phx-target={@myself} class="mt-4">
            <div class="mb-4">
              <label for="voter_name" class="block text-sm font-medium text-gray-700 dark:text-gray-300">Name</label>
              <input
                type="text"
                name="voter[name]"
                id="voter_name"
                value={@form_data["name"]}
                phx-change="validate"
                phx-debounce="300"
                phx-target={@myself}
                required
                class="mt-1 block w-full border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                placeholder="Your full name"
              />
            </div>

            <div class="mb-4">
              <label for="voter_email" class="block text-sm font-medium text-gray-700 dark:text-gray-300">Email</label>
              <input
                type="email"
                name="voter[email]"
                id="voter_email"
                value={@form_data["email"]}
                phx-change="validate"
                phx-debounce="300"
                phx-target={@myself}
                required
                class="mt-1 block w-full border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                placeholder="your@email.com"
              />
            </div>

            <%= if @errors != [] do %>
              <div class="mb-4 text-red-600 dark:text-red-400 text-sm">
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
                class="flex-1 bg-gray-300 dark:bg-gray-600 hover:bg-gray-400 dark:hover:bg-gray-500 text-gray-800 dark:text-gray-200 font-medium py-2 px-4 rounded transition-colors"
                disabled={@loading}
              >
                Cancel
              </button>

              <button
                type="submit"
                class="flex-1 bg-blue-600 hover:bg-blue-700 dark:bg-blue-600 dark:hover:bg-blue-700 text-white font-medium py-2 px-4 rounded disabled:opacity-50 transition-colors"
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

  # Vote summary rendering functions

  defp render_vote_summary(assigns) do
    case assigns.poll_type do
      :date_poll ->
        render_date_poll_summary(assigns)

      :generic_poll ->
        render_generic_poll_summary(assigns)
    end
  end

  defp render_date_poll_summary(assigns) do
    ~H"""
    <%= for {option_id, vote_type} <- @temp_votes do %>
      <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
      <%= if option do %>
        <div class="flex justify-between items-center text-sm py-1">
          <span class="text-gray-700 dark:text-gray-300">
            <%= Calendar.strftime(option.date, "%b %d") %>
          </span>
          <span class={"font-medium " <> get_date_vote_color(vote_type)}>
            <%= get_date_vote_display(vote_type) %>
          </span>
        </div>
      <% end %>
    <% end %>
    """
  end

  defp render_generic_poll_summary(assigns) do
    ~H"""
    <%= case @temp_votes do %>
      <% votes when is_map(votes) and not is_map_key(votes, :poll_type) -> %>
        <!-- Legacy format - simple map -->
        <%= for {option_id, vote_value} <- votes do %>
          <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
          <%= if option do %>
            <div class="flex justify-between items-center text-sm py-1">
              <span class="text-gray-700 dark:text-gray-300">
                <%= option.title %>
              </span>
              <span class="font-medium text-blue-600 dark:text-blue-400">
                <%= format_vote_value(vote_value) %>
              </span>
            </div>
          <% end %>
        <% end %>

      <% %{poll_type: poll_type, votes: votes} -> %>
        <!-- New format with poll_type -->
        <%= render_typed_vote_summary(assigns, poll_type, votes) %>

      <% _ -> %>
        <div class="text-sm text-gray-500 dark:text-gray-400">No votes to display</div>
    <% end %>
    """
  end

  defp render_typed_vote_summary(assigns, poll_type, votes) do
    case poll_type do
      :binary ->
        render_binary_vote_summary(assigns, votes)

      :approval ->
        render_approval_vote_summary(assigns, votes)

      :ranked ->
        render_ranked_vote_summary(assigns, votes)

      :star ->
        render_star_vote_summary(assigns, votes)
    end
  end

  defp render_binary_vote_summary(assigns, votes) do
    assigns = assign(assigns, :votes, votes)

    ~H"""
    <%= for {option_id, vote_value} <- @votes do %>
      <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
      <%= if option do %>
        <div class="flex justify-between items-center text-sm py-1">
          <span class="text-gray-700 dark:text-gray-300">
            <%= option.title %>
          </span>
          <span class={"font-medium " <> get_binary_vote_color(vote_value)}>
            <%= get_binary_vote_display(vote_value) %>
          </span>
        </div>
      <% end %>
    <% end %>
    """
  end

  defp render_approval_vote_summary(assigns, votes) do
    assigns = assign(assigns, :votes, votes)

    ~H"""
    <%= for {option_id, _vote_value} <- @votes do %>
      <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
      <%= if option do %>
        <div class="flex justify-between items-center text-sm py-1">
          <span class="text-gray-700 dark:text-gray-300">
            <%= option.title %>
          </span>
          <span class="font-medium text-green-600 dark:text-green-400">
            ✓ Selected
          </span>
        </div>
      <% end %>
    <% end %>
    """
  end

  defp render_ranked_vote_summary(assigns, votes) do
    assigns = assign(assigns, :votes, votes)

    ~H"""
    <%= for vote <- @votes |> Enum.sort_by(fn
          %{rank: rank} -> rank
          {_id, rank} -> rank
        end) do %>
      <% {option_id, rank} = case vote do
          %{option_id: oid, rank: r} -> {oid, r}
          {oid, r} -> {oid, r}
         end %>
      <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
      <%= if option do %>
        <div class="flex justify-between items-center text-sm py-1">
          <span class="text-gray-700 dark:text-gray-300">
            <%= option.title %>
          </span>
          <span class="font-medium text-blue-600 dark:text-blue-400">
            #<%= rank %>
          </span>
        </div>
      <% end %>
    <% end %>
    """
  end

  defp render_star_vote_summary(assigns, votes) do
    assigns = assign(assigns, :votes, votes)

    ~H"""
    <%= for {option_id, stars} <- @votes do %>
      <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
      <%= if option do %>
        <div class="flex justify-between items-center text-sm py-1">
          <span class="text-gray-700 dark:text-gray-300">
            <%= option.title %>
          </span>
          <span class="font-medium text-yellow-600 dark:text-yellow-400">
            <%= String.duplicate("⭐", stars) %>
          </span>
        </div>
      <% end %>
    <% end %>
    """
  end

  # Helper functions for vote display

  defp get_date_vote_color(vote_type) do
    case vote_type do
      :yes -> "text-green-600 dark:text-green-400"
      :if_need_be -> "text-yellow-600 dark:text-yellow-400"
      :no -> "text-red-600 dark:text-red-400"
    end
  end

  defp get_date_vote_display(vote_type) do
    case vote_type do
      :yes -> "👍 Yes"
      :if_need_be -> "🤷 If needed"
      :no -> "👎 No"
    end
  end

  defp get_binary_vote_color(vote_value) do
    case vote_value do
      "yes" -> "text-green-600 dark:text-green-400"
      "no" -> "text-red-600 dark:text-red-400"
      "maybe" -> "text-yellow-600 dark:text-yellow-400"
    end
  end

  defp get_binary_vote_display(vote_value) do
    case vote_value do
      "yes" -> "👍 Yes"
      "no" -> "👎 No"
      "maybe" -> "🤷 Maybe"
    end
  end

  defp format_vote_value(vote_value) when is_binary(vote_value), do: vote_value
  defp format_vote_value(vote_value) when is_atom(vote_value), do: Atom.to_string(vote_value)
  defp format_vote_value(vote_value), do: inspect(vote_value)
end
