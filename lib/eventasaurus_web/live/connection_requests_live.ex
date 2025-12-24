defmodule EventasaurusWeb.ConnectionRequestsLive do
  @moduledoc """
  LiveView for managing introductions.

  This page shows:
  - Pending introductions the user has received
  - Sent introductions awaiting response
  """

  use EventasaurusWeb, :live_view

  import EventasaurusWeb.Helpers.AvatarHelper

  alias EventasaurusApp.Relationships

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.user

    {:ok,
     socket
     |> assign(:page_title, "Introductions")
     |> assign(:active_tab, :received)
     |> load_requests(user)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = case params["tab"] do
      "sent" -> :sent
      _ -> :received
    end

    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> load_requests(socket.assigns.user)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/people/introductions?tab=#{tab}")}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    user = socket.assigns.user

    with request when not is_nil(request) <- Relationships.get_pending_request_by_id(id),
         true <- request.related_user_id == user.id,
         context <- generate_approval_context(request),
         {:ok, _relationship} <- Relationships.approve_connection_request(request, user, context) do
      {:noreply,
       socket
       |> put_flash(:info, "Introduction accepted!")
       |> load_requests(user)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not approve request")}
    end
  end

  @impl true
  def handle_event("deny", %{"id" => id}, socket) do
    user = socket.assigns.user

    with request when not is_nil(request) <- Relationships.get_pending_request_by_id(id),
         true <- request.related_user_id == user.id,
         {:ok, _relationship} <- Relationships.deny_connection_request(request, user) do
      {:noreply,
       socket
       |> put_flash(:info, "Introduction declined")
       |> load_requests(user)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not decline request")}
    end
  end

  @impl true
  def handle_event("cancel", %{"id" => id}, socket) do
    user = socket.assigns.user

    with request when not is_nil(request) <- Relationships.get_pending_request_by_id(id),
         true <- request.user_id == user.id,
         {:ok, _count} <- Relationships.cancel_connection_request(request, user) do
      {:noreply,
       socket
       |> put_flash(:info, "Introduction cancelled")
       |> load_requests(user)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not cancel request")}
    end
  end

  defp load_requests(socket, user) do
    received_requests = Relationships.list_pending_requests_for_user(user, preload: [:user, :originated_from_event])
    sent_requests = Relationships.list_sent_requests(user)
    received_count = length(received_requests)
    sent_count = length(sent_requests)

    socket
    |> assign(:received_requests, received_requests)
    |> assign(:sent_requests, sent_requests)
    |> assign(:received_count, received_count)
    |> assign(:sent_count, sent_count)
  end

  defp generate_approval_context(request) do
    if request.originated_from_event do
      event = request.originated_from_event
      date = case event.start_at do
        %DateTime{} = dt -> Calendar.strftime(dt, "%B %Y")
        %NaiveDateTime{} = ndt -> Calendar.strftime(ndt, "%B %Y")
        _ -> ""
      end

      if date != "" do
        "Met at #{event.title} - #{date}"
      else
        "Met at #{event.title}"
      end
    else
      "Connected on Eventasaurus"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <!-- Header (matching Discover page layout) -->
      <header class="mb-6">
        <h1 class="text-3xl font-bold text-gray-900">People</h1>
        <p class="mt-2 text-gray-600">
          People who want to stay in touch with you.
        </p>
      </header>

      <!-- Section Navigation -->
      <nav class="mb-6 flex gap-4 border-b border-gray-200 pb-4">
        <.link
          navigate={~p"/people/discover"}
          class="inline-flex items-center gap-2 px-4 py-2 rounded-lg font-medium text-sm text-gray-600 hover:bg-gray-100"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          Discover
        </.link>
        <.link
          navigate={~p"/people/introductions"}
          class="inline-flex items-center gap-2 px-4 py-2 rounded-lg font-medium text-sm bg-indigo-100 text-indigo-700"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
          </svg>
          Introductions
        </.link>
      </nav>

      <!-- Tabs (matching Discover page style with indigo colors) -->
      <nav class="mb-6 border-b border-gray-200">
        <div class="flex space-x-8">
          <button
            phx-click="switch_tab"
            phx-value-tab="received"
            class={[
              "flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm transition-colors",
              if(@active_tab == :received,
                do: "border-indigo-600 text-indigo-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
            </svg>
            Received
            <%= if @received_count > 0 do %>
              <span class="ml-1 bg-indigo-100 text-indigo-600 py-0.5 px-2 rounded-full text-xs font-medium">
                {@received_count}
              </span>
            <% end %>
          </button>

          <button
            phx-click="switch_tab"
            phx-value-tab="sent"
            class={[
              "flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm transition-colors",
              if(@active_tab == :sent,
                do: "border-indigo-600 text-indigo-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
            </svg>
            Sent
            <%= if @sent_count > 0 do %>
              <span class="ml-1 bg-indigo-100 text-indigo-600 py-0.5 px-2 rounded-full text-xs font-medium">
                {@sent_count}
              </span>
            <% end %>
          </button>
        </div>
      </nav>

      <!-- Request Lists -->
      <%= if @active_tab == :received do %>
        <.received_requests_list requests={@received_requests} />
      <% else %>
        <.sent_requests_list requests={@sent_requests} />
      <% end %>
    </div>
    """
  end

  defp received_requests_list(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= if Enum.empty?(@requests) do %>
        <div class="text-center py-12 bg-gray-50 rounded-lg">
          <Heroicons.user_plus class="h-12 w-12 text-gray-400 mx-auto" />
          <h3 class="mt-4 text-lg font-medium text-gray-900">No pending introductions</h3>
          <p class="mt-2 text-gray-500">
            When someone wants to stay in touch, it will appear here.
          </p>
        </div>
      <% else %>
        <%= for request <- @requests do %>
          <div class="bg-white border border-gray-200 rounded-lg p-4 flex items-center justify-between">
            <div class="flex items-center space-x-4">
              <%= avatar_img_size(request.user, :md, class: "rounded-full object-cover") %>
              <div>
                <h4 class="font-medium text-gray-900">
                  {request.user.name || request.user.email}
                </h4>
                <%= if request.request_message do %>
                  <p class="text-sm text-gray-500 mt-1 italic">
                    "{request.request_message}"
                  </p>
                <% end %>
                <%= if request.originated_from_event do %>
                  <p class="text-sm text-gray-500 mt-1">
                    From event: {request.originated_from_event.title}
                  </p>
                <% end %>
                <p class="text-xs text-gray-400 mt-1">
                  Requested {format_relative_time(request.inserted_at)}
                </p>
              </div>
            </div>
            <div class="flex items-center space-x-2">
              <button
                phx-click="approve"
                phx-value-id={request.id}
                class="px-4 py-2 bg-teal-600 text-white text-sm font-medium rounded-lg hover:bg-teal-700 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2"
              >
                Accept
              </button>
              <button
                phx-click="deny"
                phx-value-id={request.id}
                class="px-4 py-2 bg-gray-100 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2"
              >
                Decline
              </button>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp sent_requests_list(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= if Enum.empty?(@requests) do %>
        <div class="text-center py-12 bg-gray-50 rounded-lg">
          <Heroicons.clock class="h-12 w-12 text-gray-400 mx-auto" />
          <h3 class="mt-4 text-lg font-medium text-gray-900">No sent introductions</h3>
          <p class="mt-2 text-gray-500">
            Introductions you've sent will appear here.
          </p>
        </div>
      <% else %>
        <%= for request <- @requests do %>
          <div class="bg-white border border-gray-200 rounded-lg p-4 flex items-center justify-between">
            <div class="flex items-center space-x-4">
              <%= avatar_img_size(request.related_user, :md, class: "rounded-full object-cover") %>
              <div>
                <h4 class="font-medium text-gray-900">
                  {request.related_user.name || request.related_user.email}
                </h4>
                <div class="flex items-center mt-1">
                  <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-amber-100 text-amber-800">
                    <Heroicons.clock class="h-3 w-3 mr-1" />
                    Pending
                  </span>
                </div>
                <p class="text-xs text-gray-400 mt-1">
                  Sent {format_relative_time(request.inserted_at)}
                </p>
              </div>
            </div>
            <div>
              <button
                phx-click="cancel"
                phx-value-id={request.id}
                class="px-4 py-2 bg-gray-100 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2"
              >
                Cancel
              </button>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()

    # Convert NaiveDateTime to DateTime if needed
    datetime_utc =
      case datetime do
        %DateTime{} -> datetime
        %NaiveDateTime{} -> DateTime.from_naive!(datetime, "Etc/UTC")
      end

    diff = DateTime.diff(now, datetime_utc, :second)

    cond do
      diff < 60 ->
        "just now"

      diff < 3600 ->
        minutes = div(diff, 60)
        if minutes == 1, do: "1 minute ago", else: "#{minutes} minutes ago"

      diff < 86400 ->
        hours = div(diff, 3600)
        if hours == 1, do: "1 hour ago", else: "#{hours} hours ago"

      diff < 604800 ->
        days = div(diff, 86400)
        if days == 1, do: "1 day ago", else: "#{days} days ago"

      true ->
        Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
