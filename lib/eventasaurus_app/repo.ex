defmodule EventasaurusApp.Repo do
  @moduledoc """
  Mock repository module that satisfies the interface needed by the application.

  Since the app is configured to use Supabase instead of a standard database,
  this implementation mocks the necessary Repo functions to prevent errors.
  """

  @doc """
  Gets a record by id. Returns an empty map since we're mocking the database.
  """
  def get!(_, _id) do
    %{}
  end

  @doc """
  Gets a record by conditions. Returns nil since we're mocking the database.
  """
  def get_by(_, _opts) do
    nil
  end

  @doc """
  Returns all records for the given query. Returns an empty list since we're mocking the database.
  """
  def all(_query) do
    []
  end

  @doc """
  Inserts a record. Returns {:ok, struct} as if the insert succeeded.
  """
  def insert(struct) do
    {:ok, struct}
  end

  @doc """
  Updates a record. Returns {:ok, struct} as if the update succeeded.
  """
  def update(struct) do
    {:ok, struct}
  end

  @doc """
  Deletes a record. Returns {:ok, struct} as if the delete succeeded.
  """
  def delete(struct) do
    {:ok, struct}
  end
end
