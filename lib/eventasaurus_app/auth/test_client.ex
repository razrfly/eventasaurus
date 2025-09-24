defmodule EventasaurusApp.Auth.TestClient do
  @moduledoc """
  Test client for mocking Auth.Client behavior in tests.
  This allows tests to simulate authentication without making HTTP requests.
  Uses ETS to share data across processes (needed for LiveView tests).
  """

  require Logger

  @table_name :test_auth_users

  @doc """
  Mock implementation of get_user/1 for testing.

  In tests, we can set up the expected user data and this function will return it.
  Uses ETS to ensure data is available across all processes.
  """
  def get_user(token) do
    case :ets.lookup(@table_name, token) do
      [{^token, user_data}] ->
        {:ok, user_data}

      [] ->
        {:error, %{message: "Invalid token", status: 401}}
    end
  end

  @doc """
  Helper function to set up a mock user for a specific token in tests.
  """
  def set_test_user(token, user_data) do
    # Ensure the ETS table exists
    ensure_table_exists()

    :ets.insert(@table_name, {token, user_data})
    :ok
  end

  @doc """
  Helper function to clear all test users.
  """
  def clear_test_users do
    ensure_table_exists()
    :ets.delete_all_objects(@table_name)
  end

  # Ensure the ETS table exists
  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:named_table, :public, :set])

      _ ->
        :ok
    end
  end
end
