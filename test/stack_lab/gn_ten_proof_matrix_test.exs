defmodule StackLab.GnTen.ProofMatrixTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.ProofMatrix

  test "reports a missing proof matrix" do
    path = Path.join(System.tmp_dir!(), "missing_proof_matrix.yml")
    File.rm(path)

    assert {:error, report} = ProofMatrix.validate(path)
    assert [%{code: "proof_matrix_missing"}] = report.failures
  end

  test "rejects duplicate proof ids" do
    path = matrix_path!(duplicate?: true)

    assert {:error, report} = ProofMatrix.validate(path)
    assert failure_code?(report, "proof_duplicate_id")
  end

  test "rejects unknown owner repos" do
    path = matrix_path!(proof_overrides: %{owner_repo: "unknown_repo"})

    assert {:error, report} = ProofMatrix.validate(path)
    assert failure_code?(report, "proof_unknown_owner_repo")
  end

  test "rejects unknown contract families" do
    path = matrix_path!(proof_overrides: %{contract_family: "999 unknown"})

    assert {:error, report} = ProofMatrix.validate(path)
    assert failure_code?(report, "proof_unknown_contract_family")
  end

  test "rejects implemented proofs without commands" do
    path = matrix_path!(proof_overrides: %{command: "null"})

    assert {:error, report} = ProofMatrix.validate(path)
    assert failure_code?(report, "proof_missing_command")
  end

  test "rejects implemented proofs without receipts" do
    path = matrix_path!(proof_overrides: %{receipt: "null"})

    assert {:error, report} = ProofMatrix.validate(path)
    assert failure_code?(report, "proof_missing_receipt")
  end

  test "rejects missing-proof entries that claim commands" do
    path =
      matrix_path!(
        proof_id: "refactoring_deletion_backlog",
        proof_overrides: %{command: "mix ci"}
      )

    assert {:error, report} = ProofMatrix.validate(path)
    assert failure_code?(report, "proof_invalid_missing_claim")
  end

  test "rejects missing contract family coverage" do
    path = matrix_path!(drop_family: "600 deployment")

    assert {:error, report} = ProofMatrix.validate(path)
    assert failure_code?(report, "proof_missing_contract_family")
  end

  test "rejects trace receipts with unsafe posture" do
    path =
      matrix_path!(
        proof_overrides: %{
          trace_receipt: %{
            schema: "aitrace.single_node_proof_trace.v1",
            ref: "trace://stack_lab/local_quick/latest",
            authoritative_audit?: "true",
            production_deployment_proven?: "false"
          }
        }
      )

    assert {:error, report} = ProofMatrix.validate(path)
    assert failure_code?(report, "proof_invalid_trace_join")
  end

  test "validates the checked-in proof matrix ledger" do
    assert {:ok, report} = ProofMatrix.validate()
    assert report.schema_version == "gn_ten_proof_matrix_v1"
    assert report.workspace_ref == "workspace://nshkrdotcom/gn-ten"
    assert report.branch_policy == "main_only"
    assert report.proof_count == 8
    assert report.implemented_count == 4
    assert report.missing_proof_count == 4
    assert report.highest_risk_missing_proof == "single_node_deployment_rehearsal"
  end

  defp failure_code?(report, code) do
    Enum.any?(report.failures, &(&1.code == code))
  end

  defp matrix_path!(opts) do
    root = Path.join(System.tmp_dir!(), "stack_lab_proofs_#{System.unique_integer([:positive])}")
    File.rm_rf!(root)
    File.mkdir_p!(root)
    path = Path.join(root, "proof_matrix.yml")
    File.write!(path, matrix(opts))
    path
  end

  defp matrix(opts) do
    proof_id = Keyword.get(opts, :proof_id, "repo_agent_instruction_drift")
    overrides = Keyword.get(opts, :proof_overrides, %{})
    drop_family = Keyword.get(opts, :drop_family)

    proofs =
      base_proofs()
      |> Enum.reject(&(&1.contract_family == drop_family))
      |> Enum.map(fn proof ->
        if proof.id == proof_id, do: Map.merge(proof, overrides), else: proof
      end)

    proofs =
      if Keyword.get(opts, :duplicate?, false) do
        [List.first(proofs) | proofs]
      else
        proofs
      end

    """
    schema_version: gn_ten_proof_matrix_v1
    workspace_ref: workspace://nshkrdotcom/gn-ten
    branch_policy: main_only

    contract_families:
      - "000 repo contracts"
      - "100 development process"
      - "200 refactoring"
      - "300 architecture"
      - "400 agent patterns"
      - "500 governance"
      - "600 deployment"

    proofs:
    #{Enum.map_join(proofs, "\n", &proof_yaml/1)}
    """
  end

  defp proof_yaml(proof) do
    """
      - id: #{proof.id}
        owner_repo: #{proof.owner_repo}
        contract_family: "#{proof.contract_family}"
        status: #{proof.status}
        profile: #{proof.profile}
        command: #{proof.command}
        fixture: #{proof.fixture}
        receipt: #{proof.receipt}
        proves:
    #{Enum.map_join(proof.proves, "\n", &"      - #{&1}")}
        does_not_prove:
    #{Enum.map_join(proof.does_not_prove, "\n", &"      - #{&1}")}
        next_action: #{proof.next_action}
    #{trace_receipt_yaml(Map.get(proof, :trace_receipt))}
    """
  end

  defp trace_receipt_yaml(nil), do: ""

  defp trace_receipt_yaml(trace_receipt) do
    """
        trace_receipt:
          schema: #{Map.fetch!(trace_receipt, :schema)}
          ref: #{Map.fetch!(trace_receipt, :ref)}
          posture:
            authoritative_audit?: #{Map.fetch!(trace_receipt, :authoritative_audit?)}
            production_deployment_proven?: #{Map.fetch!(trace_receipt, :production_deployment_proven?)}
    """
  end

  defp base_proofs do
    [
      %{
        id: "repo_agent_instruction_drift",
        owner_repo: "stack_lab",
        contract_family: "000 repo contracts",
        status: "implemented",
        profile: "local_quick",
        command: "mix gn_ten.repo_agents.validate",
        fixture: "repo_agent_instructions/",
        receipt: "receipt://stack_lab/repo_agent_instruction_drift/latest",
        proves: ["repo agent instructions match reviewed drafts"],
        does_not_prove: ["future instruction edits"],
        next_action: "keep validator in mix ci"
      },
      %{
        id: "stack_lab_development_loop",
        owner_repo: "stack_lab",
        contract_family: "100 development process",
        status: "implemented",
        profile: "local_full",
        command: "mix ci",
        fixture: "support/lab_core",
        receipt: "receipt://stack_lab/mix_ci/latest",
        proves: ["local StackLab CI composes"],
        does_not_prove: ["deployment behavior"],
        next_action: "add batch receipts"
      },
      missing("refactoring_deletion_backlog", "200 refactoring"),
      %{
        id: "contract_artifact_ledger",
        owner_repo: "stack_lab",
        contract_family: "300 architecture",
        status: "implemented",
        profile: "local_quick",
        command: "mix gn_ten.artifacts.validate",
        fixture: "contract_artifacts.yml",
        receipt: "receipt://stack_lab/contract_artifact_ledger/latest",
        proves: ["artifact producers and consumers resolve"],
        does_not_prove: ["package publishing"],
        next_action: "add batch receipts"
      },
      missing("agent_turn_runtime_patterns", "400 agent patterns"),
      missing("governed_connector_export_fixture", "500 governance"),
      missing("single_node_deployment_rehearsal", "600 deployment")
    ]
  end

  defp missing(id, family) do
    %{
      id: id,
      owner_repo: "stack_lab",
      contract_family: family,
      status: "missing-proof",
      profile: "local_quick",
      command: "null",
      fixture: "null",
      receipt: "null",
      proves: [],
      does_not_prove: ["#{family} is proven"],
      next_action: "add the smallest proof for #{family}"
    }
  end
end
