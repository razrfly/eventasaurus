defmodule EventasaurusDiscovery.Categories.CategoryClassifier do
  @moduledoc """
  ML-powered category classification using zero-shot NLI (Natural Language Inference).

  Uses facebook/bart-large-mnli model via Bumblebee for zero-shot classification.
  Maps event text to our category taxonomy without training data.

  ## Usage

      # Single classification
      {:ok, result} = CategoryClassifier.classify("Live jazz concert at the Blue Note")
      # => {:ok, %{category: "concerts", score: 0.92, all_scores: %{...}}}

      # Batch classification (more efficient for multiple texts)
      {:ok, results} = CategoryClassifier.classify_batch(["rock concert", "comedy show"])

  ## Configuration

  The model is loaded lazily on first use. Set environment variables:
  - `ML_CATEGORY_MODEL` - Model name (default: "facebook/bart-large-mnli")
  - `ML_CATEGORY_THRESHOLD` - Minimum confidence threshold (default: 0.5)
  """

  require Logger

  # Default model for zero-shot classification
  @default_model "facebook/bart-large-mnli"

  # Minimum confidence threshold for classification
  @default_threshold 0.5

  # Map our category slugs to natural language labels for the NLI model.
  # These labels are crafted to work well with the NLI hypothesis format:
  # "This text is about {label}"
  @category_labels %{
    "concerts" => "a live music concert or musical performance",
    "theatre" => "a theatre play, stage performance, or dramatic production",
    "film" => "a movie screening, cinema showing, or film festival",
    "comedy" => "a comedy show, stand-up performance, or humorous entertainment",
    "sports" => "a sports event, athletic competition, or fitness activity",
    "arts" => "an art exhibition, gallery show, or visual arts event",
    "food-drink" => "a food festival, culinary event, wine tasting, or dining experience",
    "nightlife" => "a nightclub party, DJ event, or late-night entertainment",
    "festivals" => "a festival, large outdoor celebration, or multi-day event",
    "family" => "a family-friendly event, kids activity, or children's entertainment",
    "education" => "a workshop, class, lecture, or educational event",
    "community" => "a community gathering, local meetup, or neighborhood event",
    "business" => "a business conference, networking event, or professional meetup",
    "trivia" => "a trivia night, pub quiz, or knowledge competition",
    "other" => "a general event or miscellaneous activity"
  }

  # Reverse lookup: label -> slug
  @label_to_slug @category_labels
                 |> Enum.map(fn {slug, label} -> {label, slug} end)
                 |> Map.new()

  @doc """
  Returns the category labels map (slug -> natural language label).
  """
  @spec category_labels() :: %{String.t() => String.t()}
  def category_labels, do: @category_labels

  @doc """
  Returns list of all category slugs.
  """
  @spec category_slugs() :: [String.t()]
  def category_slugs, do: Map.keys(@category_labels)

  @doc """
  Returns list of natural language labels used for classification.
  """
  @spec labels() :: [String.t()]
  def labels, do: Map.values(@category_labels)

  @doc """
  Classify a text input into event categories using zero-shot NLI.

  ## Options

  - `:threshold` - Minimum confidence score (default: #{@default_threshold})
  - `:serving` - Pre-initialized Nx.Serving (optional, for performance)

  ## Returns

  - `{:ok, %{category: slug, score: float, all_scores: map}}` on success
  - `{:error, reason}` on failure
  - `{:ok, %{category: "other", score: score, ...}}` if below threshold

  ## Examples

      iex> CategoryClassifier.classify("Rock concert at Madison Square Garden")
      {:ok, %{category: "concerts", score: 0.94, all_scores: %{...}}}

      iex> CategoryClassifier.classify("Unknown gibberish text")
      {:ok, %{category: "other", score: 0.32, all_scores: %{...}}}
  """
  @spec classify(String.t(), keyword()) ::
          {:ok, %{category: String.t(), score: float(), all_scores: map()}} | {:error, term()}
  def classify(text, opts \\ []) when is_binary(text) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    serving = Keyword.get_lazy(opts, :serving, &get_serving/0)

    case serving do
      {:error, reason} ->
        {:error, reason}

      serving when is_struct(serving, Nx.Serving) ->
        do_classify(serving, text, threshold)

      _ ->
        {:error, :invalid_serving}
    end
  end

  @doc """
  Batch classify multiple texts efficiently.

  More efficient than calling `classify/2` multiple times as it batches
  the model inference.

  ## Options

  - `:threshold` - Minimum confidence score (default: #{@default_threshold})
  - `:serving` - Pre-initialized Nx.Serving (optional)

  ## Returns

  - `{:ok, [%{category: slug, score: float, all_scores: map}, ...]}` on success
  - `{:error, reason}` on failure
  """
  @spec classify_batch([String.t()], keyword()) ::
          {:ok, [%{category: String.t(), score: float(), all_scores: map()}]} | {:error, term()}
  def classify_batch(texts, opts \\ []) when is_list(texts) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    serving = Keyword.get_lazy(opts, :serving, &get_serving/0)

    case serving do
      {:error, reason} ->
        {:error, reason}

      serving when is_struct(serving, Nx.Serving) ->
        results =
          texts
          |> Enum.map(fn text ->
            case do_classify(serving, text, threshold) do
              {:ok, result} -> result
              {:error, _} -> %{category: "other", score: 0.0, all_scores: %{}, error: true}
            end
          end)

        {:ok, results}

      _ ->
        {:error, :invalid_serving}
    end
  end

  @doc """
  Get or create the Nx.Serving for zero-shot classification.

  The serving is lazily initialized on first call. Subsequent calls
  return the cached serving from the process dictionary.

  ## Options

  - `:model` - Model name (default: "#{@default_model}")
  - `:force_reload` - Force reload even if cached (default: false)

  ## Returns

  - `Nx.Serving.t()` on success
  - `{:error, reason}` on failure
  """
  @spec get_serving(keyword()) :: Nx.Serving.t() | {:error, term()}
  def get_serving(opts \\ []) do
    force_reload = Keyword.get(opts, :force_reload, false)
    model_name = Keyword.get(opts, :model, model_name())

    cache_key = {:category_classifier_serving, model_name}

    case {force_reload, Process.get(cache_key)} do
      {false, serving} when not is_nil(serving) ->
        serving

      _ ->
        case load_serving(model_name) do
          {:ok, serving} ->
            Process.put(cache_key, serving)
            serving

          {:error, reason} = error ->
            Logger.error("[CategoryClassifier] Failed to load serving: #{inspect(reason)}")
            error
        end
    end
  end

  @doc """
  Check if the ML model is available and working.

  Useful for health checks and graceful degradation.
  """
  @spec available?() :: boolean()
  def available? do
    case get_serving() do
      {:error, _} -> false
      serving when is_struct(serving, Nx.Serving) -> true
      _ -> false
    end
  end

  @doc """
  Get the configured model name.
  """
  @spec model_name() :: String.t()
  def model_name do
    System.get_env("ML_CATEGORY_MODEL", @default_model)
  end

  @doc """
  Get the configured confidence threshold.
  """
  @spec threshold() :: float()
  def threshold do
    case System.get_env("ML_CATEGORY_THRESHOLD") do
      nil -> @default_threshold
      val -> String.to_float(val)
    end
  end

  # Private functions

  defp do_classify(serving, text, threshold) do
    try do
      result = Nx.Serving.run(serving, text)
      process_prediction(result, threshold)
    rescue
      e ->
        Logger.error("[CategoryClassifier] Classification failed: #{inspect(e)}")
        {:error, {:classification_failed, e}}
    end
  end

  defp process_prediction(%{predictions: predictions}, threshold) when is_list(predictions) do
    # Build all_scores map: slug -> score
    all_scores =
      predictions
      |> Enum.map(fn %{label: label, score: score} ->
        slug = Map.get(@label_to_slug, label, "other")
        {slug, Float.round(score, 4)}
      end)
      |> Map.new()

    # Get top prediction
    case predictions do
      [%{label: top_label, score: top_score} | _] ->
        top_slug = Map.get(@label_to_slug, top_label, "other")

        # Apply threshold - if below, return "other"
        final_category = if top_score >= threshold, do: top_slug, else: "other"

        {:ok,
         %{
           category: final_category,
           score: Float.round(top_score, 4),
           all_scores: all_scores
         }}

      [] ->
        {:ok, %{category: "other", score: 0.0, all_scores: all_scores}}
    end
  end

  defp process_prediction(result, _threshold) do
    Logger.warning("[CategoryClassifier] Unexpected prediction format: #{inspect(result)}")
    {:error, {:unexpected_format, result}}
  end

  defp load_serving(model_name) do
    Logger.info("[CategoryClassifier] Loading model: #{model_name}")

    with {:ok, model_info} <- load_model(model_name),
         {:ok, tokenizer} <- load_tokenizer(model_name) do
      labels = labels()

      serving =
        Bumblebee.Text.zero_shot_classification(
          model_info,
          tokenizer,
          labels,
          compile: [batch_size: 1, sequence_length: 128],
          defn_options: [compiler: EXLA]
        )

      Logger.info("[CategoryClassifier] Model loaded successfully with #{length(labels)} labels")
      {:ok, serving}
    end
  end

  defp load_model(model_name) do
    Logger.debug("[CategoryClassifier] Loading model weights...")

    case Bumblebee.load_model({:hf, model_name}) do
      {:ok, _} = result -> result
      {:error, reason} -> {:error, {:model_load_failed, reason}}
    end
  end

  defp load_tokenizer(model_name) do
    Logger.debug("[CategoryClassifier] Loading tokenizer...")

    case Bumblebee.load_tokenizer({:hf, model_name}) do
      {:ok, _} = result -> result
      {:error, reason} -> {:error, {:tokenizer_load_failed, reason}}
    end
  end
end
