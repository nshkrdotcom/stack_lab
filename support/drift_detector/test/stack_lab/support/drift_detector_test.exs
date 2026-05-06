defmodule StackLab.Support.DriftDetectorTest do
  use ExUnit.Case, async: true

  alias StackLab.Support.DriftDetector

  test "detects deterministic bounded drift signals" do
    assert {:ok, [signal]} =
             DriftDetector.detect([
               run("run-1", guard_decision_drift: "allow"),
               run("run-2", guard_decision_drift: "block")
             ])

    assert signal.signal_class == :guard_decision_drift
    refute Map.has_key?(DriftDetector.project(signal), :payload)
  end

  test "rejects cross-tenant windows, unbounded windows, raw payloads, and class drift" do
    assert {:error, :cross_tenant_drift_comparison_forbidden} =
             DriftDetector.detect([
               run("run-1"),
               Map.put(run("run-2"), :tenant_ref, "tenant://b")
             ])

    assert {:error, :drift_window_unbounded} =
             DriftDetector.detect(List.duplicate(run("run"), 101))

    assert {:error, {:raw_drift_payload_forbidden, :model_output}} =
             DriftDetector.detect([Map.put(run("run-1"), :model_output, "raw")])

    assert :free_form not in DriftDetector.signal_classes()
  end

  defp run(run_ref, overrides \\ []) do
    Map.merge(
      %{
        run_ref: run_ref,
        trace_ref: "trace://#{run_ref}",
        tenant_ref: "tenant://a",
        installation_ref: "installation://a",
        prompt_drift: "same",
        guard_decision_drift: "allow"
      },
      Map.new(overrides)
    )
  end
end
