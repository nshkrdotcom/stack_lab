defmodule StackLab.NoBypassScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.NoBypassScanner
  alias StackLab.NoBypassScanner.Receipt

  test "emits passing receipts when product surfaces use approved facades" do
    assert {:ok, %Receipt{} = receipt} =
             NoBypassScanner.scan(valid_attrs())

    assert receipt.status == :pass
    assert receipt.fixture_ref == "AOC-044"
    assert receipt.owner_repo == "extravaganza"
    assert receipt.findings == []
  end

  test "reports direct GEPA, TRINITY, provider, env auth, runtime, DB, and trace bypasses" do
    attrs =
      valid_attrs(
        signals: %{
          direct_gepa_framework_calls: ["GepaFramework.Runner.run"],
          direct_trinity_framework_calls: ["TrinityFramework.Router.route"],
          direct_provider_sdk_calls: ["Anthropic.Messages.create"],
          direct_generated_sdk_calls: ["GitHubEx.Client.request"],
          direct_env_auth_lookup: ["ANTHROPIC_API_KEY"],
          direct_runtime_mutation: ["Mezzanine.Execution.Repo.update_all"],
          direct_db_access: ["Repo.all"],
          direct_trace_writes: ["AITrace.Event.new"]
        }
      )

    assert {:ok, %Receipt{status: :open_defect, findings: findings}} =
             NoBypassScanner.scan(attrs)

    assert Enum.map(findings, & &1.rule) == [
             :direct_gepa_framework_calls,
             :direct_trinity_framework_calls,
             :direct_provider_sdk_calls,
             :direct_generated_sdk_calls,
             :direct_env_auth_lookup,
             :direct_runtime_mutation,
             :direct_db_access,
             :direct_trace_writes
           ]
  end

  test "rejects unknown no-bypass rules" do
    assert {:error, {:unknown_no_bypass_rules, [:pattern_scan]}} =
             NoBypassScanner.scan(valid_attrs(rules: [:direct_provider_sdk_calls, :pattern_scan]))
  end

  defp valid_attrs(overrides \\ []) do
    attrs = %{
      owner_repo: "extravaganza",
      package_path: "apps/extravaganza_core",
      target_code_paths: ["apps/extravaganza_core/lib/extravaganza/headless_surface.ex"],
      approved_facade_refs: [
        "app-kit-adaptive-control-surface://tenant-1/adaptive",
        "app-kit-headless-surface://tenant-1/headless",
        "app-kit-authority-projection://tenant-1/headless"
      ],
      proof_refs: ["proof://stack-lab/no-bypass/1"],
      scanner_refs: ["scanner://stack-lab/no-bypass/1"],
      signals: %{}
    }

    Map.merge(attrs, Map.new(overrides))
  end
end
