defmodule EventasaurusWeb.MarketingHTML do
  use EventasaurusWeb, :html

  import EventasaurusWeb.MarketingComponents
  import EventasaurusWeb.OatmealComponents

  embed_templates "marketing_html/*"

  defp next_friday_label do
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)
    days_ahead = if day_of_week < 5, do: 5 - day_of_week, else: 12 - day_of_week
    next_friday = Date.add(today, days_ahead)
    "#{Calendar.strftime(next_friday, "%a")} #{next_friday.day} #{Calendar.strftime(next_friday, "%b")}"
  end
end
