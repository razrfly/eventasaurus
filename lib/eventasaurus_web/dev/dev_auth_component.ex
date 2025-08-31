defmodule EventasaurusWeb.Dev.DevAuthComponent do
  @moduledoc """
  Development-only component for quick user login.
  This component is only rendered in development mode.
  """
  use Phoenix.Component
  alias EventasaurusWeb.Dev.DevAuth

  @doc """
  Renders the development quick login section.
  Only renders in development mode.
  """
  attr :users, :list, default: []
  
  def quick_login_section(assigns) do
    if DevAuth.enabled?() do
      ~H"""
      <div class="mt-6">
        <div class="border-t border-gray-200 pt-6">
          <p class="text-xs text-amber-600 font-medium mb-3">🚧 DEVELOPMENT MODE</p>
          
          <form action="/dev/quick-login" method="post" class="space-y-3">
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            
            <select 
              name="user_id" 
              class="block w-full rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-amber-500 focus:ring-offset-2"
              required
              onchange="this.form.submit()"
            >
              <option value="" disabled selected>Quick login as test user...</option>
              <%= for {user, label} <- @users do %>
                <option value={user.id}>
                  <%= label %> - <%= user.email %>
                </option>
              <% end %>
            </select>
            
            <noscript>
              <button 
                type="submit" 
                class="flex w-full justify-center items-center rounded-md border border-amber-300 bg-amber-50 px-4 py-2 text-sm font-medium text-amber-700 shadow-sm hover:bg-amber-100 focus:outline-none focus:ring-2 focus:ring-amber-500 focus:ring-offset-2"
              >
                Quick Login →
              </button>
            </noscript>
          </form>
          
          <p class="mt-3 text-xs text-gray-500">
            This feature is only visible in development mode.
          </p>
        </div>
      </div>
      """
    else
      ~H"""
      <!-- Dev quick login disabled -->
      """
    end
  end
end