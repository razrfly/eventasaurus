defmodule EventasaurusWeb.MarketingHTML do
  use EventasaurusWeb, :html

  import EventasaurusWeb.MarketingComponents
  import EventasaurusWeb.OatmealComponents

  embed_templates "marketing_html/*"
end
