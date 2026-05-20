defmodule StackLab.StructuralGate.Zones do
  @moduledoc """
  Structural scanner zone classification.
  """

  @excluded_segments [".git", "_build", "deps", "dist", "node_modules"]
  @doc_segments ["doc", "docs"]
  @fixture_segments ["fixture", "fixtures", "test", "tests", "test_support"]
  @demo_segments ["example", "examples", "demo", "demos"]
  @scanner_segments [
    "scanner",
    "scanners",
    "no_bypass_scanner",
    "connector_hardening_scanner",
    "ai_run_lineage_scanner",
    "tenant_isolation_scanner",
    "model_inference_scanner",
    "memory_fabric_scanner",
    "cost_budget_scanner",
    "optimization_fabric_scanner",
    "persistence_matrix_scanner",
    "coordination_fabric_scanner",
    "adaptive_control_scanner"
  ]
  @receipt_trace_segments [
    "receipt",
    "receipts",
    "trace",
    "traces",
    "replay",
    "replay_engine",
    "replay_contracts",
    "evidence"
  ]

  @spec classify(String.t(), String.t()) :: atom()
  def classify(repo, path) do
    segments = path_segments(path)
    basename = Path.basename(path)

    static_zone(segments, basename) ||
      repo_special_zone(repo, segments) ||
      repo_zone(repo, segments)
  end

  @spec excluded_path?(String.t()) :: boolean()
  def excluded_path?(path), do: any_segment?(path_segments(path), @excluded_segments)

  @spec integration_bridge_root?(String.t()) :: boolean()
  def integration_bridge_root?(path) do
    segments = path_segments(path)

    contains_ordered_segments?(segments, ["mezzanine", "bridges", "integration_bridge", "lib"]) and
      not adapter_path?(segments)
  end

  @spec canonical_provider_classification_path?(String.t()) :: boolean()
  def canonical_provider_classification_path?(path) do
    String.ends_with?(
      path,
      "/jido_integration/core/provider_classification/lib/jido/integration/v2/provider_classification.ex"
    )
  end

  @spec closed_provider_dispatch_scan_path?(map()) :: boolean()
  def closed_provider_dispatch_scan_path?(%{
        repo: "jido_integration",
        zone: :other_project_code,
        path: path
      }) do
    not jido_provider_vocabulary_data_owner?(path)
  end

  def closed_provider_dispatch_scan_path?(_checked_path), do: false

  @spec provider_public_vocabulary_allowed_path?(String.t()) :: boolean()
  def provider_public_vocabulary_allowed_path?(path) do
    allowed_fragments = [
      "/app_kit/core/authority_projections/",
      "/app_kit/core/cost_surface/",
      "/app_kit/core/coordination_surface/",
      "/app_kit/core/headless_surface/",
      "/app_kit/lib/app_kit/workspace/",
      "/app_kit/web/cost_dashboard/",
      "/citadel/core/authority_contract/",
      "/citadel/core/connector_binding/",
      "/citadel/core/native_auth_assertion/",
      "/citadel/core/provider_auth_fabric/",
      "/execution_plane/core/execution_plane/conformance/execution_plane_testkit/",
      "/execution_plane/core/execution_plane/core/execution_plane_contracts/",
      "/jido_integration/core/auth/",
      "/jido_integration/core/connector_registry/",
      "/jido_integration/core/contracts/",
      "/jido_integration/core/model_provider_registry/",
      "/jido_integration/core/platform/lib/jido/integration/v2/deterministic_lower_lane.ex",
      "/jido_integration/core/provider_classification/",
      "/jido_integration/core/provider_feature_matrix/",
      "/jido_integration/core/tool_contracts/",
      "/mezzanine/bridges/integration_bridge/lib/mezzanine/integration_bridge/provider_authority_admission.ex",
      "/mezzanine/core/coordination_engine/",
      "/mezzanine/core/cost_attribution_engine/",
      "/mezzanine/core/headless_coding_ops/",
      "/mezzanine/core/m1_m2_runtime/",
      "/mezzanine/core/projection_engine/",
      "/mezzanine/core/workflow_runtime/",
      "/mezzanine/core/workspace_build_model/",
      "/outer_brain/core/ai_artifact_contracts/",
      "/stack_lab/support/citadel_spine_harness/"
    ]

    Enum.any?(allowed_fragments, &String.contains?(path, &1))
  end

  defp static_zone(segments, basename) do
    cond do
      any_segment?(segments, @excluded_segments) ->
        :generated_excluded

      any_segment?(segments, @doc_segments) or String.ends_with?(basename, ".md") ->
        :docs

      any_segment?(segments, @fixture_segments) ->
        :fixtures_tests

      any_segment?(segments, @demo_segments) ->
        :demo

      any_segment?(segments, @scanner_segments) ->
        :scanner

      any_segment?(segments, @receipt_trace_segments) ->
        :receipt_trace

      true ->
        nil
    end
  end

  defp repo_special_zone(repo, segments) do
    cond do
      repo == "extravaganza" ->
        :product

      repo == "jido_integration" and Enum.member?(segments, "connectors") ->
        :connector

      repo == "mezzanine" and adapter_path?(segments) ->
        :adapter

      repo == "AITrace" ->
        :receipt_trace

      true ->
        nil
    end
  end

  defp repo_zone("app_kit", segments),
    do: if(Enum.member?(segments, "core"), do: :generic, else: :other_project_code)

  defp repo_zone("mezzanine", segments),
    do: if(Enum.member?(segments, "core"), do: :generic, else: :other_project_code)

  defp repo_zone("ground_plane", segments),
    do: if(Enum.member?(segments, "core"), do: :ground_plane, else: :other_project_code)

  defp repo_zone("citadel", segments) do
    if citadel_generic_policy_path?(segments), do: :generic_policy, else: :other_project_code
  end

  defp repo_zone(_repo, _segments), do: :other_project_code

  defp adapter_path?(segments) do
    Enum.member?(segments, "provider_adapters") or
      contains_ordered_segments?(segments, ["bridges", "integration_bridge", "provider_adapters"])
  end

  defp citadel_generic_policy_path?(segments) do
    contains_ordered_segments?(segments, ["core", "policy_packs"]) or
      contains_ordered_segments?(segments, ["core", "authority_contract"]) or
      contains_ordered_segments?(segments, ["core", "execution_governance_contract"]) or
      contains_ordered_segments?(segments, ["core", "citadel_kernel"])
  end

  defp jido_provider_vocabulary_data_owner?(path) do
    allowed_fragments = [
      "/jido_integration/core/provider_classification/",
      "/jido_integration/core/provider_feature_matrix/",
      "/jido_integration/core/tool_contracts/"
    ]

    Enum.any?(allowed_fragments, &String.contains?(path, &1))
  end

  defp contains_ordered_segments?(segments, wanted) do
    segments
    |> Enum.chunk_every(length(wanted), 1, :discard)
    |> Enum.any?(&(&1 == wanted))
  end

  defp any_segment?(segments, wanted), do: Enum.any?(wanted, &Enum.member?(segments, &1))

  defp path_segments(path) do
    path
    |> Path.expand()
    |> Path.split()
  end
end
