defmodule StackLab.GnTen.TenantScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.TenantScanner

  test "detects unscoped Repo calls" do
    root =
      source_root!("bad_query", """
      defmodule BadQuery do
        @tenant_scoped true

        def all do
          Repo.all(Thing)
        end
      end
      """)

    assert {:error, report} = TenantScanner.scan(root: root, mode: :query)
    assert [%{code: "tenant_unscoped_query"}] = report.violations
  end

  test "allows scoped Repo calls" do
    root =
      source_root!("good_query", """
      defmodule GoodQuery do
        @tenant_scoped true

        def all(tenant_id) do
          Repo.all(from thing in Thing, where: thing.tenant_id == ^tenant_id)
        end
      end
      """)

    assert {:ok, report} = TenantScanner.scan(root: root, mode: :query)
    assert report.violations == []
  end

  test "detects credential leases without tenant refs" do
    root =
      source_root!("bad_lease", """
      defmodule BadLease do
        def build do
          CredentialLease.new!(%{
            lease_id: "lease-1",
            credential_ref_id: "cred-1",
            subject: "operator",
            payload: %{},
            expires_at: DateTime.utc_now()
          })
        end
      end
      """)

    assert {:error, report} = TenantScanner.scan(root: root, mode: :lease)
    assert [%{code: "tenant_lease_no_tenant_ref"}] = report.violations
  end

  test "allows credential leases with tenant refs" do
    root =
      source_root!("good_lease", """
      defmodule GoodLease do
        def build do
          CredentialLease.new!(%{
            lease_id: "lease-1",
            tenant_id: "tenant-1",
            credential_ref_id: "cred-1",
            subject: "operator",
            payload: %{},
            expires_at: DateTime.utc_now()
          })
        end
      end
      """)

    assert {:ok, report} = TenantScanner.scan(root: root, mode: :lease)
    assert report.violations == []
  end

  defp source_root!(name, source) do
    root =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_tenant_scan_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "lib"))
    File.write!(Path.join(root, "lib/sample.ex"), source)
    root
  end
end
