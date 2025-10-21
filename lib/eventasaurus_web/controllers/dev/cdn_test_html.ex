defmodule EventasaurusWeb.Dev.CdnTestHTML do
  use EventasaurusWeb, :html

  alias Eventasaurus.CDN

  embed_templates "cdn_test_html/*"
end
