defmodule EventasaurusDiscovery.Sources.QuestionOne do
  @moduledoc """
  Convenience module for Question One source.

  Delegates to EventasaurusDiscovery.Sources.QuestionOne.Source
  for cleaner imports and references.
  """

  defdelegate name(), to: EventasaurusDiscovery.Sources.QuestionOne.Source
  defdelegate key(), to: EventasaurusDiscovery.Sources.QuestionOne.Source
  defdelegate enabled?(), to: EventasaurusDiscovery.Sources.QuestionOne.Source
  defdelegate priority(), to: EventasaurusDiscovery.Sources.QuestionOne.Source
  defdelegate config(), to: EventasaurusDiscovery.Sources.QuestionOne.Source
  defdelegate sync_job_args(options \\ %{}), to: EventasaurusDiscovery.Sources.QuestionOne.Source

  defdelegate detail_job_args(venue_url, metadata \\ %{}),
    to: EventasaurusDiscovery.Sources.QuestionOne.Source

  defdelegate validate_config(), to: EventasaurusDiscovery.Sources.QuestionOne.Source
end
