defmodule StackLab.CitadelSpineHarness.TransportRuntime do
  @moduledoc false

  @key {__MODULE__, :config}

  @spec put!(map()) :: :ok
  def put!(config) when is_map(config) do
    :persistent_term.put(@key, config)
    :ok
  end

  @spec fetch!() :: map()
  def fetch! do
    case :persistent_term.get(@key, :missing) do
      :missing ->
        raise ArgumentError, "stack_lab citadel spine transport runtime is not configured"

      config ->
        config
    end
  end

  @spec reset!() :: :ok
  def reset! do
    :persistent_term.erase(@key)
    :ok
  end
end
