defmodule EventasaurusApp.Storage.StorageError do
  @moduledoc """
  Defines error types for storage operations.
  """

  @type t :: %__MODULE__{
    message: String.t(),
    reason: atom(),
    status_code: integer() | nil
  }

  defstruct message: nil, reason: nil, status_code: nil

  @doc """
  Creates a not found error.
  """
  def not_found(message) do
    %__MODULE__{
      message: message,
      reason: :not_found,
      status_code: 404
    }
  end

  @doc """
  Creates a server error.
  """
  def server_error(message) do
    %__MODULE__{
      message: message,
      reason: :server_error,
      status_code: 500
    }
  end

  @doc """
  Creates a bad request error.
  """
  def bad_request(message) do
    %__MODULE__{
      message: message,
      reason: :bad_request,
      status_code: 400
    }
  end

  @doc """
  Creates an unauthorized error.
  """
  def unauthorized(message) do
    %__MODULE__{
      message: message,
      reason: :unauthorized,
      status_code: 401
    }
  end

  @doc """
  Creates a forbidden error.
  """
  def forbidden(message) do
    %__MODULE__{
      message: message,
      reason: :forbidden,
      status_code: 403
    }
  end
end
