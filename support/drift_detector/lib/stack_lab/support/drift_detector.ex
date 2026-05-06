defmodule StackLab.Support.DriftDetector do
  @moduledoc """
  Deterministic drift detector for comparable AI runs.
  """

  @signal_classes [
    :prompt_drift,
    :tool_call_drift,
    :guard_decision_drift,
    :memory_access_drift,
    :cost_attribution_drift,
    :latency_drift
  ]
  @max_window_count 100
  @raw_keys [
    :body,
    :raw_body,
    :payload,
    :raw_payload,
    :model_output,
    :provider_payload,
    "body",
    "raw_body",
    "payload",
    "raw_payload",
    "model_output",
    "provider_payload"
  ]

  defmodule DriftSignal do
    @moduledoc "Bounded drift signal."
    @enforce_keys [:drift_signal_ref, :signal_class, :magnitude_class, :window_ref, :context_refs]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            drift_signal_ref: String.t(),
            signal_class: atom(),
            magnitude_class: String.t(),
            window_ref: String.t(),
            context_refs: [String.t()]
          }
  end

  @spec signal_classes() :: [atom()]
  def signal_classes, do: @signal_classes

  @spec detect([map()], keyword()) :: {:ok, [DriftSignal.t()]} | {:error, term()}
  def detect(runs, opts \\ [])

  def detect(runs, opts) when is_list(runs) and is_list(opts) do
    with :ok <- bounded_window(runs, opts),
         :ok <- comparable_tenants(runs),
         :ok <- reject_raw_runs(runs) do
      {:ok, build_signals(runs)}
    end
  end

  def detect(_runs, _opts), do: {:error, :invalid_drift_window}

  @spec project(DriftSignal.t()) :: map()
  def project(%DriftSignal{} = signal) do
    %{
      drift_signal_ref: signal.drift_signal_ref,
      signal_class: signal.signal_class,
      magnitude_class: signal.magnitude_class,
      window_ref: signal.window_ref,
      context_refs: signal.context_refs
    }
  end

  defp bounded_window(runs, opts) do
    max_window = Keyword.get(opts, :max_window_count, @max_window_count)

    if is_integer(max_window) and max_window in 1..@max_window_count and
         length(runs) <= max_window do
      :ok
    else
      {:error, :drift_window_unbounded}
    end
  end

  defp comparable_tenants([]), do: :ok

  defp comparable_tenants([first | rest]) do
    tenant = fetch(first, :tenant_ref)

    if Enum.all?(rest, &(fetch(&1, :tenant_ref) == tenant)) do
      :ok
    else
      {:error, :cross_tenant_drift_comparison_forbidden}
    end
  end

  defp reject_raw_runs(runs) do
    runs
    |> Enum.find_value(:ok, fn run ->
      case Enum.find(@raw_keys, &Map.has_key?(run, &1)) do
        nil -> nil
        key -> {:error, {:raw_drift_payload_forbidden, key}}
      end
    end)
  end

  defp build_signals(runs) do
    runs
    |> comparable_fields()
    |> Enum.flat_map(&signal_for_field(&1, runs))
  end

  defp comparable_fields(runs) do
    runs
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.filter(&(&1 in @signal_classes))
  end

  defp signal_for_field(field, runs) do
    values = runs |> Enum.map(&fetch(&1, field)) |> Enum.uniq()

    if length(values) > 1 do
      [
        %DriftSignal{
          drift_signal_ref: "drift-signal://#{field}/#{hash(inspect(values))}",
          signal_class: field,
          magnitude_class: "changed_distinct_values_#{length(values)}",
          window_ref: window_ref(runs),
          context_refs: context_refs(runs)
        }
      ]
    else
      []
    end
  end

  defp window_ref(runs) do
    runs
    |> context_refs()
    |> Enum.join("|")
    |> hash()
    |> then(&("drift-window://" <> &1))
  end

  defp context_refs(runs) do
    runs
    |> Enum.map(&(fetch(&1, :run_ref) || fetch(&1, :trace_ref)))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  defp fetch(map, field), do: Map.get(map, field) || Map.get(map, Atom.to_string(field))
  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
