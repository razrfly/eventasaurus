alias EventasaurusDiscovery.Sources.Sortiraparis.Client

url = "https://www.sortiraparis.com/en/what-to-visit-in-paris/exhibit-museum/articles/327359-open-air-exhibition-of-works-by-andrea-roggi-quartier-faubourg-saint-honore"

case Client.fetch_page(url) do
  {:ok, html} ->
    File.write!("/tmp/sortiraparis_exhibition.html", html)
    IO.puts("✅ HTML saved to /tmp/sortiraparis_exhibition.html (#{byte_size(html)} bytes)")

  {:error, reason} ->
    IO.puts("❌ Failed: #{inspect(reason)}")
end
