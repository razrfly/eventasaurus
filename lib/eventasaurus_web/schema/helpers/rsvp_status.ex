defmodule EventasaurusWeb.Schema.Helpers.RsvpStatus do
  @moduledoc """
  Bidirectional mapping between client-friendly GraphQL RSVP status
  enums and internal database atom values.

  GraphQL uses: GOING, INTERESTED, NOT_GOING
  Database uses: :accepted, :interested, :declined, :cancelled, :confirmed_with_order, :pending
  """

  # GraphQL → DB
  def to_db(:going), do: :accepted
  def to_db(:interested), do: :interested
  def to_db(:not_going), do: :declined

  # DB → GraphQL
  def from_db(:accepted), do: :going
  def from_db(:confirmed_with_order), do: :going
  def from_db(:interested), do: :interested
  def from_db(:declined), do: :not_going
  def from_db(:cancelled), do: :not_going
  def from_db(:pending), do: :interested
  def from_db(nil), do: nil
  def from_db(_unknown), do: :interested
end
