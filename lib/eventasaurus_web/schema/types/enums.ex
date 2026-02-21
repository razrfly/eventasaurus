defmodule EventasaurusWeb.Schema.Types.Enums do
  use Absinthe.Schema.Notation

  enum :event_status do
    value(:draft)
    value(:polling)
    value(:threshold)
    value(:confirmed)
    value(:canceled)
  end

  enum :event_visibility do
    value(:public)
    value(:private)
  end

  enum :event_theme do
    value(:minimal)
    value(:cosmic)
    value(:velocity)
    value(:retro)
    value(:celebration)
    value(:nature)
    value(:professional)
  end

  @desc "Client-friendly RSVP status. Mapped to internal DB values by the resolver layer."
  enum :rsvp_status do
    value(:going)
    value(:interested)
    value(:not_going)
  end
end
