defmodule EventasaurusWeb.Live.Components.VenueReviewsComponent do
  @moduledoc """
  Reviews section component for venue/restaurant/activity display.

  Shows user reviews and ratings from Google Places API.
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:compact, fn -> false end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="venue-reviews-component">
      <%= if @has_reviews do %>
        <div class="bg-white rounded-lg shadow-sm border">
        <div class="p-6">
          <%= if not @compact do %>
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Reviews</h3>
          <% end %>

          <!-- Overall Rating Summary -->
          <%= if @overall_rating && @overall_rating > 0 do %>
            <div class="mb-6 p-4 bg-gray-50 rounded-lg">
              <div class="flex items-center gap-4">
                <div class="text-center">
                  <div class="text-3xl font-bold text-gray-900"><%= format_rating(@overall_rating) %></div>
                  <div class="flex items-center justify-center gap-0.5 mt-1">
                    <%= for star <- 1..5 do %>
                      <.icon
                        name="hero-star-solid"
                        class={"h-4 w-4 #{if star <= @overall_rating, do: "text-yellow-400", else: "text-gray-300"}"}
                      />
                    <% end %>
                  </div>
                </div>
                <%= if @total_ratings && @total_ratings > 0 do %>
                  <div class="text-sm text-gray-600">
                    Based on <%= format_ratings_count(@total_ratings) %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <!-- Individual Reviews -->
          <div class="space-y-4">
            <%= for review <- @reviews do %>
              <.review_card review={review} compact={@compact} />
            <% end %>
          </div>

          <%= if length(@reviews) == 0 && @overall_rating do %>
            <div class="text-center py-8 text-gray-500">
              <.icon name="hero-star" class="h-8 w-8 mx-auto mb-2" />
              <p class="text-sm">No detailed reviews available</p>
              <p class="text-xs">But this place has a <%= format_rating(@overall_rating) %>-star rating!</p>
            </div>
          <% end %>
        </div>
      </div>
      <% end %>
    </div>
    """
  end

  # Private function components

  defp review_card(assigns) do
    ~H"""
    <div class="border-b border-gray-200 last:border-b-0 pb-4 last:pb-0">
      <div class="flex items-start gap-3">
        <!-- Avatar placeholder -->
        <div class="w-8 h-8 bg-gray-300 rounded-full flex items-center justify-center flex-shrink-0">
          <.icon name="hero-user" class="h-4 w-4 text-gray-600" />
        </div>

        <div class="flex-1 min-w-0">
          <!-- Review header -->
          <div class="flex items-start justify-between">
            <div class="flex-1">
              <div class="flex items-center gap-2">
                <p class="font-medium text-gray-900 text-sm"><%= @review.author_name || "Anonymous" %></p>
                <%= if @review.rating do %>
                  <div class="flex items-center gap-0.5">
                    <%= for star <- 1..5 do %>
                      <.icon
                        name="hero-star-solid"
                        class={"h-3 w-3 #{if star <= @review.rating, do: "text-yellow-400", else: "text-gray-300"}"}
                      />
                    <% end %>
                  </div>
                <% end %>
              </div>
              <%= if @review.time do %>
                <p class="text-xs text-gray-500 mt-0.5">
                  <%= format_review_time(@review.time) %>
                </p>
              <% end %>
            </div>
          </div>

          <!-- Review text -->
          <%= if @review.text && String.trim(@review.text) != "" do %>
            <div class="mt-2">
              <p class={[
                "text-gray-700",
                @compact && "text-xs" || "text-sm",
                "leading-relaxed"
              ]}>
                <%= format_review_text(@review.text) %>
              </p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Private functions

  defp assign_computed_data(socket) do
    rich_data = socket.assigns.rich_data

    # Support both standardized format (new) and old format (for backward compatibility)

    # Extract overall rating from standardized format or fallback to old format
    overall_rating =
      case rich_data do
        %{rating: %{value: value}} -> value
        %{sections: %{reviews: %{overall_rating: rating}}} -> rating
        %{"metadata" => %{"rating" => rating}} -> rating
        _ -> nil
      end

    # Extract total ratings from standardized format or fallback to old format
    total_ratings =
      case rich_data do
        %{rating: %{count: count}} -> count
        %{sections: %{reviews: %{total_ratings: total}}} -> total
        %{"metadata" => %{"user_ratings_total" => total}} -> total
        _ -> nil
      end

    # Extract reviews from standardized format or fallback to old format
    reviews =
      case rich_data do
        %{sections: %{reviews: %{reviews: reviews}}} when is_list(reviews) -> reviews
        %{"additional_data" => %{"reviews" => reviews}} when is_list(reviews) -> reviews
        _ -> []
      end

    socket
    |> assign(:overall_rating, overall_rating)
    |> assign(:total_ratings, total_ratings)
    |> assign(:reviews, normalize_reviews(reviews))
    |> assign(:has_reviews, has_reviews?(reviews, overall_rating))
  end

  defp has_reviews?(reviews, overall_rating) do
    (is_list(reviews) && length(reviews) > 0) || (is_number(overall_rating) && overall_rating > 0)
  end

  defp normalize_reviews(reviews) when is_list(reviews) do
    reviews
    # Limit to 5 reviews for display
    |> Enum.take(5)
    |> Enum.map(&normalize_review/1)
  end

  defp normalize_reviews(_), do: []

  defp normalize_review(review) when is_map(review) do
    %{
      author_name: Map.get(review, "author_name"),
      rating: Map.get(review, "rating"),
      text: Map.get(review, "text"),
      time: Map.get(review, "time")
    }
  end

  defp normalize_review(_), do: %{}

  defp format_rating(rating) when is_number(rating) do
    :erlang.float_to_binary(rating, decimals: 1)
  end

  defp format_rating(_), do: "N/A"

  defp format_ratings_count(count) when is_integer(count) do
    cond do
      count >= 1000 -> "#{div(count, 1000)}k+ reviews"
      count > 1 -> "#{count} reviews"
      count == 1 -> "1 review"
      true -> "No reviews"
    end
  end

  defp format_ratings_count(_), do: "No reviews"

  defp format_review_time(time) when is_integer(time) do
    # Google Places API returns Unix timestamp
    datetime = DateTime.from_unix!(time)
    now = DateTime.utc_now()

    case DateTime.diff(now, datetime, :day) do
      0 -> "Today"
      1 -> "Yesterday"
      days when days < 7 -> "#{days} days ago"
      days when days < 30 -> "#{div(days, 7)} weeks ago"
      days when days < 365 -> "#{div(days, 30)} months ago"
      days -> "#{div(days, 365)} years ago"
    end
  rescue
    _ -> "Recently"
  end

  defp format_review_time(_), do: ""

  defp format_review_text(text) when is_binary(text) do
    text
    |> String.trim()
    # Limit review text length
    |> truncate_text(200)
  end

  defp format_review_text(_), do: ""

  defp truncate_text(text, max_length) do
    Eventasaurus.Utils.Text.truncate_text(text, max_length)
  end
end
