defmodule EventasaurusApp.Repo.Migrations.NormalizeSupabaseImageUrls do
  @moduledoc """
  Normalize legacy Supabase storage URLs to relative paths.

  This migration converts full Supabase URLs like:
    https://vnhxedeynrtvakglinnr.supabase.co/storage/v1/object/public/eventasaur.us/events/image.jpg

  To relative paths like:
    events/image.jpg

  The ImageUrlHelper.resolve/1 function prepends the R2 CDN URL at runtime,
  so we only need to store the relative path.

  Tables affected:
  - events.cover_image_url
  - groups.cover_image_url
  - groups.avatar_url
  - poll_options.image_url
  - sources.logo_url

  Note: External URLs (TMDB, Unsplash, picsum, etc.) are NOT modified.
  Only URLs containing 'supabase.co/storage' are converted.
  """
  use Ecto.Migration

  # The Supabase bucket name used in production
  @bucket_name "eventasaur.us"

  def up do
    # Pattern explanation:
    # - Match: https://{any}.supabase.co/storage/v1/object/public/{bucket}/{path}
    # - Replace with: {path}
    #
    # The regex captures everything after the bucket name as the path
    # Using regexp_replace with 'g' flag for global replacement (though we expect one match)

    # events.cover_image_url
    execute """
    UPDATE events
    SET cover_image_url = regexp_replace(
      cover_image_url,
      '^https://[^/]+\\.supabase\\.co/storage/v1/object/public/#{@bucket_name}/(.+)$',
      '\\1'
    )
    WHERE cover_image_url LIKE '%supabase.co/storage%'
    """

    # groups.cover_image_url
    execute """
    UPDATE groups
    SET cover_image_url = regexp_replace(
      cover_image_url,
      '^https://[^/]+\\.supabase\\.co/storage/v1/object/public/#{@bucket_name}/(.+)$',
      '\\1'
    )
    WHERE cover_image_url LIKE '%supabase.co/storage%'
    """

    # groups.avatar_url
    execute """
    UPDATE groups
    SET avatar_url = regexp_replace(
      avatar_url,
      '^https://[^/]+\\.supabase\\.co/storage/v1/object/public/#{@bucket_name}/(.+)$',
      '\\1'
    )
    WHERE avatar_url LIKE '%supabase.co/storage%'
    """

    # poll_options.image_url
    execute """
    UPDATE poll_options
    SET image_url = regexp_replace(
      image_url,
      '^https://[^/]+\\.supabase\\.co/storage/v1/object/public/#{@bucket_name}/(.+)$',
      '\\1'
    )
    WHERE image_url LIKE '%supabase.co/storage%'
    """

    # sources.logo_url
    execute """
    UPDATE sources
    SET logo_url = regexp_replace(
      logo_url,
      '^https://[^/]+\\.supabase\\.co/storage/v1/object/public/#{@bucket_name}/(.+)$',
      '\\1'
    )
    WHERE logo_url LIKE '%supabase.co/storage%'
    """
  end

  def down do
    # This migration is not reversible in a meaningful way because:
    # 1. We don't know which Supabase project ID was used
    # 2. The runtime ImageUrlHelper.resolve/1 handles both formats
    # 3. Rolling back would require re-uploading images to Supabase
    #
    # If you need to rollback, the ImageUrlHelper.resolve/1 function
    # will still correctly resolve relative paths to R2 CDN URLs.
    :ok
  end
end
