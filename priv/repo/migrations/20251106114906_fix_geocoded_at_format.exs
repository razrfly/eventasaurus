defmodule EventasaurusApp.Repo.Migrations.FixGeocodedAtFormat do
  use Ecto.Migration

  def up do
    # Fix geocoded_at format in geocoding_performance JSONB field
    # Convert DateTime struct JSON to ISO8601 string
    execute """
    UPDATE venues
    SET geocoding_performance = jsonb_set(
      geocoding_performance,
      '{geocoded_at}',
      to_jsonb(
        make_timestamptz(
          (geocoding_performance->'geocoded_at'->>'year')::int,
          (geocoding_performance->'geocoded_at'->>'month')::int,
          (geocoding_performance->'geocoded_at'->>'day')::int,
          (geocoding_performance->'geocoded_at'->>'hour')::int,
          (geocoding_performance->'geocoded_at'->>'minute')::int,
          (geocoding_performance->'geocoded_at'->>'second')::int +
            COALESCE((geocoding_performance->'geocoded_at'->'microsecond'->>0)::numeric / 1000000, 0)
        )::text
      )
    )
    WHERE geocoding_performance IS NOT NULL
      AND jsonb_typeof(geocoding_performance->'geocoded_at') = 'object';
    """
  end

  def down do
    # Cannot reliably reverse this migration
    # Would need to convert ISO8601 strings back to DateTime structs
    :ok
  end
end
