defmodule EventasaurusWeb.PublicEventController do
  use EventasaurusWeb, :controller

  alias EventasaurusWeb.ReservedSlugs

  # Keep reserved slugs check for other actions if needed
  def check_reserved_slug(slug) do
    ReservedSlugs.reserved?(slug)
  end
end
