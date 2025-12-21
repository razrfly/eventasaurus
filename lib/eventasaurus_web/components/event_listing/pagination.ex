defmodule EventasaurusWeb.Components.EventListing.Pagination do
  @moduledoc """
  Pagination component for event listings.

  Renders page navigation with previous/next buttons and page numbers.
  Emits `paginate` event with `page` value to parent LiveView.

  ## Example

      <.pagination pagination={@pagination} />
  """

  use Phoenix.Component

  alias EventasaurusDiscovery.Pagination, as: PaginationStruct

  @doc """
  Renders pagination controls.

  ## Attributes

  - `pagination` - Pagination struct with page_number, total_pages, etc.

  ## Events Emitted

  - `paginate` with `page` value - when page button is clicked
  """
  attr :pagination, :any, required: true

  def pagination(assigns) do
    # Don't render pagination when there's only one page or less
    if assigns.pagination.total_pages <= 1 do
      ~H""
    else
      ~H"""
    <nav class="flex justify-center mt-8">
      <div class="flex items-center space-x-2">
        <!-- Previous -->
        <button
          :if={@pagination.page_number > 1}
          phx-click="paginate"
          phx-value-page={@pagination.page_number - 1}
          class="px-3 py-2 border border-gray-300 rounded-md hover:bg-gray-50"
        >
          Previous
        </button>

        <!-- Page Numbers -->
        <div class="flex space-x-1">
          <%= for page <- page_links(@pagination) do %>
            <%= if page == :ellipsis do %>
              <span class="px-3 py-2">...</span>
            <% else %>
              <button
                phx-click="paginate"
                phx-value-page={page}
                class={[
                  "px-3 py-2 rounded-md",
                  if(page == @pagination.page_number,
                    do: "bg-blue-600 text-white",
                    else: "border border-gray-300 hover:bg-gray-50"
                  )
                ]}
              >
                <%= page %>
              </button>
            <% end %>
          <% end %>
        </div>

        <!-- Next -->
        <button
          :if={@pagination.page_number < @pagination.total_pages}
          phx-click="paginate"
          phx-value-page={@pagination.page_number + 1}
          class="px-3 py-2 border border-gray-300 rounded-md hover:bg-gray-50"
        >
          Next
        </button>
      </div>
    </nav>
    """
    end
  end

  # Generate page links with ellipsis for large page counts
  # Delegates to the Pagination module if available, otherwise provides fallback
  defp page_links(pagination) do
    if function_exported?(PaginationStruct, :page_links, 1) do
      PaginationStruct.page_links(pagination)
    else
      # Fallback implementation
      generate_page_links(pagination.page_number, pagination.total_pages)
    end
  end

  defp generate_page_links(_current, total) when total <= 7 do
    Enum.to_list(1..total)
  end

  defp generate_page_links(current, total) do
    cond do
      current <= 4 ->
        Enum.to_list(1..5) ++ [:ellipsis, total]

      current >= total - 3 ->
        [1, :ellipsis] ++ Enum.to_list((total - 4)..total)

      true ->
        [1, :ellipsis] ++ Enum.to_list((current - 1)..(current + 1)) ++ [:ellipsis, total]
    end
  end
end
