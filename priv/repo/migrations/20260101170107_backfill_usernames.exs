defmodule EventasaurusApp.Repo.Migrations.BackfillUsernames do
  @moduledoc """
  Backfill usernames for all users with NULL username.

  Username generation priority:
  1. Name-based: First name slugified + last initial (e.g., "john-s")
  2. Email-based: Email prefix slugified (e.g., "john.doe@..." -> "johndoe")
  3. Fallback: "user-{id}"

  Handles uniqueness conflicts by appending incrementing numbers.
  """
  use Ecto.Migration

  @username_regex ~r/^[a-zA-Z0-9_-]{3,30}$/

  # Reserved usernames that cannot be used
  @reserved_usernames ~w(
    admin administrator root system support help api www about contact
    privacy terms login logout signup register dashboard events orders
    tickets checkout profile settings user users home index new edit
    delete create update destroy show list admin organizer host
    attendee guest member moderator owner manager staff team
  )

  def up do
    # Get all users with NULL username
    result =
      Ecto.Adapters.SQL.query!(
        repo(),
        "SELECT id, name, email FROM users WHERE username IS NULL ORDER BY id",
        []
      )

    IO.puts("Found #{result.num_rows} users with NULL username")

    # Process each user
    Enum.each(result.rows, fn [user_id, name, email] ->
      username = generate_unique_username(user_id, name, email)
      IO.puts("Setting username for user #{user_id}: #{username}")

      Ecto.Adapters.SQL.query!(
        repo(),
        "UPDATE users SET username = $1 WHERE id = $2",
        [username, user_id]
      )
    end)

    IO.puts("Backfill complete!")
  end

  def down do
    # Cannot automatically reverse - would need to track which usernames were auto-generated
    IO.puts("Note: Cannot automatically revert auto-generated usernames")
    IO.puts("Manual intervention required if rollback needed")
  end

  # Generate a unique username for a user
  defp generate_unique_username(user_id, name, email) do
    base = generate_base_username(name, email, user_id)
    ensure_unique(base, user_id)
  end

  # Generate base username from name or email
  defp generate_base_username(name, email, user_id) do
    cond do
      # Try name-based first
      is_binary(name) and String.trim(name) != "" ->
        case from_name(name) do
          nil -> from_email_or_fallback(email, user_id)
          username -> username
        end

      # Try email-based
      is_binary(email) ->
        from_email_or_fallback(email, user_id)

      # Fallback
      true ->
        "user-#{user_id}"
    end
  end

  defp from_email_or_fallback(email, user_id) do
    case from_email(email) do
      nil -> "user-#{user_id}"
      username -> username
    end
  end

  # Generate from name (first name + last initial)
  defp from_name(name) do
    parts =
      name
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    case parts do
      [first] ->
        slug = slugify_name(first)
        if valid_base?(slug), do: slug, else: nil

      [first | rest] ->
        first_slug = slugify_name(first)
        last = List.last(rest)
        last_initial = last |> String.first() |> String.downcase()

        if is_binary(first_slug) and byte_size(first_slug) >= 2 do
          "#{first_slug}-#{last_initial}"
        else
          nil
        end

      [] ->
        nil
    end
  end

  # Generate from email prefix
  defp from_email(email) when is_binary(email) do
    prefix =
      email
      |> String.split("@")
      |> List.first()
      |> slugify_name()

    if valid_base?(prefix) do
      String.slice(prefix, 0, 30)
    else
      nil
    end
  end

  defp from_email(_), do: nil

  # Slugify a name component
  defp slugify_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.replace(~r/[\s-]+/, "")
    |> case do
      "" -> nil
      slug -> slug
    end
  end

  defp slugify_name(_), do: nil

  defp valid_base?(nil), do: false
  defp valid_base?(slug), do: is_binary(slug) and byte_size(slug) >= 3

  # Ensure username is unique
  defp ensure_unique(base, user_id) do
    cond do
      valid_and_available?(base, user_id) ->
        base

      # Try with incrementing numbers
      true ->
        find_available_variant(base, user_id) || "user-#{user_id}"
    end
  end

  defp find_available_variant(base, user_id) do
    # Truncate base to leave room for suffix (max 30 chars total)
    max_base_len = 26
    truncated_base = String.slice(base || "", 0, max_base_len)

    Enum.find_value(1..99, fn n ->
      candidate = "#{truncated_base}-#{n}"

      if valid_and_available?(candidate, user_id) do
        candidate
      else
        nil
      end
    end)
  end

  defp valid_and_available?(username, user_id) do
    valid?(username) and not username_exists?(username, user_id)
  end

  defp valid?(username) when is_binary(username) do
    String.match?(username, @username_regex) and
      String.downcase(username) not in @reserved_usernames
  end

  defp valid?(_), do: false

  # Check if username already exists (excluding current user)
  defp username_exists?(username, user_id) do
    result =
      Ecto.Adapters.SQL.query!(
        repo(),
        "SELECT 1 FROM users WHERE lower(username) = $1 AND id != $2 LIMIT 1",
        [String.downcase(username), user_id]
      )

    result.num_rows > 0
  end
end
