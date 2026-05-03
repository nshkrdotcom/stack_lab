defmodule StackLab.CitadelSpineHarness.InProcessInvocationDownstream do
  @moduledoc false

  @behaviour Citadel.InvocationBridge.Downstream

  alias Citadel.ExecutionIntentEnvelope.V2, as: ExecutionIntentEnvelopeV2
  alias Citadel.JidoIntegrationBridge.InvocationDownstream
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionRejection
  alias StackLab.CitadelSpineHarness.InProcessTransport

  @impl true
  @spec submit_execution_intent(ExecutionIntentEnvelopeV2.t()) ::
          {:accepted, SubmissionAcceptance.t()}
          | {:rejected, SubmissionRejection.t()}
          | {:error, atom()}
  def submit_execution_intent(%ExecutionIntentEnvelopeV2{} = envelope) do
    InvocationDownstream.submit_execution_intent(envelope, transport_module: InProcessTransport)
  end
end

defmodule StackLab.CitadelSpineHarness.RemoteInvocationDownstream do
  @moduledoc false

  @behaviour Citadel.InvocationBridge.Downstream

  alias Citadel.ExecutionIntentEnvelope.V2, as: ExecutionIntentEnvelopeV2
  alias Citadel.JidoIntegrationBridge.InvocationDownstream
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionRejection
  alias StackLab.CitadelSpineHarness.RemoteTransport

  @impl true
  @spec submit_execution_intent(ExecutionIntentEnvelopeV2.t()) ::
          {:accepted, SubmissionAcceptance.t()}
          | {:rejected, SubmissionRejection.t()}
          | {:error, atom()}
  def submit_execution_intent(%ExecutionIntentEnvelopeV2{} = envelope) do
    InvocationDownstream.submit_execution_intent(envelope, transport_module: RemoteTransport)
  end
end
