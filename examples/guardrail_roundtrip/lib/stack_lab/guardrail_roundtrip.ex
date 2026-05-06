defmodule StackLab.GuardrailRoundtrip do
  @moduledoc """
  Prompt and guardrail proof roundtrip.
  """

  alias AppKit.{GuardrailSurface, PromptSurface}
  alias OuterBrain.{GuardrailEngine, PromptFabric}

  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(attrs) when is_map(attrs) do
    prompt_content = Map.get(attrs, :prompt_content, "safe prompt")
    payload = Map.get(attrs, :payload, prompt_content)

    with {:ok, store, prompt_ref} <-
           PromptFabric.author(PromptFabric.new(), prompt_attrs(attrs), prompt_content),
         {:ok, prompt_projection} <-
           PromptFabric.project(
             store,
             Map.merge(prompt_attrs(attrs), %{revision: prompt_ref.revision})
           ),
         {:ok, prompt_surface} <-
           PromptSurface.view_projection(Map.put(prompt_projection, :prompt_ref, prompt_ref)),
         {:ok, decision} <-
           GuardrailEngine.evaluate(:input_prompt, payload, guard_attrs(attrs, prompt_ref)),
         guard_projection = GuardrailEngine.project(decision),
         {:ok, guard_surface} <-
           GuardrailSurface.decision_projection(%{
             decision_ref: decision_ref(decision),
             decision: decision
           }) do
      {:ok,
       %{
         receipt_ref: "guardrail-roundtrip://#{hash(decision.trace_ref)}",
         fixture_refs: [
           "PROMPT-001",
           "PROMPT-009",
           "GUARD-001",
           "GUARD-002",
           "GUARD-010",
           "GUARD-014"
         ],
         prompt_projection: prompt_surface,
         guard_projection: guard_projection,
         guard_surface: guard_surface,
         status: status(decision)
       }}
    end
  end

  defp prompt_attrs(attrs) do
    %{
      tenant_ref: Map.get(attrs, :tenant_ref, "tenant://a"),
      authority_ref: Map.get(attrs, :authority_ref, "authority://a"),
      installation_ref: Map.get(attrs, :installation_ref, "installation://a"),
      idempotency_key: Map.get(attrs, :idempotency_key, "idem-guardrail-roundtrip"),
      trace_ref: Map.get(attrs, :trace_ref, "trace://guardrail-roundtrip"),
      prompt_id: Map.get(attrs, :prompt_id, "prompt://guardrail-roundtrip"),
      redaction_policy_ref: Map.get(attrs, :redaction_policy_ref, "redaction://prompt"),
      decision_evidence_ref: Map.get(attrs, :decision_evidence_ref, "decision://prompt-author")
    }
  end

  defp guard_attrs(attrs, prompt_ref) do
    %{
      tenant_ref: Map.get(attrs, :tenant_ref, "tenant://a"),
      authority_ref: Map.get(attrs, :authority_ref, "authority://a"),
      installation_ref: Map.get(attrs, :installation_ref, "installation://a"),
      idempotency_key: Map.get(attrs, :idempotency_key, "idem-guardrail-roundtrip"),
      trace_ref: Map.get(attrs, :trace_ref, "trace://guardrail-roundtrip"),
      prompt_ref: Map.from_struct(prompt_ref),
      detector_chain_ref: Map.get(attrs, :detector_chain_ref, "guard-chain://roundtrip"),
      detector_chain: Map.get(attrs, :detector_chain, [:schema_shape_reference, :pii_reference])
    }
  end

  defp status(%{decision_class: :allow}), do: :pass
  defp status(%{decision_class: :allow_with_redaction}), do: :redacted
  defp status(_decision), do: :rejected

  defp decision_ref(decision),
    do: "guard-decision://#{hash(decision.trace_ref <> Atom.to_string(decision.decision_class))}"

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
