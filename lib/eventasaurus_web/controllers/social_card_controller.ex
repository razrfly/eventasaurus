defmodule EventasaurusWeb.SocialCardController do
  @moduledoc """
  Base controller behaviour for social card generation.

  This module defines a common flow for all social card controllers, extracting
  the shared logic while allowing type-specific implementations through callbacks.

  ## Usage

      defmodule EventasaurusWeb.MySocialCardController do
        use EventasaurusWeb.SocialCardController, type: :my_type

        @impl true
        def lookup_entity(params) do
          # Return {:ok, entity} or {:error, :not_found, "Message"}
        end

        @impl true
        def build_card_data(entity) do
          # Return map with data needed for social card
        end

        @impl true
        def build_slug(params, data) do
          # Return string slug for logging/file naming
        end

        @impl true
        def sanitize(data) do
          # Return sanitized data
        end

        @impl true
        def render_svg(data) do
          # Return SVG string
        end
      end
  """

  @doc """
  Looks up the entity from route params.
  Returns {:ok, entity} or {:error, :not_found, message}.
  """
  @callback lookup_entity(params :: map()) ::
              {:ok, term()} | {:error, :not_found, String.t()}

  @doc """
  Builds the data map needed for the social card from the entity.
  """
  @callback build_card_data(entity :: term()) :: map()

  @doc """
  Builds the slug string used for logging and file naming.
  """
  @callback build_slug(params :: map(), data :: map()) :: String.t()

  @doc """
  Sanitizes the data before rendering.
  """
  @callback sanitize(data :: map()) :: map()

  @doc """
  Renders the SVG content for the social card.
  """
  @callback render_svg(sanitized_data :: map()) :: String.t()

  defmacro __using__(opts) do
    card_type = Keyword.fetch!(opts, :type)

    quote do
      use EventasaurusWeb, :controller

      require Logger

      alias EventasaurusWeb.Helpers.SocialCardHelpers

      @behaviour EventasaurusWeb.SocialCardController

      @card_type unquote(card_type)

      @doc """
      Generates a social card PNG with hash validation.
      Provides cache busting through hash-based URLs.
      """
      def generate_card(conn, %{"hash" => hash, "rest" => rest} = params) do
        final_hash = SocialCardHelpers.parse_hash(hash, rest)

        case lookup_entity(params) do
          {:error, :not_found, message} ->
            Logger.warning(message)
            send_resp(conn, 404, message)

          {:ok, entity} ->
            data = build_card_data(entity)
            slug = build_slug(params, data)

            Logger.info("#{@card_type} social card requested for #{slug}, hash: #{hash}")

            if SocialCardHelpers.validate_hash(data, final_hash, @card_type) do
              Logger.info("Hash validated for #{@card_type} #{slug}")

              sanitized_data = sanitize(data)
              svg_content = render_svg(sanitized_data)

              case SocialCardHelpers.generate_png(svg_content, slug, sanitized_data) do
                {:ok, png_data} ->
                  SocialCardHelpers.send_png_response(conn, png_data, final_hash)

                {:error, error} ->
                  SocialCardHelpers.send_error_response(conn, error)
              end
            else
              SocialCardHelpers.send_hash_mismatch_redirect(
                conn,
                data,
                slug,
                final_hash,
                @card_type
              )
            end
        end
      end

      # Allow controllers to override if they need custom action names
      defoverridable generate_card: 2
    end
  end
end
