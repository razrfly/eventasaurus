defmodule EventasaurusWeb.PublicEventController do
  use EventasaurusWeb, :controller

  # List of reserved slugs that should not be treated as event slugs
  @reserved_slugs ~w(login register logout dashboard help pricing privacy terms contact)

  # Keep reserved slugs check for other actions if needed
  def check_reserved_slug(slug) do
    slug in @reserved_slugs
  end
end
