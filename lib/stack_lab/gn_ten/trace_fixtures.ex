defmodule StackLab.GnTen.TraceFixtures do
  @moduledoc """
  Deterministic gn-ten proof trace fixtures for local StackLab review.

  These are development evidence fixtures. They are not audit records and do
  not claim deployment proof.
  """

  alias StackLab.GnTen.Manifest

  @schema_version "aitrace.single_node_proof_trace.v1"
  @workspace_ref "workspace://nshkrdotcom/gn-ten"
  @node_ref "node://single-node/local-beam"
  @proof_class "single_node_beam_development"
  @allowed_profiles ~w(local_quick local_full assembled_offline deployment_single_node)
  @required_spans ~w(
    workspace_manifest_validated
    repo_local_ci
    stack_lab_proof
    trace_exported
  )
  @denied_keys ~w(raw_prompt provider_payload workflow_history secret api_key token)

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec build(atom() | String.t(), keyword()) :: {:ok, map()} | {:error, [map()]}
  def build(profile, opts \\ []) do
    profile = normalize_profile(profile)

    if profile in @allowed_profiles do
      {:ok, trace(profile, opts)}
    else
      {:error, [failure("trace_unknown_profile", profile: profile)]}
    end
  end

  @spec build!(atom() | String.t(), keyword()) :: map()
  def build!(profile, opts \\ []) do
    case build(profile, opts) do
      {:ok, trace} -> trace
      {:error, failures} -> raise ArgumentError, "invalid trace fixture: #{inspect(failures)}"
    end
  end

  @spec validate_export(map()) :: :ok | {:error, [map()]}
  def validate_export(trace) when is_map(trace) do
    failures =
      []
      |> require_equal("trace_bad_schema", trace["schema_version"], @schema_version)
      |> validate_profile(trace["profile"])
      |> validate_required_spans(trace["spans"])
      |> validate_posture(trace["proof_posture"])
      |> validate_denied_keys(trace)

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  def validate_export(_trace), do: {:error, [failure("trace_invalid_export")]}

  defp trace(profile, opts) do
    %{
      "schema_version" => @schema_version,
      "proof_class" => @proof_class,
      "profile" => profile,
      "trace_id" => "trace://stack_lab/#{profile}/latest",
      "workspace_ref" => @workspace_ref,
      "node_ref" => @node_ref,
      "batch_ref" => Keyword.get(opts, :batch_ref, "batch://gn-ten/#{profile}"),
      "repo_refs" => repo_refs(),
      "spans" => spans(profile),
      "proof_posture" => proof_posture(),
      "evidence_requirements" => [
        "repo_local_ci_receipts",
        "stack_lab_proof_matrix_entry",
        "trace_export_receipt"
      ],
      "not_proven" => [
        "production_deployment",
        "multi_node_failover",
        "authoritative_audit_chain",
        "compliance_export"
      ]
    }
  end

  defp spans(profile) do
    base_spans() ++ profile_spans(profile)
  end

  defp base_spans do
    [
      span("workspace_manifest_validated", "mix gn_ten.validate"),
      span("repo_local_ci", "repo-local CI receipts"),
      span("stack_lab_proof", "mix gn_ten.proofs.validate"),
      span("trace_exported", "mix gn_ten.trace.export")
    ]
  end

  defp profile_spans("local_quick") do
    [
      span("repo_agents_validate", "mix gn_ten.repo_agents.validate"),
      span("artifacts_validate", "mix gn_ten.artifacts.validate"),
      span("proofs_validate", "mix gn_ten.proofs.validate")
    ]
  end

  defp profile_spans("local_full") do
    profile_spans("local_quick") ++
      [
        span("stack_lab_ci", "mix ci")
      ]
  end

  defp profile_spans("assembled_offline") do
    profile_spans("local_full") ++
      [
        span("assembled_fixture", "StackLab assembled offline fixture")
      ]
  end

  defp profile_spans("deployment_single_node") do
    profile_spans("assembled_offline") ++
      [
        span("deploy_rehearsal", "single-node deploy rehearsal"),
        span("restore_rehearsal", "single-node restore rehearsal")
      ]
  end

  defp span(name, evidence_ref) do
    %{
      "name" => name,
      "status" => "pass",
      "attributes" => %{
        "workspace_ref" => @workspace_ref,
        "repo_ref" => "repo://nshkrdotcom/stack_lab",
        "evidence_ref" => evidence_ref
      }
    }
  end

  defp proof_posture do
    %{
      "authoritative_audit?" => false,
      "production_deployment_proven?" => false,
      "safe_action" => "use_as_development_trace_fixture"
    }
  end

  defp repo_refs do
    Enum.map(Manifest.expected_repos(), &"repo://nshkrdotcom/#{&1}")
  end

  defp validate_profile(failures, profile) when profile in @allowed_profiles, do: failures

  defp validate_profile(failures, profile) do
    [failure("trace_unknown_profile", profile: profile) | failures]
  end

  defp validate_required_spans(failures, spans) when is_list(spans) do
    present = spans |> Enum.map(& &1["name"]) |> MapSet.new()

    @required_spans
    |> Enum.reject(&MapSet.member?(present, &1))
    |> case do
      [] -> failures
      missing -> [failure("trace_missing_required_span", spans: missing) | failures]
    end
  end

  defp validate_required_spans(failures, _spans) do
    [failure("trace_missing_required_span", spans: @required_spans) | failures]
  end

  defp validate_posture(failures, %{} = posture) do
    safe? =
      posture["authoritative_audit?"] == false and
        posture["production_deployment_proven?"] == false and
        posture["safe_action"] == "use_as_development_trace_fixture"

    if safe?, do: failures, else: [failure("trace_bad_posture", posture: posture) | failures]
  end

  defp validate_posture(failures, posture) do
    [failure("trace_bad_posture", posture: posture) | failures]
  end

  defp validate_denied_keys(failures, trace) do
    trace
    |> denied_paths([])
    |> Enum.reduce(failures, fn path, acc ->
      [failure("trace_public_denied_key", path: path) | acc]
    end)
  end

  defp denied_paths(%{} = map, path) do
    Enum.flat_map(map, fn {key, value} ->
      child_path = path ++ [to_string(key)]

      if to_string(key) in @denied_keys do
        [Enum.join(child_path, ".")]
      else
        denied_paths(value, child_path)
      end
    end)
  end

  defp denied_paths(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} ->
      denied_paths(value, path ++ [Integer.to_string(index)])
    end)
  end

  defp denied_paths(_value, _path), do: []

  defp normalize_profile(profile) when is_atom(profile), do: Atom.to_string(profile)
  defp normalize_profile(profile) when is_binary(profile), do: profile
  defp normalize_profile(profile), do: inspect(profile)

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected) do
    [failure(code, expected: expected, actual: actual) | failures]
  end

  defp failure(code, fields \\ []) do
    fields
    |> Map.new()
    |> Map.put(:code, code)
  end
end
