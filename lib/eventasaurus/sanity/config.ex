defmodule Eventasaurus.Sanity.Config do
  @moduledoc """
  Configuration helpers for Sanity CMS integration.
  """

  @doc """
  Returns the Sanity project ID.
  Raises if not configured.
  """
  def project_id do
    get_config(:project_id) || raise "SANITY_PROJECT_ID not configured"
  end

  @doc """
  Returns the Sanity API token.
  Raises if not configured.
  """
  def api_token do
    get_config(:api_token) || raise "SANITY_API_TOKEN not configured"
  end

  @doc """
  Returns the Sanity dataset name.
  Defaults to "production".
  """
  def dataset do
    get_config(:dataset) || "production"
  end

  @doc """
  Returns true if Sanity is properly configured.
  """
  def enabled? do
    project_id = get_config(:project_id)
    api_token = get_config(:api_token)
    project_id != nil and project_id != "" and api_token != nil and api_token != ""
  end

  defp get_config(key) do
    Application.get_env(:eventasaurus, :sanity, [])[key]
  end
end
