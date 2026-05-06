defmodule StackLab.TenantIsolationScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.TenantIsolationScanner
  alias StackLab.TenantIsolationScanner.Receipt

  test "emits passing receipts for tenant-scoped projection and trace facts" do
    assert {:ok, %Receipt{} = receipt} =
             TenantIsolationScanner.scan(valid_attrs())

    assert receipt.status == :pass
    assert receipt.fixture_ref == "UAA-041"
    assert receipt.owner_repo == "app_kit"
    assert receipt.findings == []
    assert receipt.required_refs == TenantIsolationScanner.required_refs()
  end

  test "reports missing tenant and cross-tenant findings without leaking values" do
    attrs =
      valid_attrs(
        facts: [
          %{kind: :product_projection, tenant_ref: nil, ref: "projection://tenant-1/run/1"},
          %{
            kind: :trace,
            tenant_ref: "tenant://tenant-2",
            ref: "trace://tenant-2/run/9",
            secret: "secret-value"
          }
        ]
      )

    assert {:ok, %Receipt{status: :open_defect, findings: findings}} =
             TenantIsolationScanner.scan(attrs)

    assert Enum.any?(findings, &(&1.reason == :missing_tenant_ref))
    assert Enum.any?(findings, &(&1.reason == :cross_tenant_ref))
    refute String.contains?(inspect(findings), "secret-value")
  end

  test "rejects unknown tenant-sensitive fact kinds" do
    assert {:error, {:unknown_tenant_fact_kinds, [:raw_sql_dump]}} =
             TenantIsolationScanner.scan(valid_attrs(facts: [%{kind: :raw_sql_dump}]))
  end

  defp valid_attrs(overrides \\ []) do
    attrs = %{
      tenant_ref: "tenant://tenant-1",
      owner_repo: "app_kit",
      package_path: "core/authority_projections",
      target_code_paths: ["core/authority_projections/lib/app_kit/authority_projections.ex"],
      facts: [
        %{
          kind: :product_projection,
          tenant_ref: "tenant://tenant-1",
          ref: "projection://tenant-1/run/1"
        },
        %{kind: :trace, tenant_ref: "tenant://tenant-1", ref: "trace://tenant-1/run/1"},
        %{
          kind: :credential_lease,
          tenant_ref: "tenant://tenant-1",
          ref: "credential-lease://tenant-1/lease-1"
        }
      ],
      proof_refs: ["proof://stack-lab/tenant-isolation/1"],
      scanner_refs: ["scanner://stack-lab/tenant-isolation/1"]
    }

    Map.merge(attrs, Map.new(overrides))
  end
end
