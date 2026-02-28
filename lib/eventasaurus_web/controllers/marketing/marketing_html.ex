defmodule EventasaurusWeb.MarketingHTML do
  use EventasaurusWeb, :html

  import EventasaurusWeb.MarketingComponents
  import EventasaurusWeb.OatmealComponents

  embed_templates "marketing_html/*"

  defp next_friday_label do
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)
    days_ahead = case day_of_week do
      n when n < 5 -> 5 - n
      n -> 12 - n
    end
    next_friday = Date.add(today, days_ahead)
    "#{Calendar.strftime(next_friday, "%a")} #{next_friday.day} #{Calendar.strftime(next_friday, "%b")}"
  end
end
