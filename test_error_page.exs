# Test the error page detection
alias EventasaurusDiscovery.Sources.Karnet.DetailExtractor

test_html_404 = """
<html>
<head><title>Error 404 - Not Found</title></head>
<body>
<h1>Error 404</h1>
<p>Page not found</p>
</body>
</html>
"""

test_html_polish_404 = """
<html>
<head><title>Nie znaleziono strony</title></head>
<body>
<h1>Nie znaleziono strony</h1>
<p>Strona nie została znaleziona</p>
</body>
</html>
"""

test_html_valid = """
<html>
<head><title>Some Event Title</title></head>
<body>
<h1>Concert Event</h1>
<p>Event details here</p>
</body>
</html>
"""

IO.puts("Testing error page detection:")
IO.puts("404 page with Error 404: #{inspect(DetailExtractor.is_error_page?(test_html_404))}")
IO.puts("Polish 404 page: #{inspect(DetailExtractor.is_error_page?(test_html_polish_404))}")
IO.puts("Valid event page: #{inspect(DetailExtractor.is_error_page?(test_html_valid))}")
