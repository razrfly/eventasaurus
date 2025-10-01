defmodule EventasaurusDiscovery.Sources.Pubquiz.Config do
  @moduledoc """
  Configuration for PubQuiz.pl scraper.

  PubQuiz.pl is a Poland-wide platform for weekly trivia nights.
  Base URL: https://pubquiz.pl/bilety/
  """

  @base_url "https://pubquiz.pl/bilety/"
  @rate_limit_seconds 2
  @timeout_ms 30_000

  def base_url, do: @base_url

  def rate_limit, do: @rate_limit_seconds

  def timeout, do: @timeout_ms

  def headers do
    [
      {"User-Agent", "Eventasaurus Discovery Bot/1.0"},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7"}
    ]
  end

  def max_retries, do: 2
  def retry_delay_ms, do: 5_000
end
