defmodule StackLab.CitadelSpineHarness.OperationalObservabilityProof do
  @moduledoc false

  alias Citadel.ObservabilityContract.{
    CardinalityBounds,
    OperationalRunbook,
    OperationalSignal,
    OperationalSLO,
    OperatorSignalAdapter
  }

  @case_name :deterministic_run_health
  @scenario 43
  @signal_names OperationalSignal.signal_names()

  @spec run_case(:deterministic_run_health) :: {:ok, map()} | {:error, term()}
  def run_case(:deterministic_run_health) do
    proof = %{
      case: @case_name,
      scenario: @scenario,
      deterministic_run_evidence: deterministic_run_evidence(),
      operational_health: operational_health_evidence(),
      aitrace_boundary: %{
        replay_dependency?: false,
        audit_event_emitted?: false,
        replay_event_emitted?: false,
        purpose: :operator_health_not_audit_replay
      }
    }

    with :ok <- validate_proof(proof) do
      {:ok, proof}
    end
  end

  @spec validate_proof(map()) :: :ok | {:error, term()}
  def validate_proof(%{} = proof) do
    with :ok <- validate_deterministic_run(proof),
         :ok <- validate_operational_health(proof) do
      validate_aitrace_boundary(proof)
    end
  end

  def validate_proof(_proof), do: {:error, :invalid_operational_observability_proof}

  defp deterministic_run_evidence do
    %{
      run_ref: "deterministic-run://stack-lab/operational-observability/phase8",
      tenant_ref: "tenant://stack-lab/phase8-redacted",
      receipt_ref: "receipt://stack-lab/phase8/operator-health",
      receipt_contract: "DeterministicRunReceipt.v1",
      command_refs: [
        "mix test test/citadel/observability_contract/operational_signal_test.exs",
        "mix test support/citadel_spine_harness/test/operational_observability_proof_test.exs"
      ]
    }
  end

  defp operational_health_evidence do
    signals = Enum.map(@signal_names, &OperationalSignal.signal!/1)

    %{
      signal_contract: OperationalSignal.contract_name(),
      signal_refs: Enum.map(signals, &"operational-signal://#{&1.signal_name}"),
      backend_envelopes:
        Map.new(signals, &{&1.signal_name, OperatorSignalAdapter.backend_envelopes(&1)}),
      slo_threshold_refs:
        OperationalSLO.thresholds()
        |> Map.values()
        |> Enum.map(& &1.metric_ref),
      runbook_refs:
        OperationalRunbook.entries()
        |> Map.values()
        |> Enum.map(& &1.name),
      operator_visibility?: true
    }
  end

  defp validate_deterministic_run(%{deterministic_run_evidence: evidence}) do
    cond do
      not ref?(evidence.run_ref, "deterministic-run://") -> {:error, :missing_run_ref}
      not ref?(evidence.tenant_ref, "tenant://") -> {:error, :missing_tenant_ref}
      not ref?(evidence.receipt_ref, "receipt://") -> {:error, :missing_receipt_ref}
      evidence.command_refs == [] -> {:error, :missing_proof_commands}
      true -> :ok
    end
  end

  defp validate_deterministic_run(_proof), do: {:error, :missing_deterministic_run_evidence}

  defp validate_operational_health(%{operational_health: health}) do
    with :ok <- validate_signal_refs(health),
         :ok <- validate_backend_envelopes(health.backend_envelopes),
         :ok <- validate_slo_refs(health.slo_threshold_refs),
         :ok <- validate_runbook_refs(health.runbook_refs) do
      if health.operator_visibility? do
        :ok
      else
        {:error, :operator_visibility_missing}
      end
    end
  end

  defp validate_operational_health(_proof), do: {:error, :missing_operational_health_evidence}

  defp validate_signal_refs(%{signal_refs: refs}) when is_list(refs) do
    expected = Enum.map(@signal_names, &"operational-signal://#{&1}")

    if Enum.sort(refs) == Enum.sort(expected) do
      :ok
    else
      {:error, :missing_operational_signal_ref}
    end
  end

  defp validate_signal_refs(_health), do: {:error, :missing_operational_signal_refs}

  defp validate_backend_envelopes(envelopes) when is_map(envelopes) do
    Enum.reduce_while(@signal_names, :ok, fn name, :ok ->
      case Map.fetch(envelopes, name) do
        {:ok, envelope} -> envelope |> validate_backend_envelope() |> continue_or_halt()
        :error -> {:halt, {:error, {:missing_backend_envelope, name}}}
      end
    end)
  end

  defp validate_backend_envelopes(_envelopes), do: {:error, :invalid_backend_envelopes}

  defp validate_backend_envelope(%{
         telemetry: %{metadata: metadata},
         metric: %{labels: labels},
         log: %{fields: log_fields},
         trace: %{attributes: trace_attributes}
       }) do
    with :ok <- CardinalityBounds.validate_metric_labels(Map.keys(metadata)),
         :ok <- CardinalityBounds.validate_metric_labels(Map.keys(labels)),
         true <- OperationalSignal.redaction_safe?(log_fields),
         true <- OperationalSignal.redaction_safe?(trace_attributes) do
      :ok
    else
      false -> {:error, :raw_operational_payload}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_backend_envelope(_envelope), do: {:error, :invalid_backend_envelope}

  defp validate_slo_refs(refs) when is_list(refs) do
    required =
      OperationalSLO.thresholds()
      |> Map.values()
      |> Enum.map(& &1.metric_ref)
      |> Enum.sort()

    if Enum.sort(refs) == required, do: :ok, else: {:error, :missing_slo_ref}
  end

  defp validate_slo_refs(_refs), do: {:error, :invalid_slo_refs}

  defp validate_runbook_refs(refs) when is_list(refs) do
    required =
      OperationalRunbook.entry_names()
      |> Enum.sort()

    if Enum.sort(refs) == required, do: :ok, else: {:error, :missing_runbook_ref}
  end

  defp validate_runbook_refs(_refs), do: {:error, :invalid_runbook_refs}

  defp validate_aitrace_boundary(%{
         aitrace_boundary: %{
           replay_dependency?: false,
           audit_event_emitted?: false,
           replay_event_emitted?: false
         }
       }) do
    :ok
  end

  defp validate_aitrace_boundary(_proof), do: {:error, :aitrace_boundary_not_separate}

  defp continue_or_halt(:ok), do: {:cont, :ok}
  defp continue_or_halt({:error, reason}), do: {:halt, {:error, reason}}

  defp ref?(value, prefix) when is_binary(value), do: String.starts_with?(value, prefix)
  defp ref?(_value, _prefix), do: false
end
