defmodule StackLab.CitadelSpineHarness.RemoteTransport do
  @moduledoc false

  @behaviour Citadel.JidoIntegrationBridge.Transport

  alias Jido.Integration.V2.BrainIngress
  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionRejection
  alias StackLab.CitadelSpineHarness.Timing
  alias StackLab.CitadelSpineHarness.TransportRuntime

  @impl true
  def submit_brain_invocation(%BrainInvocation{} = invocation) do
    config = TransportRuntime.fetch!()
    maybe_delay(config)

    case remote_accept(
           config.remote_node,
           invocation,
           config.brain_ingress_opts,
           config.timeout_ms
         ) do
      {:ok, %SubmissionAcceptance{} = acceptance, gateway, runtime_inputs} ->
        duplicate_acceptance = maybe_deliver_twice(config, invocation)

        send_result(config.listener, %{
          result: :accepted,
          acceptance: acceptance,
          gateway: gateway,
          runtime_inputs: runtime_inputs,
          submission_key: acceptance.submission_key,
          duplicate_acceptance: duplicate_acceptance,
          remote_node: config.remote_node
        })

        {:accepted, acceptance}

      {:error, %SubmissionRejection{} = rejection} ->
        send_result(config.listener, %{
          result: :rejected,
          rejection: rejection,
          submission_key: rejection.submission_key,
          remote_node: config.remote_node
        })

        {:rejected, rejection}

      {:transport_error, reason} ->
        send_result(config.listener, %{
          result: :error,
          reason: reason,
          remote_node: config.remote_node
        })

        {:error, reason}
    end
  end

  defp remote_accept(remote_node, invocation, opts, timeout_ms) do
    :erpc.call(remote_node, BrainIngress, :accept_invocation, [invocation, opts], timeout_ms)
  rescue
    ErlangError ->
      {:transport_error, :transport_unreachable}
  catch
    :exit, _reason ->
      {:transport_error, :transport_unreachable}
  end

  defp maybe_delay(%{delay_ms: delay_ms}) when is_integer(delay_ms) and delay_ms > 0 do
    Timing.delay(:remote_transport_probe_delay, delay_ms)
  end

  defp maybe_delay(_config), do: :ok

  defp maybe_deliver_twice(%{deliver_twice?: true} = config, %BrainInvocation{} = invocation) do
    case remote_accept(
           config.remote_node,
           invocation,
           config.brain_ingress_opts,
           config.timeout_ms
         ) do
      {:ok, %SubmissionAcceptance{} = acceptance, _gateway, _runtime_inputs} -> acceptance
      _other -> nil
    end
  end

  defp maybe_deliver_twice(_config, _invocation), do: nil

  defp send_result(listener, payload) when is_pid(listener) do
    send(listener, {:stack_lab_brain_ingress_result, payload})
  end
end
