defmodule StackLab.Examples.SynapseProductAcceptance do
  @moduledoc """
  External product acceptance proof for the Synapse rewrite.
  """

  alias StackLab.NoBypassScanner

  @schema_version "stack_lab.synapse_product_acceptance.v1"
  @default_synapse_root "/home/home/p/g/n/synapse"
  @target_code_paths ["apps/synapse_core/lib", "apps/synapse_web/lib"]
  @run_token "stacklab-synapse-proof"

  @scan_rules [
    direct_provider_sdk_calls: ["ReqLLM", "OpenAI", "Anthropic", "Claude", "Gemini", "Codex"],
    direct_generated_sdk_calls: ["Jido.", "Jido.Integration"],
    direct_runtime_mutation: [
      "Citadel.",
      "ExecutionPlane",
      "Mezzanine.Execution",
      "Mezzanine.Runtime",
      "Mezzanine.Workflow"
    ],
    direct_db_access: ["Ecto.Repo", ".Repo", "Repo."],
    direct_trace_writes: ["AITrace", "TraceCollector", "TraceWriter"],
    direct_env_auth_lookup: ["System.get_env(", "System.fetch_env!("]
  ]

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    synapse_root = Keyword.get(opts, :synapse_root, @default_synapse_root)

    with {:ok, bootstrap} <- prove_bootstrap(),
         {:ok, run_start} <- prove_run_start(),
         {:ok, turn_submission} <- prove_turn_submission(run_start),
         {:ok, review_decision} <- prove_review_decision(),
         {:ok, memory_context} <- prove_memory_context(),
         {:ok, denial_path} <- prove_denial_path(),
         {:ok, evidence} <- prove_evidence(),
         {:ok, teams_arbitration} <- prove_teams_arbitration(),
         {:ok, no_bypass} <- prove_no_bypass(synapse_root) do
      {:ok,
       %{
         "schema_version" => @schema_version,
         "status" => "pass",
         "product_repo" => "synapse",
         "product_path" => synapse_root,
         "stack_lab_role" => "external_product_acceptance",
         "classification" => "fixture_backed_product_acceptance",
         "proofs" => %{
           "bootstrap" => bootstrap,
           "run_start" => run_start,
           "turn_submission" => turn_submission,
           "review_decision" => review_decision,
           "memory_context" => memory_context,
           "denial_path" => denial_path,
           "evidence" => evidence,
           "teams_arbitration" => teams_arbitration,
           "cross_tenant" => cross_tenant_status()
         },
         "no_bypass" => no_bypass,
         "not_proven" => [
           "live_provider_behavior",
           "multi_tenant_persisted_data_rejection",
           "production_deployment"
         ]
       }}
    end
  end

  defp prove_bootstrap do
    status = Synapse.ProductBootstrap.fixture_status()

    if status.status == :fixture_backed and status.surface == "AppKit.InstallationSurface" do
      {:ok,
       %{
         "status" => "pass",
         "feature_status" => "fixture_backed",
         "surface" => status.surface,
         "pack_slug" => status.pack_slug,
         "pack_version" => status.pack_version
       }}
    else
      {:error, {:bootstrap_unexpected_status, status}}
    end
  end

  defp prove_run_start do
    attrs = %{
      "title" => "StackLab Synapse acceptance",
      "goal_summary" => "Prove the product path enters through AppKit."
    }

    case Synapse.AgentRuns.start_run(attrs, run_token: @run_token) do
      {:ok, run} when run.state == :accepted and run.surface == "AppKit.AgentIntake" ->
        {:ok,
         %{
           "status" => "pass",
           "feature_status" => "fixture_backed",
           "surface" => run.surface,
           "run_ref" => run.ref,
           "evidence_refs" => run.evidence_refs
         }}

      other ->
        {:error, {:run_start_failed, other}}
    end
  end

  defp prove_turn_submission(run_start) do
    attrs = %{"kind" => "user_input", "input_summary" => "StackLab proof turn"}

    case Synapse.Turns.submit_turn(run_start["run_ref"], attrs) do
      {:ok, result} when result.accepted? == true ->
        {:ok,
         %{
           "status" => Atom.to_string(result.status),
           "feature_status" => "fixture_backed",
           "command_kind" => Atom.to_string(result.command_kind),
           "command_ref" => result.command_ref,
           "receipt_ref" => result.receipt_ref
         }}

      other ->
        {:error, {:turn_submission_failed, other}}
    end
  end

  defp prove_review_decision do
    attrs = %{"decision" => "accept", "reason" => "stack_lab_product_acceptance"}

    case Synapse.Reviews.record_decision("fixture-review", attrs) do
      {:ok, result} when result.status == :accepted ->
        {:ok,
         %{
           "status" => Atom.to_string(result.status),
           "feature_status" => "fixture_backed",
           "message" => result.message,
           "decision_id" => result.metadata.decision_id
         }}

      other ->
        {:error, {:review_decision_failed, other}}
    end
  end

  defp prove_memory_context do
    memories = Synapse.Memory.list_memories()

    with true <- memory_states_present?(memories),
         {:ok, context_pack} <- Synapse.ContextPacks.get_context_pack("phase-3") do
      {:ok,
       %{
         "status" => "pass",
         "feature_status" => "fixture_backed",
         "memory_states" => memory_states(memories),
         "context_pack_ref" => context_pack.ref,
         "included_count" => length(context_pack.included),
         "denied_count" => length(context_pack.denied),
         "stale_count" => length(context_pack.stale),
         "revoked_count" => length(context_pack.revoked),
         "candidate_count" => length(context_pack.candidates)
       }}
    else
      false -> {:error, {:memory_states_missing, memory_states(memories)}}
      other -> {:error, {:context_pack_failed, other}}
    end
  end

  defp prove_denial_path do
    with {:ok, eligibility} <- Synapse.Catalog.get_eligibility("external-write-tool"),
         true <- eligibility.item.status == :denied,
         {:error, {:raw_memory_payload_forbidden, :body}} <-
           Synapse.Memory.write_feedback(%{body: "raw forbidden payload"}),
         {:error, :invalid_turn_kind} <-
           Synapse.Turns.submit_turn("phase-3", %{"kind" => "unsafe_kind"}) do
      {:ok,
       %{
         "status" => "pass",
         "denied_catalog_item" => eligibility.item.id,
         "reason_codes" => eligibility.item.reason_codes,
         "raw_memory_payload_rejected" => true,
         "invalid_turn_kind_rejected" => true
       }}
    else
      other -> {:error, {:denial_path_failed, other}}
    end
  end

  defp prove_evidence do
    evidence = Synapse.Evidence.list_evidence()
    available = Enum.filter(evidence, &(&1.status == "available"))
    missing = Enum.filter(evidence, &(&1.status == "missing"))

    with [%{receipt_ref: receipt_ref} | _rest] <- available,
         {:ok, receipt} <- Synapse.Evidence.get_receipt(receipt_ref),
         operations when operations.status == :fixture_backed <- Synapse.Evidence.operations() do
      {:ok,
       %{
         "status" => "pass",
         "feature_status" => "fixture_backed",
         "available_evidence_count" => length(available),
         "missing_evidence_count" => length(missing),
         "receipt_ref" => receipt.receipt.receipt_ref,
         "operations_status" => Atom.to_string(operations.status)
       }}
    else
      other -> {:error, {:evidence_failed, other}}
    end
  end

  defp prove_teams_arbitration do
    with {:ok, team} <- Synapse.Teams.get_team("fixture-team"),
         {:ok, session} <- Synapse.Arbitration.get_session("phase-7") do
      {:ok,
       %{
         "status" => "pass",
         "feature_status" => "fixture_backed",
         "team_ref" => team.ref,
         "team_control_status" => Atom.to_string(team.control_status.status),
         "arbitration_ref" => session.ref,
         "arbitration_state" => Atom.to_string(session.state)
       }}
    else
      other -> {:error, {:teams_arbitration_failed, other}}
    end
  end

  defp prove_no_bypass(synapse_root) do
    files = source_files(synapse_root)
    signals = source_signals(files)

    attrs = %{
      owner_repo: "synapse",
      package_path: "apps/synapse_core",
      target_code_paths: Enum.map(@target_code_paths, &Path.join(synapse_root, &1)),
      approved_facade_refs: ["AppKit"],
      proof_refs: ["stacklab://synapse-product-acceptance"],
      scanner_refs: ["stack-lab.product-no-bypass-scanner.v1"],
      signals: signals
    }

    with {:ok, receipt} <- NoBypassScanner.scan(attrs),
         true <- receipt.status == :pass do
      {:ok,
       %{
         "status" => Atom.to_string(receipt.status),
         "receipt_ref" => receipt.receipt_ref,
         "scanner_ref" => receipt.scanner_ref,
         "checked_rules" => Enum.map(receipt.checked_rules, &Atom.to_string/1),
         "target_code_paths" => receipt.target_code_paths,
         "approved_facade_refs" => receipt.approved_facade_refs,
         "appkit_reference_count" => appkit_reference_count(files),
         "allowed_authoring_contract_refs" => allowed_authoring_contract_refs(files)
       }}
    else
      false -> {:error, {:no_bypass_open_defect, signals}}
      other -> {:error, {:no_bypass_failed, other}}
    end
  end

  defp cross_tenant_status do
    %{
      "status" => "not_applicable",
      "reason" => "fixture_single_tenant_no_persisted_cross_tenant_surface",
      "release_claim" => "not_proven"
    }
  end

  defp memory_states_present?(memories) do
    required = [:included, :denied, :stale, :revoked, :candidate]
    states = Enum.map(memories, & &1.state)
    Enum.all?(required, &(&1 in states))
  end

  defp memory_states(memories) do
    memories
    |> Enum.map(& &1.state)
    |> Enum.uniq()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.sort()
  end

  defp source_files(synapse_root) do
    @target_code_paths
    |> Enum.flat_map(fn path ->
      Path.wildcard(Path.join([synapse_root, path, "**", "*.ex"]))
    end)
    |> Enum.map(fn path -> {path, File.read!(path)} end)
  end

  defp source_signals(files) do
    @scan_rules
    |> Enum.map(fn {rule, tokens} ->
      {rule, forbidden_occurrences(files, tokens)}
    end)
    |> Enum.reject(fn {_rule, occurrences} -> occurrences == [] end)
    |> Map.new()
  end

  defp forbidden_occurrences(files, tokens) do
    Enum.flat_map(files, fn {path, content} ->
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_number} ->
        tokens
        |> Enum.filter(&forbidden_token_present?(line, &1))
        |> Enum.map(&occurrence(path, line_number, &1))
      end)
    end)
  end

  defp forbidden_token_present?(line, "Jido."), do: String.contains?(line, "Jido.")
  defp forbidden_token_present?(line, token), do: String.contains?(line, token)

  defp occurrence(path, line_number, token), do: "#{path}:#{line_number}:#{token}"

  defp appkit_reference_count(files) do
    files
    |> Enum.flat_map(fn {_path, content} -> String.split(content, "\n") end)
    |> Enum.count(&String.contains?(&1, "AppKit."))
  end

  defp allowed_authoring_contract_refs(files) do
    files
    |> Enum.flat_map(fn {path, content} ->
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _line_number} -> String.contains?(line, "Mezzanine.Pack") end)
      |> Enum.map(fn {_line, line_number} -> "#{path}:#{line_number}:Mezzanine.Pack" end)
    end)
  end
end
