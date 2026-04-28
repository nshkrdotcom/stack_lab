defmodule StackLab.GnTen.ContractArtifactsTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.ContractArtifacts

  test "reports a missing artifact ledger" do
    path = Path.join(System.tmp_dir!(), "missing_contract_artifacts.yml")
    File.rm(path)

    assert {:error, report} = ContractArtifacts.validate(path)
    assert [%{code: "artifact_ledger_missing"}] = report.failures
  end

  test "rejects an unknown producer" do
    path = ledger_path!(producer_repo: "unknown_repo")

    assert {:error, report} = ContractArtifacts.validate(path)
    assert failure_code?(report, "artifact_unknown_producer")
  end

  test "rejects an unknown consumer" do
    path = ledger_path!(consumers: ["missing_consumer"])

    assert {:error, report} = ContractArtifacts.validate(path)
    assert failure_code?(report, "artifact_unknown_consumer")
  end

  test "rejects duplicate artifact names" do
    path = ledger_path!(duplicate?: true)

    assert {:error, report} = ContractArtifacts.validate(path)
    assert failure_code?(report, "artifact_duplicate_name")
  end

  test "rejects non-main source refs" do
    path = ledger_path!(source_ref: "feature/test")

    assert {:error, report} = ContractArtifacts.validate(path)
    assert failure_code?(report, "artifact_bad_source_ref")
  end

  test "rejects malformed artifact refs" do
    path = ledger_path!(artifact_ref: "artifact://nshkrdotcom/wrong/stack_lab_gn_ten_manifest")

    assert {:error, report} = ContractArtifacts.validate(path)
    assert failure_code?(report, "artifact_bad_ref")
  end

  test "rejects deprecated artifacts that still list consumers" do
    path = ledger_path!(status: "deprecated", successor: "new_stack_lab_gn_ten_manifest")

    assert {:error, report} = ContractArtifacts.validate(path)
    assert failure_code?(report, "artifact_deprecated_consumers_remain")
  end

  test "reports bootstrap stale source sha as a warning" do
    path = ledger_path!(source_sha: String.duplicate("0", 40))

    assert {:ok, report} = ContractArtifacts.validate(path)
    assert warning_code?(report, "artifact_source_sha_stale")
    assert report.stale_count == 1
  end

  test "rejects projected stale source sha" do
    path = ledger_path!(source_sha: String.duplicate("0", 40), status: "projected")

    assert {:error, report} = ContractArtifacts.validate(path)
    assert failure_code?(report, "artifact_source_sha_stale")
  end

  test "does not check proposed artifact source sha drift" do
    path = ledger_path!(source_sha: String.duplicate("0", 40), status: "proposed")

    assert {:ok, report} = ContractArtifacts.validate(path)
    refute warning_code?(report, "artifact_source_sha_stale")
    assert report.stale_count == 0
  end

  test "validates the checked-in bootstrap ledger" do
    assert {:ok, report} = ContractArtifacts.validate()
    assert report.schema_version == "gn_ten_contract_artifacts_v1"
    assert report.workspace_ref == "workspace://nshkrdotcom/gn-ten"
    assert report.branch_policy == "main_only"
    assert report.artifact_count == 12

    artifact_names = MapSet.new(Enum.map(report.artifacts, & &1.name))

    assert MapSet.subset?(
             MapSet.new(~w(
               ground_plane_contracts
               execution_plane
               jido_integration_contracts
               citadel_domain_surface
               authority_contract
               outer_brain_contracts
               mezzanine_core
               app_kit_core
               stack_lab_lab_core
               aitrace
             )),
             artifact_names
           )
  end

  defp failure_code?(report, code) do
    Enum.any?(report.failures, &(&1.code == code))
  end

  defp warning_code?(report, code) do
    Enum.any?(report.warnings, &(&1.code == code))
  end

  defp ledger_path!(overrides) do
    root =
      Path.join(System.tmp_dir!(), "stack_lab_artifacts_#{System.unique_integer([:positive])}")

    File.rm_rf!(root)
    File.mkdir_p!(root)
    path = Path.join(root, "contract_artifacts.yml")
    File.write!(path, ledger(overrides))
    path
  end

  defp ledger(overrides) do
    artifact = %{
      name: Keyword.get(overrides, :name, "stack_lab_gn_ten_manifest"),
      producer_repo: Keyword.get(overrides, :producer_repo, "stack_lab"),
      source_ref: Keyword.get(overrides, :source_ref, "main"),
      source_sha: Keyword.get(overrides, :source_sha, stack_lab_sha()),
      consumers: Keyword.get(overrides, :consumers, ["app_kit"]),
      status: Keyword.get(overrides, :status, "bootstrap"),
      artifact_ref:
        Keyword.get(
          overrides,
          :artifact_ref,
          "artifact://nshkrdotcom/#{Keyword.get(overrides, :producer_repo, "stack_lab")}/#{Keyword.get(overrides, :name, "stack_lab_gn_ten_manifest")}"
        ),
      successor: Keyword.get(overrides, :successor)
    }

    artifacts = [artifact]

    artifacts =
      if Keyword.get(overrides, :duplicate?, false) do
        [artifact | artifacts]
      else
        artifacts
      end

    """
    schema_version: gn_ten_contract_artifacts_v1
    workspace_ref: workspace://nshkrdotcom/gn-ten
    branch_policy: main_only

    artifacts:
    #{Enum.map_join(artifacts, "\n", &artifact_yaml/1)}
    """
  end

  defp artifact_yaml(artifact) do
    """
      - name: #{artifact.name}
        artifact_ref: #{artifact.artifact_ref}
        producer_repo: #{artifact.producer_repo}
        producer_repo_ref: repo://nshkrdotcom/#{artifact.producer_repo}
        producer_path: /home/home/p/g/n/#{artifact.producer_repo}
        source_ref: #{artifact.source_ref}
        source_sha: #{artifact.source_sha}
        build_command: cd /home/home/p/g/n/#{artifact.producer_repo} && mix ci
        status: #{artifact.status}
    #{successor_yaml(artifact.successor)}
        consumers:
    #{Enum.map_join(artifact.consumers, "\n", &"      - #{&1}")}
        notes: test ledger
    """
  end

  defp successor_yaml(nil), do: ""
  defp successor_yaml(successor), do: "    successor: #{successor}"

  defp stack_lab_sha do
    {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: File.cwd!())
    String.trim(sha)
  end
end
