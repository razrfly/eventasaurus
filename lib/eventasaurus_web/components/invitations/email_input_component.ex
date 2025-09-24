defmodule EventasaurusWeb.Components.Invitations.EmailInputComponent do
  @moduledoc """
  Component for inputting email addresses with validation and bulk support.
  Handles both single email input and comma-separated lists.
  """
  use EventasaurusWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:email_input, "")
     |> assign(:error, nil)
     |> assign(:selected_emails, MapSet.new())}
  end

  @impl true
  def update(assigns, socket) do
    selected_emails =
      case assigns[:selected_emails] do
        nil -> MapSet.new()
        emails -> MapSet.new(emails)
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_emails, selected_emails)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="email-input-component">
      <div class="mb-4">
        <label for={@id <> "_email_input"} class="block text-sm font-medium text-gray-700 mb-2">
          Email addresses
        </label>
        <p class="text-sm text-gray-500 mb-2">
          Enter email addresses separated by commas
        </p>
        <div class="flex gap-2">
          <textarea
            id={@id <> "_email_input"}
            name="emails"
            rows="3"
            value={@email_input}
            phx-target={@myself}
            phx-change="update_email_input"
            placeholder="friend1@example.com, friend2@example.com"
            class={[
              "flex-1 px-3 py-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-green-500",
              @error && "border-red-300"
            ]}
          />
          <button
            type="button"
            phx-target={@myself}
            phx-click="add_emails"
            phx-value-emails={@email_input}
            class="px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-green-500"
          >
            Add
          </button>
        </div>
        <%= if @error do %>
          <p class="mt-2 text-sm text-red-600">
            <%= @error %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("update_email_input", %{"emails" => emails}, socket) do
    {:noreply, assign(socket, :email_input, emails)}
  end

  @impl true
  def handle_event("add_emails", %{"emails" => emails_input}, socket) do
    emails_input = String.trim(emails_input)

    if emails_input == "" do
      {:noreply, assign(socket, :error, "Please enter at least one email address")}
    else
      case parse_and_validate_emails(emails_input, socket.assigns.selected_emails) do
        {:ok, new_emails} ->
          # Send the emails to parent
          Enum.each(new_emails, fn email ->
            send(self(), {:email_added, email})
          end)

          {:noreply,
           socket
           |> assign(:email_input, "")
           |> assign(:error, nil)}

        {:error, error} ->
          {:noreply, assign(socket, :error, error)}
      end
    end
  end

  # Helper functions

  defp parse_and_validate_emails(input, existing_emails) do
    emails =
      input
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.downcase/1)
      |> Enum.filter(&(&1 != ""))
      |> Enum.uniq()

    # Validate each email
    invalid_emails =
      emails
      |> Enum.reject(&valid_email?/1)

    cond do
      length(invalid_emails) > 0 ->
        {:error, "Invalid email format: #{Enum.join(invalid_emails, ", ")}"}

      true ->
        # Filter out existing emails
        new_emails = Enum.reject(emails, &MapSet.member?(existing_emails, &1))

        if length(new_emails) == 0 do
          {:error, "All emails have already been added"}
        else
          {:ok, new_emails}
        end
    end
  end

  defp valid_email?(email) do
    # Basic email validation
    email =~ ~r/^[^\s]+@[^\s]+\.[^\s]+$/
  end
end