defmodule Eventasaurus.Services.AnonymousIdService do
  @moduledoc """
  Service for generating and managing consistent anonymous user IDs.
  
  Uses session-based IDs stored in the socket assigns to ensure
  the same anonymous user gets the same ID throughout their session.
  """
  
  @doc """
  Gets or generates a consistent anonymous ID for the current session.
  
  For LiveView sockets, this should be called once and stored in assigns.
  For backend services, this generates a temporary ID.
  """
  def get_or_generate_anonymous_id(socket_or_session) when is_map(socket_or_session) do
    case socket_or_session do
      %{assigns: %{anonymous_id: id}} when not is_nil(id) ->
        # Already have an ID in socket assigns
        id
        
      %{assigns: _assigns} ->
        # Generate new ID for LiveView socket
        generate_anonymous_id()
        
      %{"anonymous_id" => id} when not is_nil(id) ->
        # Session map with existing ID
        id
        
      _ ->
        # Generate new ID
        generate_anonymous_id()
    end
  end
  
  def get_or_generate_anonymous_id(_), do: generate_anonymous_id()
  
  @doc """
  Generates a new anonymous ID.
  
  Uses a combination of timestamp and random value to ensure uniqueness
  while being reproducible within a reasonable time window.
  """
  def generate_anonymous_id do
    # Use microsecond timestamp for better uniqueness
    timestamp = System.os_time(:microsecond)
    # Use :crypto for better randomness and more entropy (48 bits)
    random_component = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
    
    "anon_#{timestamp}_#{random_component}"
  end
  
  @doc """
  Stores anonymous ID in socket assigns for consistent use.
  """
  def assign_anonymous_id(socket) do
    case socket.assigns[:anonymous_id] do
      nil ->
        Phoenix.Component.assign(socket, :anonymous_id, generate_anonymous_id())
      _ ->
        socket
    end
  end
  
  @doc """
  Gets the user identifier for analytics, using user_id if available,
  otherwise the anonymous ID.
  """
  def get_user_identifier(user_id, socket_or_session) when is_nil(user_id) do
    get_or_generate_anonymous_id(socket_or_session)
  end
  
  def get_user_identifier(user_id, _socket_or_session) when is_binary(user_id) and user_id != "" do
    user_id
  end
  
  def get_user_identifier(user_id, _socket_or_session) when is_integer(user_id) do
    to_string(user_id)
  end
  
  def get_user_identifier(_user_id, socket_or_session) do
    get_or_generate_anonymous_id(socket_or_session)
  end
end