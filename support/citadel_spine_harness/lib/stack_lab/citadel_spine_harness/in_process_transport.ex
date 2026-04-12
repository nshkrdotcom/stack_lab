defmodule StackLab.CitadelSpineHarness.InProcessTransport do
  @moduledoc false

  @behaviour Citadel.JidoIntegrationBridge.Transport

  alias Jido.Integration.V2.BrainIngress
  alias Jido.Integration.V2.BrainInvocation
  alias StackLab.CitadelSpineHarness.TransportRuntime

  @impl true
  def submit_brain_invocation(%BrainInvocation{} = invocation) do
    config = TransportRuntime.fetch!()

    case BrainIngress.accept_invocation(
           invocation,
           submission_ledger: config.submission_ledger,
           submission_ledger_opts: config.submission_ledger_opts,
           scope_resolver: config.scope_resolver,
           scope_resolver_opts: config.scope_resolver_opts
         ) do
      {:ok, acceptance, gateway, runtime_inputs} ->
        notify(config.listener, %{
          result: :accepted,
          submission_key: invocation.submission_key,
          acceptance: acceptance,
          gateway: gateway,
          runtime_inputs: runtime_inputs
        })

        {:accepted, acceptance}

      {:error, rejection} ->
        notify(config.listener, %{
          result: :rejected,
          submission_key: invocation.submission_key,
          rejection: rejection
        })

        {:rejected, rejection}
    end
  end

  defp notify(listener, payload) when is_pid(listener) do
    send(listener, {:stack_lab_brain_ingress_result, payload})
  end

  defp notify(_listener, _payload), do: :ok
end
