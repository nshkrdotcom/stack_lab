defmodule StackLab.CitadelSpineHarness.LowerGatewayStub do
  @moduledoc false

  @behaviour Mezzanine.LowerGateway

  alias Mezzanine.RuntimeProfile
  alias Mezzanine.RuntimeProfileStore
  alias StackLab.AppEnvSandbox

  @listener_key :stack_lab_lower_gateway_listener
  @handlers_key :stack_lab_lower_gateway_handlers

  @spec with_handlers(map(), (-> result)) :: result when result: var
  def with_handlers(handlers, fun) when is_map(handlers) and is_function(fun, 0) do
    previous_profile = install_runtime_profile()
    previous_listener = Process.get(@listener_key)
    previous_handlers = Process.get(@handlers_key)

    drain_gateway_messages()

    AppEnvSandbox.with_env(
      [{:put, :mezzanine_execution_engine, :lower_gateway_impl, __MODULE__}],
      fn ->
        Process.put(@listener_key, self())
        Process.put(@handlers_key, handlers)

        try do
          fun.()
        after
          drain_gateway_messages()
          restore_process_value(@listener_key, previous_listener)
          restore_process_value(@handlers_key, previous_handlers)
          restore_runtime_profile(previous_profile)
        end
      end
    )
  end

  @impl true
  def dispatch(claim) do
    reply(:dispatch, [claim], {:error, {:unexpected_lower_gateway_call, :dispatch}})
  end

  @impl true
  def lookup_submission(submission_dedupe_key, tenant_id) do
    reply(:lookup_submission, [submission_dedupe_key, tenant_id], :never_seen)
  end

  @impl true
  def fetch_execution_outcome(execution_lookup, tenant_id) do
    reply(
      :fetch_execution_outcome,
      [execution_lookup, tenant_id],
      {:error, {:unexpected_lower_gateway_call, :fetch_execution_outcome}}
    )
  end

  @impl true
  def request_cancel(submission_ref, tenant_id, reason) do
    reply(
      :request_cancel,
      [submission_ref, tenant_id, reason],
      {:error, {:unexpected_lower_gateway_call, :request_cancel}}
    )
  end

  defp reply(operation, args, fallback) do
    if listener = Process.get(@listener_key) do
      send(listener, {:stack_lab_lower_gateway, operation, args})
    end

    case Process.get(@handlers_key, %{}) do
      %{^operation => handler} when is_function(handler, 1) -> handler.(args)
      _other -> fallback
    end
  end

  defp install_runtime_profile do
    profile =
      RuntimeProfileStore.profile()
      |> RuntimeProfile.put(:mezzanine_execution_engine, :lower_gateway_impl, __MODULE__)

    case RuntimeProfileStore.replace_profile(profile) do
      {:ok, previous_profile} -> {:ok, previous_profile}
      {:error, :not_running} -> :not_running
    end
  end

  defp restore_runtime_profile({:ok, previous_profile}) do
    _ = RuntimeProfileStore.replace_profile(previous_profile)
    :ok
  end

  defp restore_runtime_profile(:not_running), do: :ok

  defp restore_process_value(key, nil), do: Process.delete(key)
  defp restore_process_value(key, value), do: Process.put(key, value)

  defp drain_gateway_messages do
    receive do
      {:stack_lab_lower_gateway, _operation, _args} ->
        drain_gateway_messages()
    after
      0 -> :ok
    end
  end
end
