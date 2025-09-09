defmodule EventasaurusWeb.PresentedByComponent do
  @moduledoc """
  Component that displays "Presented by" information when an event belongs to a group.
  Shows group icon, name, and provides a clickable link to the group page.
  """

  use EventasaurusWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@group} class="bg-white border border-gray-200 rounded-xl p-4 shadow-sm mb-6">
        <div class="flex items-center justify-between">
          <span class="text-xs text-gray-500 font-medium uppercase tracking-wide">Presented by</span>
        </div>
        
        <.link 
          navigate={~p"/groups/#{@group.slug}"} 
          class="flex items-center space-x-3 mt-2 hover:bg-gray-50 p-2 rounded-lg transition-colors group"
        >
          <div class="flex-shrink-0">
            <img 
              :if={@group.avatar_url}
              src={@group.avatar_url} 
              alt={"#{@group.name} avatar"}
              class="w-8 h-8 rounded-full object-cover border border-gray-200"
            />
            <div 
              :if={!@group.avatar_url}
              class="w-8 h-8 rounded-full bg-gradient-to-br from-purple-400 to-pink-400 flex items-center justify-center text-white text-sm font-semibold"
            >
              <%= String.first(@group.name) |> String.upcase() %>
            </div>
          </div>
          
          <div class="flex-1">
            <span class="text-sm font-semibold text-gray-900 group-hover:text-blue-600 transition-colors">
              <%= @group.name %>
            </span>
          </div>
          
          <svg class="w-4 h-4 text-gray-400 group-hover:text-blue-600 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
        </.link>
      </div>
    </div>
    """
  end
end
