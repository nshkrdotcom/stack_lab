defmodule StackLab.Examples.EnvRemediationHarnessTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.EnvRemediationHarness
  alias StackLab.Examples.EnvRemediationHarness.Finding
  alias StackLab.Examples.EnvRemediationHarness.PhaseReceipt
  alias StackLab.GnTenControlPlane
  alias StackLab.SpecCell

  test "scan_text records fixed env tokens without source excerpts" do
    findings =
      EnvRemediationHarness.scan_text(
        "lib/example.ex",
        "System.get_env(\"OPENAI_API_KEY\")\n:ok\nApplication.get_env(:owner, :token)",
        owner_repo: "extravaganza"
      )

    assert [
             %Finding{
               owner_repo: "extravaganza",
               path: "lib/example.ex",
               line: 1,
               token: :system_get_env
             },
             %Finding{
               owner_repo: "extravaganza",
               path: "lib/example.ex",
               line: 1,
               token: :api_key
             },
             %Finding{
               owner_repo: "extravaganza",
               path: "lib/example.ex",
               line: 1,
               token: :openai_api_key
             },
             %Finding{
               owner_repo: "extravaganza",
               path: "lib/example.ex",
               line: 3,
               token: :application_get_env
             }
           ] = findings
  end

  test "classification and production class are bounded" do
    [finding] = EnvRemediationHarness.scan_text("lib/example.ex", "System.get_env(name)")

    assert {:ok, %Finding{classification: :approved_boot_boundary}} =
             EnvRemediationHarness.classify(
               finding,
               :approved_boot_boundary,
               :standalone_auth
             )

    assert {:error, :unknown_classification} =
             EnvRemediationHarness.classify(finding, :native_login, :standalone_auth)

    assert {:error, :unknown_production_class} =
             EnvRemediationHarness.classify(
               finding,
               :approved_boot_boundary,
               :operator_secret
             )
  end

  test "unresolved governed hot-path findings block release" do
    [finding] = EnvRemediationHarness.scan_text("lib/example.ex", "System.get_env(name)")

    assert EnvRemediationHarness.release_blocking?(finding)

    assert {:ok, classified} =
             EnvRemediationHarness.classify(finding, :governed_hot_path_fix, :governed_auth)

    assert EnvRemediationHarness.governed_hot_path?(classified)
    assert EnvRemediationHarness.release_blocking?(classified)

    assert {:ok, remediated} =
             EnvRemediationHarness.classify(
               finding,
               :approved_boot_boundary,
               :standalone_auth
             )

    refute EnvRemediationHarness.release_blocking?(remediated)
  end

  test "redacted receipts omit source line text and raw values" do
    findings =
      EnvRemediationHarness.scan_text(
        "lib/example.ex",
        "System.get_env(\"OPENAI_API_KEY\")",
        owner_repo: "extravaganza"
      )

    finding = Enum.find(findings, &(&1.token == :system_get_env))

    assert {:ok, classified} =
             EnvRemediationHarness.classify(
               finding,
               :approved_boot_boundary,
               :standalone_auth
             )

    receipt =
      classified
      |> EnvRemediationHarness.attach_receipt(
        proof_command: "mix test test/extravaganza/env_test.exs",
        receipt_path: "docs/receipts/env/extravaganza.json"
      )
      |> EnvRemediationHarness.redacted_receipt()

    refute Map.has_key?(receipt, :source_text)
    refute Map.has_key?(receipt, :raw_value)
    assert receipt.token == :system_get_env
    assert receipt.proof_command == "mix test test/extravaganza/env_test.exs"
  end

  test "creates SpecCell and gn-ten receipt records for env phases" do
    cell =
      EnvRemediationHarness.spec_cell("extravaganza",
        requirement_id: "ENV-01",
        acceptance_fixture: "UAA-029",
        target_code_paths: ["/home/home/p/g/n/extravaganza"],
        proof_command: "mix test test/extravaganza/env_test.exs"
      )

    assert %SpecCell{} = cell
    refute SpecCell.complete?(cell)

    receipt = EnvRemediationHarness.receipt(cell, requirement_id: "ENV-01", state: "missing")

    assert %GnTenControlPlane{} = receipt
    assert GnTenControlPlane.release_blocking?(receipt)
  end

  test "records bounded phase command and closeout receipts" do
    kinds = [
      :env_scan,
      :redaction_scan,
      :pattern_engine_free_scan,
      :atom_source_scan,
      :repo_qc
    ]

    receipts =
      Enum.map(kinds, fn kind ->
        assert {:ok, %PhaseReceipt{} = receipt} =
                 EnvRemediationHarness.phase_receipt(
                   "extravaganza",
                   "ENV-01",
                   kind,
                   :pass,
                   proof_command: "mix test",
                   receipt_path: "implementation_docset/phase_notes/runs/env_01.md"
                 )

        receipt
      end)

    assert Enum.all?(receipts, &(not EnvRemediationHarness.release_blocking_receipt?(&1)))

    assert {:ok, pushed} =
             EnvRemediationHarness.phase_receipt(
               "extravaganza",
               "ENV-01",
               :commit_push,
               :pushed,
               commit_sha: "0123456789abcdef",
               remote: "origin/main"
             )

    pushed_receipt = EnvRemediationHarness.redacted_phase_receipt(pushed)
    assert pushed_receipt.commit_sha == "0123456789abcdef"
    assert pushed_receipt.remote == "origin/main"
    refute Map.has_key?(pushed_receipt, :raw_value)

    assert {:ok, open} =
             EnvRemediationHarness.phase_receipt(
               "extravaganza",
               "ENV-01",
               :open_defect_continue,
               :open_defect,
               open_defect: :missing_local_dependency
             )

    assert EnvRemediationHarness.release_blocking_receipt?(open)

    assert EnvRemediationHarness.redacted_phase_receipt(open).open_defect ==
             :missing_local_dependency
  end

  test "rejects unknown phase receipt kinds and states" do
    assert {:error, :unknown_receipt_kind} =
             EnvRemediationHarness.phase_receipt(
               "extravaganza",
               "ENV-01",
               :runtime_secret,
               :pass
             )

    assert {:error, :unknown_receipt_state} =
             EnvRemediationHarness.phase_receipt(
               "extravaganza",
               "ENV-01",
               :repo_qc,
               :ignored
             )
  end
end
