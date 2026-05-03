defmodule StackLab.GnTen.ProofMatrix do
  @moduledoc """
  Narrow validator for the local gn-ten proof matrix ledger.

  The proof matrix is a reviewed evidence ledger. It prevents over-claiming by
  making missing proofs explicit and requiring implemented proofs to name a
  command, receipt, and does-not-prove boundary.
  """

  alias GroundPlane.Contracts.WorkspaceRef
  alias StackLab.GnTen.{Manifest, TextRules}

  @schema_version "gn_ten_proof_matrix_v1"
  @workspace_ref WorkspaceRef.new!("nshkrdotcom", "gn-ten").ref
  @branch_policy "main_only"
  @contract_families [
    "000 repo contracts",
    "100 development process",
    "200 refactoring",
    "300 architecture",
    "400 agent patterns",
    "500 governance",
    "600 deployment"
  ]
  @allowed_statuses ~w(implemented partial missing-proof not-applicable)
  @allowed_profiles ~w(local_quick local_full assembled_offline deployment_single_node)
  @trace_schema "aitrace.single_node_proof_trace.v1"
  @default_path Path.expand("../../../proof_matrix.yml", __DIR__)

  @type report :: %{
          schema_version: String.t() | nil,
          workspace_ref: String.t() | nil,
          branch_policy: String.t() | nil,
          contract_families: [String.t()],
          proof_count: non_neg_integer(),
          implemented_count: non_neg_integer(),
          partial_count: non_neg_integer(),
          missing_proof_count: non_neg_integer(),
          not_applicable_count: non_neg_integer(),
          highest_risk_missing_proof: String.t() | nil,
          proofs: [map()],
          failures: [map()]
        }

  @spec default_path() :: String.t()
  def default_path, do: @default_path

  @spec contract_families() :: [String.t()]
  def contract_families, do: @contract_families

  @spec validate(String.t(), String.t()) :: {:ok, report()} | {:error, report()}
  def validate(path \\ @default_path, manifest_path \\ Manifest.default_path()) do
    with {:ok, manifest} <- manifest(manifest_path),
         {:ok, content} <- read(path) do
      content
      |> parse()
      |> validate_ledger(manifest)
      |> result()
    end
  end

  defp manifest(path) do
    case Manifest.validate_file(path) do
      {:ok, manifest} -> {:ok, manifest}
      {:error, failures} -> {:error, manifest_report(failures)}
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, content} ->
        {:ok, content}

      {:error, :enoent} ->
        {:error, empty_report([failure("proof_matrix_missing")])}

      {:error, reason} ->
        {:error, empty_report([failure("proof_matrix_read_failed", reason: reason)])}
    end
  end

  defp parse(content) do
    %{
      schema_version: scalar(content, "schema_version"),
      workspace_ref: scalar(content, "workspace_ref"),
      branch_policy: scalar(content, "branch_policy"),
      contract_families: contract_family_list(content),
      proofs: proof_blocks(content) |> Enum.map(&proof/1)
    }
  end

  defp validate_ledger(ledger, manifest) do
    repo_names = MapSet.new(manifest.repos)
    family_set = MapSet.new(ledger.contract_families)

    failures =
      []
      |> validate_envelope(ledger)
      |> validate_family_catalog(ledger.contract_families)
      |> validate_proof_count(ledger.proofs)
      |> validate_unique_ids(ledger.proofs)
      |> validate_owners(ledger.proofs, repo_names)
      |> validate_families(ledger.proofs, family_set)
      |> validate_statuses(ledger.proofs)
      |> validate_profiles(ledger.proofs)
      |> validate_does_not_prove(ledger.proofs)
      |> validate_status_invariants(ledger.proofs)
      |> validate_trace_receipts(ledger.proofs)
      |> validate_family_coverage(ledger.proofs)

    %{
      schema_version: ledger.schema_version,
      workspace_ref: ledger.workspace_ref,
      branch_policy: ledger.branch_policy,
      contract_families: ledger.contract_families,
      proof_count: length(ledger.proofs),
      implemented_count: count_status(ledger.proofs, "implemented"),
      partial_count: count_status(ledger.proofs, "partial"),
      missing_proof_count: count_status(ledger.proofs, "missing-proof"),
      not_applicable_count: count_status(ledger.proofs, "not-applicable"),
      highest_risk_missing_proof: highest_risk_missing_proof(ledger.proofs),
      proofs: Enum.map(ledger.proofs, &safe_proof/1),
      failures: Enum.reverse(failures)
    }
  end

  defp result(%{failures: []} = report), do: {:ok, report}
  defp result(report), do: {:error, report}

  defp validate_envelope(failures, ledger) do
    failures
    |> require_equal("proof_bad_schema_version", ledger.schema_version, @schema_version)
    |> require_equal("proof_bad_workspace_ref", ledger.workspace_ref, @workspace_ref)
    |> require_equal("proof_bad_branch_policy", ledger.branch_policy, @branch_policy)
  end

  defp validate_family_catalog(failures, families) when families == @contract_families do
    failures
  end

  defp validate_family_catalog(failures, families) do
    missing = @contract_families -- families
    unknown = families -- @contract_families

    failures
    |> add_family_catalog_failures("proof_missing_contract_family", missing)
    |> add_family_catalog_failures("proof_unknown_contract_family", unknown)
  end

  defp validate_proof_count(failures, [_proof | _rest]), do: failures
  defp validate_proof_count(failures, []), do: [failure("proof_empty_matrix") | failures]

  defp validate_unique_ids(failures, proofs) do
    proofs
    |> Enum.frequencies_by(& &1.id)
    |> Enum.filter(fn {_id, count} -> count > 1 end)
    |> Enum.reduce(failures, fn {id, _count}, acc ->
      [failure("proof_duplicate_id", proof: id) | acc]
    end)
  end

  defp validate_owners(failures, proofs, repo_names) do
    Enum.reduce(proofs, failures, fn proof, acc ->
      if MapSet.member?(repo_names, proof.owner_repo) do
        acc
      else
        [failure("proof_unknown_owner_repo", proof: proof.id, repo: proof.owner_repo) | acc]
      end
    end)
  end

  defp validate_families(failures, proofs, family_set) do
    Enum.reduce(proofs, failures, fn proof, acc ->
      if proof.contract_family in @contract_families and
           MapSet.member?(family_set, proof.contract_family) do
        acc
      else
        [
          failure("proof_unknown_contract_family",
            proof: proof.id,
            contract_family: proof.contract_family
          )
          | acc
        ]
      end
    end)
  end

  defp validate_statuses(failures, proofs) do
    Enum.reduce(proofs, failures, fn proof, acc ->
      if proof.status in @allowed_statuses do
        acc
      else
        [failure("proof_unknown_status", proof: proof.id, status: proof.status) | acc]
      end
    end)
  end

  defp validate_profiles(failures, proofs) do
    Enum.reduce(proofs, failures, fn proof, acc ->
      if proof.profile in @allowed_profiles do
        acc
      else
        [failure("proof_unknown_profile", proof: proof.id, profile: proof.profile) | acc]
      end
    end)
  end

  defp validate_does_not_prove(failures, proofs) do
    Enum.reduce(proofs, failures, fn proof, acc ->
      if empty?(proof.does_not_prove) do
        [failure("proof_missing_does_not_prove", proof: proof.id) | acc]
      else
        acc
      end
    end)
  end

  defp validate_status_invariants(failures, proofs) do
    Enum.reduce(proofs, failures, fn proof, acc ->
      case proof.status do
        "implemented" -> validate_implemented(acc, proof)
        "partial" -> validate_partial(acc, proof)
        "missing-proof" -> validate_missing_proof(acc, proof)
        "not-applicable" -> validate_not_applicable(acc, proof)
        _other -> acc
      end
    end)
  end

  defp validate_implemented(failures, proof) do
    cond do
      empty?(proof.command) ->
        [failure("proof_missing_command", proof: proof.id) | failures]

      empty?(proof.receipt) ->
        [failure("proof_missing_receipt", proof: proof.id) | failures]

      empty?(proof.proves) ->
        [
          failure("proof_invalid_implemented_claim", proof: proof.id, missing: "proves")
          | failures
        ]

      fixture_required?(proof) and empty?(proof.fixture) ->
        [
          failure("proof_invalid_implemented_claim", proof: proof.id, missing: "fixture")
          | failures
        ]

      true ->
        failures
    end
  end

  defp validate_partial(failures, proof) do
    if Enum.all?([proof.command, proof.fixture, proof.receipt], &empty?/1) or
         empty?(proof.next_action) do
      [failure("proof_invalid_partial_claim", proof: proof.id) | failures]
    else
      failures
    end
  end

  defp validate_missing_proof(failures, proof) do
    if not empty?(proof.command) or not empty?(proof.receipt) or empty?(proof.next_action) do
      [failure("proof_invalid_missing_claim", proof: proof.id) | failures]
    else
      failures
    end
  end

  defp validate_not_applicable(failures, proof) do
    if not empty?(proof.command) or not empty?(proof.receipt) or empty?(proof.next_action) do
      [failure("proof_invalid_not_applicable_claim", proof: proof.id) | failures]
    else
      failures
    end
  end

  defp validate_family_coverage(failures, proofs) do
    covered = proofs |> Enum.map(& &1.contract_family) |> MapSet.new()

    @contract_families
    |> Enum.reject(&MapSet.member?(covered, &1))
    |> Enum.reduce(failures, fn family, acc ->
      [failure("proof_missing_contract_family", contract_family: family) | acc]
    end)
  end

  defp fixture_required?(%{profile: profile}) do
    profile in ~w(assembled_offline deployment_single_node)
  end

  defp add_family_catalog_failures(failures, code, families) do
    Enum.reduce(families, failures, fn family, acc ->
      [failure(code, contract_family: family) | acc]
    end)
  end

  defp count_status(proofs, status), do: Enum.count(proofs, &(&1.status == status))

  defp highest_risk_missing_proof(proofs) do
    proofs
    |> Enum.filter(&(&1.status == "missing-proof"))
    |> Enum.sort_by(&missing_risk_rank/1)
    |> List.first()
    |> case do
      nil -> nil
      proof -> proof.id
    end
  end

  defp missing_risk_rank(%{profile: "deployment_single_node"}), do: 0
  defp missing_risk_rank(%{profile: "assembled_offline"}), do: 1
  defp missing_risk_rank(%{profile: "local_full"}), do: 2
  defp missing_risk_rank(_proof), do: 3

  defp safe_proof(proof) do
    %{
      id: proof.id,
      owner_repo: proof.owner_repo,
      contract_family: proof.contract_family,
      status: proof.status,
      profile: proof.profile,
      command: proof.command,
      fixture: proof.fixture,
      receipt: proof.receipt,
      proves: proof.proves,
      does_not_prove: proof.does_not_prove,
      next_action: proof.next_action,
      trace_receipt: proof.trace_receipt
    }
  end

  defp proof_blocks(content) do
    TextRules.list_blocks(content, "id")
  end

  defp proof(block) do
    %{
      id: block_scalar(block, "id"),
      owner_repo: block_scalar(block, "owner_repo"),
      contract_family: block_scalar(block, "contract_family"),
      status: block_scalar(block, "status"),
      profile: block_scalar(block, "profile"),
      command: block_scalar(block, "command"),
      fixture: block_scalar(block, "fixture"),
      receipt: block_scalar(block, "receipt"),
      proves: block_list(block, "proves"),
      does_not_prove: block_list(block, "does_not_prove"),
      next_action: block_scalar(block, "next_action"),
      trace_receipt: trace_receipt(block)
    }
  end

  defp validate_trace_receipts(failures, proofs) do
    Enum.reduce(proofs, failures, fn proof, acc ->
      case proof.trace_receipt do
        nil -> acc
        trace_receipt -> validate_trace_receipt(acc, proof, trace_receipt)
      end
    end)
  end

  defp validate_trace_receipt(failures, proof, trace_receipt) do
    safe_posture? =
      get_in(trace_receipt, [:posture, :authoritative_audit?]) == "false" and
        get_in(trace_receipt, [:posture, :production_deployment_proven?]) == "false"

    valid? =
      trace_receipt.schema == @trace_schema and
        String.starts_with?(trace_receipt.ref || "", "trace://") and safe_posture?

    if valid? do
      failures
    else
      [failure("proof_invalid_trace_join", proof: proof.id) | failures]
    end
  end

  defp trace_receipt(block) do
    if String.contains?(block, "trace_receipt:") do
      %{
        schema: block_scalar(block, "schema"),
        ref: block_scalar(block, "ref"),
        posture: %{
          authoritative_audit?: block_scalar(block, "authoritative_audit?"),
          production_deployment_proven?: block_scalar(block, "production_deployment_proven?")
        }
      }
    end
  end

  defp contract_family_list(content) do
    TextRules.list_items_after(content, "contract_families")
  end

  defp scalar(content, key) do
    TextRules.scalar(content, key)
  end

  defp block_scalar(block, "id") do
    TextRules.block_scalar(block, "id")
  end

  defp block_scalar(block, key) do
    TextRules.block_scalar(block, key)
  end

  defp block_list(block, key) do
    TextRules.block_list(block, key)
  end

  defp empty?(nil), do: true
  defp empty?([]), do: true
  defp empty?(""), do: true
  defp empty?(_value), do: false

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected) do
    [failure(code, expected: expected, actual: actual) | failures]
  end

  defp manifest_report(failures) do
    empty_report([failure("proof_manifest_invalid", failures: failures)])
  end

  defp empty_report(failures) do
    %{
      schema_version: nil,
      workspace_ref: nil,
      branch_policy: nil,
      contract_families: [],
      proof_count: 0,
      implemented_count: 0,
      partial_count: 0,
      missing_proof_count: 0,
      not_applicable_count: 0,
      highest_risk_missing_proof: nil,
      proofs: [],
      failures: failures
    }
  end

  defp failure(code, fields \\ []) do
    fields
    |> Map.new()
    |> Map.put(:code, code)
  end
end
