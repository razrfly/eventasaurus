defmodule EventasaurusWeb.EmailStatusComponents do
  @moduledoc """
  UI components for displaying email status information.
  """

  use Phoenix.Component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusApp.Events.EventParticipant

  @doc """
  Renders an email status badge with appropriate styling.
  """
  attr :status, :string, required: true
  attr :class, :string, default: ""

  def email_status_badge(assigns) do
    ~H"""
    <span class={["inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", badge_classes(@status), @class]}>
      <.email_status_icon status={@status} />
      <span class="ml-1"><%=
        case @status do
          "not_sent" -> "Not Sent"
          "sending" -> "Sending"
          "sent" -> "Sent"
          "delivered" -> "Delivered"
          "failed" -> "Failed"
          "bounced" -> "Bounced"
          "retrying" -> "Retrying"
          _ -> "Unknown"
        end
      %></span>
    </span>
    """
  end

  @doc """
  Renders an icon for the email status.
  """
  attr :status, :string, required: true
  attr :class, :string, default: "w-3 h-3"

  def email_status_icon(assigns) do
    ~H"""
    <.icon :if={@status == "not_sent"} name="hero-envelope" class={@class} />
    <.icon :if={@status == "sending"} name="hero-arrow-up" class={@class} />
    <.icon :if={@status == "sent"} name="hero-check" class={@class} />
    <.icon :if={@status == "delivered"} name="hero-check-circle" class={@class} />
    <.icon :if={@status == "failed"} name="hero-x-circle" class={@class} />
    <.icon :if={@status == "bounced"} name="hero-exclamation-triangle" class={@class} />
    <.icon :if={@status == "retrying"} name="hero-arrow-path" class={@class} />
    <.icon :if={@status not in ["not_sent", "sending", "sent", "delivered", "failed", "bounced", "retrying"]} name="hero-question-mark-circle" class={@class} />
    """
  end

  @doc """
  Renders a comprehensive email status display with details.
  """
  attr :participant, :map, required: true
  attr :show_retry_button, :boolean, default: false
  attr :retry_action, :string, default: nil

  def email_status_detail(assigns) do
    email_status = EventParticipant.get_email_status(assigns.participant)
    assigns = assign(assigns, :email_status, email_status)

    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center space-x-3">
          <div class="flex-shrink-0">
            <div class="w-10 h-10 bg-gray-100 rounded-full flex items-center justify-center">
              <.email_status_icon status={@email_status.status} class="w-5 h-5" />
            </div>
          </div>
          <div>
            <h3 class="text-sm font-medium text-gray-900"><%=
              case @participant do
                %{user: %{name: name}} when not is_nil(name) -> name
                %{user: %{email: email}} -> email
                %{name: name} when not is_nil(name) -> name
                %{email: email} -> email
                _ -> "Unknown"
              end
            %></h3>
            <p class="text-sm text-gray-500"><%=
              case @participant do
                %{user: %{email: email}} -> email
                %{email: email} -> email
                _ -> "No email"
              end
            %></p>
          </div>
        </div>
        <.email_status_badge status={@email_status.status} />
      </div>

      <div class="space-y-2">
        <div :if={@email_status.attempts > 0} class="text-sm text-gray-600">
          <span class="font-medium">Attempts:</span> <%= @email_status.attempts %>
        </div>

        <div :if={@email_status.last_sent_at} class="text-sm text-gray-600">
          <span class="font-medium">Last sent:</span>
          <time datetime={@email_status.last_sent_at}>
            <%= @email_status.last_sent_at %>
          </time>
        </div>

        <div :if={@email_status.last_error} class="text-sm text-red-600">
          <span class="font-medium">Error:</span> <%= @email_status.last_error %>
        </div>

        <div :if={@email_status.delivery_id} class="text-sm text-gray-600">
          <span class="font-medium">Delivery ID:</span>
          <code class="text-xs bg-gray-100 px-1 py-0.5 rounded"><%= @email_status.delivery_id %></code>
        </div>
      </div>

      <div :if={@show_retry_button and @email_status.status in ["failed", "bounced"]} class="mt-4">
        <.button
          :if={@retry_action}
          phx-click={@retry_action}
          phx-value-participant-id={@participant.id}
          class="w-full text-sm"
        >
          <.icon name="hero-arrow-path" class="w-4 h-4 mr-2" />
          Retry Email
        </.button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a summary of email delivery statistics.
  """
  attr :stats, :map, required: true
  attr :class, :string, default: ""

  def email_delivery_stats(assigns) do
    ~H"""
    <div class={["bg-white rounded-lg shadow-sm border border-gray-200 p-6", @class]}>
      <h3 class="text-lg font-medium text-gray-900 mb-4">Email Delivery Status</h3>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div class="text-center">
          <div class="text-2xl font-bold text-gray-900"><%= @stats.total_participants %></div>
          <div class="text-sm text-gray-500">Total Participants</div>
        </div>

        <div class="text-center">
          <div class="text-2xl font-bold text-green-600"><%= Map.get(@stats, "delivered", 0) %></div>
          <div class="text-sm text-gray-500">Delivered</div>
        </div>

        <div class="text-center">
          <div class="text-2xl font-bold text-blue-600"><%= Map.get(@stats, "sent", 0) %></div>
          <div class="text-sm text-gray-500">Sent</div>
        </div>

        <div class="text-center">
          <div class="text-2xl font-bold text-red-600"><%= Map.get(@stats, "failed", 0) + Map.get(@stats, "bounced", 0) %></div>
          <div class="text-sm text-gray-500">Failed</div>
        </div>
      </div>

      <div class="mt-6">
        <div class="text-sm text-gray-600 mb-2">Delivery Progress</div>
        <div class="w-full bg-gray-200 rounded-full h-2">
          <div
            class="bg-green-500 h-2 rounded-full transition-all duration-300"
            style={"width: #{delivery_percentage(@stats)}%"}
          ></div>
        </div>
        <div class="text-xs text-gray-500 mt-1">
          <%= delivery_percentage(@stats) %>% delivered
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a filterable list of participants with email status.
  """
  attr :participants, :list, required: true
  attr :current_filter, :string, default: "all"
  attr :filter_change_action, :string, default: nil
  attr :retry_action, :string, default: nil
  attr :class, :string, default: ""

  def participant_email_list(assigns) do
    ~H"""
    <div class={["bg-white rounded-lg shadow-sm border border-gray-200", @class]}>
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-medium text-gray-900">Participants</h3>
          <div class="flex items-center space-x-2">
            <select
              :if={@filter_change_action}
              phx-change={@filter_change_action}
              name="email_status_filter"
              class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
            >
              <option value="all" selected={@current_filter == "all"}>All Participants</option>
              <option value="not_sent" selected={@current_filter == "not_sent"}>Not Sent</option>
              <option value="sending" selected={@current_filter == "sending"}>Sending</option>
              <option value="sent" selected={@current_filter == "sent"}>Sent</option>
              <option value="delivered" selected={@current_filter == "delivered"}>Delivered</option>
              <option value="failed" selected={@current_filter == "failed"}>Failed</option>
              <option value="bounced" selected={@current_filter == "bounced"}>Bounced</option>
            </select>
          </div>
        </div>
      </div>

      <div class="divide-y divide-gray-200">
        <div :for={participant <- @participants} class="px-6 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-3">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-gray-100 rounded-full flex items-center justify-center">
                  <.email_status_icon status={EventParticipant.get_email_status(participant).status} class="w-4 h-4" />
                </div>
              </div>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium text-gray-900 truncate">
                  {
                    case participant do
                      %{user: %{name: name}} when not is_nil(name) -> name
                      %{user: %{email: email}} -> email
                      %{name: name} when not is_nil(name) -> name
                      %{email: email} -> email
                      _ -> "Unknown"
                    end
                  }
                </p>
                <p class="text-sm text-gray-500 truncate">
                  {
                    case participant do
                      %{user: %{email: email}} -> email
                      %{email: email} -> email
                      _ -> "No email"
                    end
                  }
                </p>
              </div>
            </div>
            <div class="flex items-center space-x-2">
              <.email_status_badge status={EventParticipant.get_email_status(participant).status} />
              <.button
                :if={@retry_action and EventParticipant.get_email_status(participant).status in ["failed", "bounced"]}
                phx-click={@retry_action}
                phx-value-participant-id={participant.id}
                class="text-sm border border-gray-300 bg-white"
              >
                <.icon name="hero-arrow-path" class="w-4 h-4" />
              </.button>
            </div>
          </div>
        </div>

        <div :if={Enum.empty?(@participants)} class="px-6 py-12 text-center">
          <.icon name="hero-inbox" class="w-12 h-12 mx-auto text-gray-400" />
          <h3 class="mt-2 text-sm font-medium text-gray-900">No participants</h3>
          <p class="mt-1 text-sm text-gray-500">No participants match the current filter.</p>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp badge_classes(status) do
    case status do
      "not_sent" -> "bg-gray-100 text-gray-800"
      "sending" -> "bg-blue-100 text-blue-800"
      "sent" -> "bg-indigo-100 text-indigo-800"
      "delivered" -> "bg-green-100 text-green-800"
      "failed" -> "bg-red-100 text-red-800"
      "bounced" -> "bg-orange-100 text-orange-800"
      "retrying" -> "bg-yellow-100 text-yellow-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp delivery_percentage(stats) do
    total = stats.total_participants
    delivered = Map.get(stats, "delivered", 0)

    if total > 0 do
      round(delivered / total * 100)
    else
      0
    end
  end


end
