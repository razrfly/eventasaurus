defmodule EventasaurusWeb.ReservedSlugs do
  @moduledoc """
  Centralized module for managing reserved slugs that cannot be used for event URLs.

  These slugs are reserved for application routes like authentication, dashboard,
  and other system pages. While the router order should prevent conflicts,
  this module provides defensive checking and a single source of truth.
  """

  @reserved_slugs ~w(
    login
    register
    logout
    dashboard
    help
    pricing
    privacy
    terms
    contact
    events
    api
    dev
    admin
    auth
    callback
    forgot-password
    reset-password
  )

  @doc """
  Returns the complete list of reserved slugs.
  """
  def all, do: @reserved_slugs

  @doc """
  Checks if a given slug is reserved.

  ## Examples

      iex> EventasaurusWeb.ReservedSlugs.reserved?("login")
      true

      iex> EventasaurusWeb.ReservedSlugs.reserved?("my-event")
      false
  """
  def reserved?(slug) when is_binary(slug) do
    slug in @reserved_slugs
  end

  def reserved?(_), do: false
end
