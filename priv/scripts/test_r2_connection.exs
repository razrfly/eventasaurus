# Test Cloudflare R2 Connection
#
# Usage: mix run priv/scripts/test_r2_connection.exs

IO.puts("\n=== Cloudflare R2 Connection Test ===\n")

# Load environment variables
account_id = System.get_env("CLOUDFLARE_ACCOUNT_ID")
access_key = System.get_env("CLOUDFLARE_ACCESS_KEY_ID")
secret_key = System.get_env("CLOUDFLARE_SECRET_ACCESS_KEY")
bucket = "wombie"

# Validate credentials exist
missing = []
missing = if is_nil(account_id) or account_id == "", do: ["CLOUDFLARE_ACCOUNT_ID" | missing], else: missing
missing = if is_nil(access_key) or access_key == "", do: ["CLOUDFLARE_ACCESS_KEY_ID" | missing], else: missing
missing = if is_nil(secret_key) or secret_key == "", do: ["CLOUDFLARE_SECRET_ACCESS_KEY" | missing], else: missing

if length(missing) > 0 do
  IO.puts("❌ Missing environment variables: #{Enum.join(missing, ", ")}")
  IO.puts("\nMake sure these are set in your .env file")
  System.halt(1)
end

IO.puts("✓ Credentials loaded")
IO.puts("  Account ID: #{String.slice(account_id, 0, 8)}...")
IO.puts("  Access Key: #{String.slice(access_key, 0, 8)}...")
IO.puts("  Bucket: #{bucket}")

# Configure ExAws for R2
config = [
  access_key_id: access_key,
  secret_access_key: secret_key,
  region: "auto",
  scheme: "https://",
  host: "#{account_id}.r2.cloudflarestorage.com",
  port: 443
]

IO.puts("\n--- Test 1: List bucket contents ---")

case ExAws.S3.list_objects(bucket, max_keys: 10) |> ExAws.request(config) do
  {:ok, %{body: %{contents: contents}}} ->
    IO.puts("✓ Successfully connected to R2 bucket '#{bucket}'")
    if length(contents) > 0 do
      IO.puts("  Found #{length(contents)} objects:")
      Enum.each(Enum.take(contents, 5), fn obj ->
        IO.puts("    - #{obj.key} (#{obj.size} bytes)")
      end)
      if length(contents) > 5, do: IO.puts("    ... and #{length(contents) - 5} more")
    else
      IO.puts("  Bucket is empty (this is expected for a new bucket)")
    end

  {:ok, %{body: body}} ->
    IO.puts("✓ Connected to R2")
    IO.puts("  Response: #{inspect(body)}")

  {:error, {:http_error, 403, %{body: body}}} ->
    IO.puts("❌ Access denied (403)")
    IO.puts("  Check that your API token has 'Object Read & Write' permissions")
    IO.puts("  Response: #{body}")

  {:error, {:http_error, 404, _}} ->
    IO.puts("❌ Bucket not found (404)")
    IO.puts("  Make sure bucket 'wombie' exists in your R2 dashboard")

  {:error, error} ->
    IO.puts("❌ Connection failed")
    IO.puts("  Error: #{inspect(error)}")
end

IO.puts("\n--- Test 2: Upload test file ---")

test_content = "Hello from Eventasaurus! Test at #{DateTime.utc_now() |> DateTime.to_iso8601()}"
test_path = "test/connection-test.txt"

case ExAws.S3.put_object(bucket, test_path, test_content, content_type: "text/plain")
     |> ExAws.request(config) do
  {:ok, _} ->
    IO.puts("✓ Successfully uploaded test file to #{test_path}")

  {:error, {:http_error, 403, _}} ->
    IO.puts("❌ Upload denied (403)")
    IO.puts("  Check that your API token has write permissions")

  {:error, error} ->
    IO.puts("❌ Upload failed")
    IO.puts("  Error: #{inspect(error)}")
end

IO.puts("\n--- Test 3: Read test file back ---")

case ExAws.S3.get_object(bucket, test_path) |> ExAws.request(config) do
  {:ok, %{body: body}} ->
    IO.puts("✓ Successfully read test file")
    IO.puts("  Content: #{body}")

  {:error, error} ->
    IO.puts("❌ Read failed")
    IO.puts("  Error: #{inspect(error)}")
end

IO.puts("\n--- Test 4: Check public URL ---")

public_url = "https://cdn2.wombie.com/#{test_path}"
IO.puts("Public URL would be: #{public_url}")
IO.puts("(This will only work after CDN is configured)")

IO.puts("\n=== Test Complete ===\n")
