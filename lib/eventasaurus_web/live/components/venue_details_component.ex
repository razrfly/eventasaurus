defmodule EventasaurusWeb.Live.Components.VenueDetailsComponent do
  @moduledoc """
  Details section component for venue/restaurant/activity display.

  Shows contact information, opening hours, pricing, website links,
  and other detailed information from Google Places API.
  """

  use EventasaurusWeb, :live_component

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
    <section class="bg-white dark:bg-gray-800 p-6 rounded-lg shadow-lg" role="complementary" aria-labelledby="venue-details-title">
      <h3 id="venue-details-title" class="text-xl font-semibold text-gray-900 dark:text-white mb-4">
        Details
      </h3>

      <!-- Contact Information -->
      <div class="space-y-4" role="group" aria-labelledby="contact-info">
        <h4 id="contact-info" class="sr-only">Contact Information</h4>

        <%= if @address do %>
          <div class="flex items-start gap-3" role="group" aria-labelledby="address-label">
            <svg class="w-5 h-5 text-gray-400 mt-0.5 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
              <path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"/>
            </svg>
            <div>
              <span id="address-label" class="text-sm font-medium text-gray-500 dark:text-gray-400">Address</span>
              <address class="mt-1 text-gray-900 dark:text-white not-italic" aria-describedby="address-label">
                <%= @address %>
              </address>
            </div>
          </div>
        <% end %>

        <%= if @phone do %>
          <div class="flex items-start gap-3" role="group" aria-labelledby="phone-label">
            <svg class="w-5 h-5 text-gray-400 mt-0.5 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
              <path d="M2 3a1 1 0 011-1h2.153a1 1 0 01.986.836l.74 4.435a1 1 0 01-.54 1.06l-1.548.773a11.037 11.037 0 006.105 6.105l.774-1.548a1 1 0 011.059-.54l4.435.74a1 1 0 01.836.986V17a1 1 0 01-1 1h-2C7.82 18 2 12.18 2 5V3z"/>
            </svg>
            <div>
              <span id="phone-label" class="text-sm font-medium text-gray-500 dark:text-gray-400">Phone</span>
              <a
                href={"tel:#{@phone}"}
                class="mt-1 text-blue-600 dark:text-blue-400 hover:underline block"
                aria-describedby="phone-label"
                role="link"
              >
                <%= @phone %>
              </a>
            </div>
          </div>
        <% end %>

        <%= if @website do %>
          <div class="flex items-start gap-3" role="group" aria-labelledby="website-label">
            <svg class="w-5 h-5 text-gray-400 mt-0.5 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
              <path fill-rule="evenodd" d="M4.083 9h1.946c.089-1.546.383-2.97.837-4.118A6.004 6.004 0 004.083 9zM10 2a8 8 0 100 16 8 8 0 000-16zm0 2c-.076 0-.232.032-.465.262-.238.234-.497.623-.737 1.182-.389.907-.673 2.142-.766 3.556h3.936c-.093-1.414-.377-2.649-.766-3.556-.24-.56-.5-.948-.737-1.182C10.232 4.032 10.076 4 10 4zm3.971 5c-.089-1.546-.383-2.97-.837-4.118A6.004 6.004 0 0115.917 9h-1.946zm-2.003 2H8.032c.093 1.414.377 2.649.766 3.556.24.56.5.948.737 1.182.233.23.389.262.465.262.076 0 .232-.032.465-.262.238-.234.498-.623.737-1.182.389-.907.673-2.142.766-3.556zm1.166 4.118c.454-1.147.748-2.572.837-4.118h1.946a6.004 6.004 0 01-2.783 4.118zm-6.268 0C6.412 13.97 6.118 12.546 6.03 11H4.083a6.004 6.004 0 002.783 4.118z" clip-rule="evenodd"/>
            </svg>
            <div>
              <span id="website-label" class="text-sm font-medium text-gray-500 dark:text-gray-400">Website</span>
              <a
                href={@website}
                target="_blank"
                rel="noopener noreferrer"
                class="mt-1 text-blue-600 dark:text-blue-400 hover:underline break-all block"
                aria-describedby="website-label"
                role="link"
              >
                <%= String.replace(@website, ~r/^https?:\/\//, "") %>
                <span class="sr-only">(opens in new tab)</span>
              </a>
            </div>
          </div>
        <% end %>

        <%= if @google_maps_url do %>
          <div class="flex items-start gap-3" role="group" aria-labelledby="maps-label">
            <svg class="w-5 h-5 text-gray-400 mt-0.5 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
              <path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"/>
            </svg>
            <div>
              <span id="maps-label" class="text-sm font-medium text-gray-500 dark:text-gray-400">Google Maps</span>
              <a
                href={@google_maps_url}
                target="_blank"
                rel="noopener noreferrer"
                class="mt-1 text-blue-600 dark:text-blue-400 hover:underline block"
                aria-describedby="maps-label"
                role="link"
              >
                View on Maps
                <span class="sr-only">(opens in new tab)</span>
              </a>
            </div>
          </div>
        <% end %>

        <!-- Rating Information -->
        <%= if @rating do %>
          <div class="flex items-start gap-3" role="group" aria-labelledby="rating-label">
            <svg class="w-5 h-5 text-yellow-400 mt-0.5 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
              <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z"/>
            </svg>
            <div>
              <span id="rating-label" class="text-sm font-medium text-gray-500 dark:text-gray-400">Rating</span>
              <div class="mt-1 flex items-center gap-2">
                <span class="text-gray-900 dark:text-white font-semibold" aria-describedby="rating-label">
                  <%= @rating %>
                </span>
                <%= if @user_ratings_total do %>
                  <span class="text-gray-500 text-sm" aria-label={"Based on #{format_ratings_count(@user_ratings_total)} reviews"}>
                    (<%= format_ratings_count(@user_ratings_total) %> reviews)
                  </span>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Price Level -->
        <%= if @price_level_description do %>
          <div class="flex items-start gap-3" role="group" aria-labelledby="price-label">
            <svg class="w-5 h-5 text-green-500 mt-0.5 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
              <path d="M8.433 7.418c.155-.103.346-.196.567-.267v1.698a2.305 2.305 0 01-.567-.267C8.07 8.34 8 8.114 8 8c0-.114.07-.34.433-.582zM11 12.849v-1.698c.22.071.412.164.567.267.364.243.433.468.433.582 0 .114-.07.34-.433.582a2.305 2.305 0 01-.567.267z"/>
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-13a1 1 0 10-2 0v.092a4.535 4.535 0 00-1.676.662C6.602 6.234 6 7.009 6 8c0 .99.602 1.765 1.324 2.246.48.32 1.054.545 1.676.662v1.941c-.391-.127-.68-.317-.843-.504a1 1 0 10-1.51 1.31c.562.649 1.413 1.076 2.353 1.253V15a1 1 0 102 0v-.092a4.535 4.535 0 001.676-.662C13.398 13.766 14 12.991 14 12c0-.99-.602-1.765-1.324-2.246A4.535 4.535 0 0011 9.092V7.151c.391.127.68.317.843.504a1 1 0 101.511-1.31c-.563-.649-1.413-1.076-2.354-1.253V5z" clip-rule="evenodd"/>
            </svg>
            <div>
              <span id="price-label" class="text-sm font-medium text-gray-500 dark:text-gray-400">Price Level</span>
              <span class="mt-1 text-gray-900 dark:text-white block" aria-describedby="price-label">
                <%= @price_level_description %>
              </span>
            </div>
          </div>
        <% end %>

        <!-- Business Hours -->
        <%= if @current_hours_status do %>
          <div class="flex items-start gap-3" role="group" aria-labelledby="hours-label">
            <svg class="w-5 h-5 text-gray-400 mt-0.5 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd"/>
            </svg>
            <div>
              <span id="hours-label" class="text-sm font-medium text-gray-500 dark:text-gray-400">Hours</span>
              <span class={[
                "mt-1 block font-medium",
                if(@current_hours_status == "Open", do: "text-green-600 dark:text-green-400", else: "text-red-600 dark:text-red-400")
              ]} aria-describedby="hours-label">
                <%= @current_hours_status %>
              </span>
            </div>
          </div>
        <% end %>

        <!-- Business Status -->
        <%= if @business_status && @business_status != "OPERATIONAL" do %>
          <div class="flex items-start gap-3" role="group" aria-labelledby="status-label">
            <svg class="w-5 h-5 text-amber-500 mt-0.5 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
              <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
            </svg>
            <div>
              <span id="status-label" class="text-sm font-medium text-gray-500 dark:text-gray-400">Status</span>
              <span class="mt-1 text-amber-600 dark:text-amber-400 block font-medium" aria-describedby="status-label">
                <%= format_business_status(@business_status) %>
              </span>
            </div>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  # Private functions

  defp assign_computed_data(socket) do
    rich_data = socket.assigns.rich_data

    # Support both standardized format (new) and old format (for backward compatibility)

    # Extract address from standardized format or fallback to old format
    address =
      case rich_data do
        %{sections: %{details: %{formatted_address: address}}} -> address
        %{"metadata" => %{"address" => address}} -> address
        _ -> nil
      end

    # Extract phone from standardized format or fallback to old format
    phone =
      case rich_data do
        %{sections: %{details: %{phone: phone}}} -> phone
        %{"metadata" => %{"formatted_phone_number" => phone}} -> phone
        _ -> nil
      end

    # Extract website from standardized format or fallback to old format
    website =
      case rich_data do
        %{external_urls: %{official: website}} -> website
        %{sections: %{details: %{website: website}}} -> website
        %{"external_urls" => %{"website" => website}} -> website
        _ -> nil
      end

    # Extract Google Maps URL from standardized format or fallback to old format
    google_maps_url =
      case rich_data do
        %{external_urls: %{maps: maps_url}} -> maps_url
        %{"external_urls" => %{"google_maps" => maps_url}} -> maps_url
        _ -> nil
      end

    # Extract rating from standardized format or fallback to old format
    rating =
      case rich_data do
        %{rating: %{value: value}} -> value
        %{"metadata" => %{"rating" => rating}} -> rating
        _ -> nil
      end

    # Extract user ratings total from standardized format or fallback to old format
    user_ratings_total =
      case rich_data do
        %{rating: %{count: count}} -> count
        %{"metadata" => %{"user_ratings_total" => total}} -> total
        _ -> nil
      end

    # Extract price level description from standardized format or fallback to old format
    price_level_description =
      case rich_data do
        %{sections: %{hero: %{price_level: level}}} when is_integer(level) ->
          format_price_level_description(level)

        %{"additional_data" => %{"price_level_description" => desc}} ->
          desc

        _ ->
          nil
      end

    # Extract business status from standardized format or fallback to old format
    business_status =
      case rich_data do
        %{status: "open"} -> "OPERATIONAL"
        %{status: "closed"} -> "CLOSED_TEMPORARILY"
        %{sections: %{hero: %{status: status}}} -> status
        %{"metadata" => %{"business_status" => status}} -> status
        _ -> nil
      end

    # Extract types from standardized format or fallback to old format
    types =
      case rich_data do
        %{categories: categories} when is_list(categories) -> categories
        %{"metadata" => %{"types" => types}} when is_list(types) -> types
        _ -> []
      end

    # Extract opening hours from standardized format or fallback to old format
    {is_open_now, opening_hours_text} =
      case rich_data do
        %{sections: %{details: %{opening_hours: %{"open_now" => open_now} = hours}}} ->
          {open_now, Map.get(hours, "weekday_text", [])}

        %{"additional_data" => %{"opening_hours" => hours}} ->
          {Map.get(hours, "open_now"), Map.get(hours, "weekday_text", [])}

        _ ->
          {nil, []}
      end

    socket
    |> assign(:address, address)
    |> assign(:phone, phone)
    |> assign(:website, website)
    |> assign(:google_maps_url, google_maps_url)
    |> assign(:rating, rating)
    |> assign(:user_ratings_total, user_ratings_total)
    |> assign(:price_level_description, price_level_description)
    |> assign(:business_status, business_status)
    |> assign(:types, filter_relevant_types(types))
    |> assign(:is_open_now, is_open_now)
    |> assign(:opening_hours_text, opening_hours_text)
    |> assign_availability_flags()
  end

  defp assign_availability_flags(socket) do
    socket
    |> assign(:has_contact_info, has_contact_info?(socket.assigns))
    |> assign(:has_opening_hours, has_opening_hours?(socket.assigns))
    |> assign(:has_rating_info, has_rating_info?(socket.assigns))
    |> assign(:has_business_info, has_business_info?(socket.assigns))
  end

  defp has_contact_info?(assigns) do
    assigns[:address] || assigns[:phone] || assigns[:website]
  end

  defp has_opening_hours?(assigns) do
    assigns[:is_open_now] != nil ||
      (assigns[:opening_hours_text] && length(assigns[:opening_hours_text]) > 0)
  end

  defp has_rating_info?(assigns) do
    (assigns[:rating] && assigns[:rating] > 0) || assigns[:price_level_description]
  end

  defp has_business_info?(assigns) do
    (assigns[:business_status] && assigns[:business_status] != "OPERATIONAL") ||
      (assigns[:types] && length(assigns[:types]) > 0)
  end

  defp format_ratings_count(count) when is_integer(count) do
    cond do
      count >= 1000 -> "#{div(count, 1000)}k+ reviews"
      count > 1 -> "#{count} reviews"
      count == 1 -> "1 review"
      true -> ""
    end
  end

  defp format_ratings_count(_), do: ""

  defp format_price_level_description(nil), do: nil
  defp format_price_level_description(0), do: "Free"
  defp format_price_level_description(1), do: "Inexpensive"
  defp format_price_level_description(2), do: "Moderate"
  defp format_price_level_description(3), do: "Expensive"
  defp format_price_level_description(4), do: "Very Expensive"
  defp format_price_level_description(_), do: nil

  defp format_business_status("CLOSED_TEMPORARILY"), do: "Temporarily Closed"
  defp format_business_status("CLOSED_PERMANENTLY"), do: "Permanently Closed"
  defp format_business_status(status), do: String.replace(status, "_", " ") |> String.capitalize()

  defp filter_relevant_types(types) when is_list(types) do
    types
    |> Enum.reject(&(&1 in ["establishment", "point_of_interest"]))
    |> Enum.take(6)
  end

  defp filter_relevant_types(_), do: []
end
