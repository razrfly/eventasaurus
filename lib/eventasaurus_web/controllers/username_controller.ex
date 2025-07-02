defmodule EventasaurusWeb.UsernameController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Accounts

  @doc """
  Checks username availability for real-time validation.

  GET /api/username/availability/:username

  Returns JSON with availability status, validation errors, and suggestions.
  """
  def check_availability(conn, %{"username" => username}) do
    # Normalize the username (trim whitespace, convert to lowercase for checking)
    normalized_username = String.trim(username)

    cond do
      # Check if username is empty
      normalized_username == "" ->
        conn
        |> json(%{
          available: false,
          valid: false,
          username: username,
          errors: ["Username cannot be empty"],
          suggestions: []
        })

      # Check format validation
      not valid_username_format?(normalized_username) ->
        conn
        |> json(%{
          available: false,
          valid: false,
          username: username,
          errors: ["Username must be 3-30 characters and contain only letters, numbers, underscores, and hyphens"],
          suggestions: []
        })

      # Check if username is reserved
      reserved_username?(normalized_username) ->
        conn
        |> json(%{
          available: false,
          valid: false,
          username: username,
          errors: ["This username is reserved and cannot be used"],
          suggestions: generate_username_suggestions(normalized_username)
        })

      # Check if username is already taken
      username_taken?(normalized_username) ->
        conn
        |> json(%{
          available: false,
          valid: true,
          username: username,
          errors: ["This username is already taken"],
          suggestions: generate_username_suggestions(normalized_username)
        })

      # Username is available
      true ->
        conn
        |> json(%{
          available: true,
          valid: true,
          username: username,
          errors: [],
          suggestions: []
        })
    end
  end

  # Private helper functions

  @username_regex ~r/^[a-zA-Z0-9_-]{3,30}$/

  defp valid_username_format?(username) do
    String.match?(username, @username_regex)
  end

  defp reserved_username?(username) when is_binary(username) do
    username_lower = String.downcase(username)
    username_lower in get_reserved_usernames()
  end

  defp username_taken?(username) when is_binary(username) do
    case Accounts.get_user_by_username(username) do
      nil -> false
      _user -> true
    end
  end

  defp get_reserved_usernames do
    case File.read("priv/reserved_usernames.txt") do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(fn line ->
          line == "" or String.starts_with?(line, "#")
        end)
        |> Enum.map(&String.downcase/1)

      {:error, _} ->
        # Fallback list if file is not found
        ["admin", "administrator", "root", "system", "support", "help", "api", "www",
         "about", "contact", "privacy", "terms", "login", "logout", "signup", "register",
         "dashboard", "events", "orders", "tickets", "checkout", "profile", "settings"]
    end
  end

  defp generate_username_suggestions(username) do
    base = String.downcase(username)

    # Try common patterns for suggestions
    suggestions = [
      "#{base}#{:rand.uniform(999)}",
      "#{base}_#{:rand.uniform(99)}",
      "#{base}#{:rand.uniform(99)}",
      "the_#{base}",
      "#{base}_official"
    ]

    # Filter out suggestions that are also taken or reserved
    suggestions
    |> Enum.reject(fn suggestion ->
      reserved_username?(suggestion) or username_taken?(suggestion)
    end)
    |> Enum.take(3)  # Return up to 3 suggestions
  end
end
