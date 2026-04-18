defmodule StackLab.CitadelSpineHarness.RemoteSpine do
  @moduledoc false

  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.Storage, as: StoreLocalStorage
  alias Jido.Integration.V2.StoreLocal.SubmissionLedger

  @spec ping() :: :ok
  def ping, do: :ok

  @spec configure_store_local!(String.t()) :: :ok
  def configure_store_local!(storage_dir) when is_binary(storage_dir) do
    stop_store_local()
    File.rm_rf!(storage_dir)
    File.mkdir_p!(storage_dir)
    :ok = StoreLocal.configure_defaults!(storage_dir: storage_dir)
    _ = Application.ensure_all_started(:telemetry)
    _ = Application.ensure_all_started(:jido_integration_v2_store_local)
    :ok = StoreLocal.reset!()
  end

  @spec cleanup_store_local(String.t()) :: :ok
  def cleanup_store_local(storage_dir) when is_binary(storage_dir) do
    stop_store_local()
    File.rm_rf!(storage_dir)
    :ok
  end

  @spec fetch_acceptance(String.t()) :: {:ok, term()} | :error
  def fetch_acceptance(submission_key) when is_binary(submission_key) do
    SubmissionLedger.fetch_acceptance(submission_key, [])
  end

  @spec fetch_rejection(String.t()) :: term()
  def fetch_rejection(submission_key) when is_binary(submission_key) do
    StoreLocalStorage.read(fn state ->
      Map.get(state.submission_rejections, submission_key)
    end)
  end

  @spec rejection_keys() :: [String.t()]
  def rejection_keys do
    StoreLocalStorage.read(fn state ->
      state.submission_rejections
      |> Map.keys()
      |> Enum.sort()
    end)
  end

  defp stop_store_local do
    case Application.stop(:jido_integration_v2_store_local) do
      :ok ->
        :ok

      {:error, {:not_started, :jido_integration_v2_store_local}} ->
        :ok

      {:error, {:not_started, _other_app}} ->
        :ok

      {:error, reason} ->
        raise "unable to stop remote store_local application: #{inspect(reason)}"
    end
  end
end
