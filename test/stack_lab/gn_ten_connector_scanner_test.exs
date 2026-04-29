defmodule StackLab.GnTen.ConnectorScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.ConnectorScanner

  test "detects unwrapped non-fixture secrets" do
    root =
      source_root!("bad_secret", """
      defmodule BadSecret do
        def call do
          %{api_key: "sk_live_real_value"}
        end
      end
      """)

    assert {:error, report} = ConnectorScanner.scan(root: root, mode: :source)
    assert [%{code: "connector_unwrapped_secret"}] = report.violations
  end

  test "allows fixture secrets and lease handles" do
    root =
      source_root!("safe_secret", """
      defmodule SafeSecret do
        def fixture, do: %{api_key: "fixture-token"}
        def lease, do: %{credential_lease_handle: "lease://opaque"}
      end
      """)

    assert {:ok, report} = ConnectorScanner.scan(root: root, mode: :source)
    assert report.violations == []
  end

  test "detects provider calls without token budget context" do
    root =
      source_root!("bad_budget", """
      defmodule BadBudget do
        def run do
          Provider.call(%{model: "provider-x", input: "hello"})
        end
      end
      """)

    assert {:error, report} = ConnectorScanner.scan(root: root, mode: :source)
    assert [%{code: "connector_unbounded_token_budget"}] = report.violations
  end

  test "allows provider calls with token budget context" do
    root =
      source_root!("good_budget", """
      defmodule GoodBudget do
        def run do
          token_budget = %{max_tokens: 128}
          Provider.call(%{model: "provider-x", input: "hello", token_budget: token_budget})
        end
      end
      """)

    assert {:ok, report} = ConnectorScanner.scan(root: root, mode: :source)
    assert report.violations == []
  end

  test "detects live-provider proof without provider-free baseline" do
    root =
      proof_root!("bad_live", """
      schema_version: gn_ten_proof_matrix_v1

      proofs:
        - id: connector_live_provider
          profile: live_provider
          live_provider: true
      """)

    assert {:error, report} = ConnectorScanner.scan(root: root, mode: :proof)
    assert [%{code: "connector_no_provider_free_proof"} | _rest] = report.violations
  end

  test "allows live-provider proof when provider-free baseline exists" do
    root =
      proof_root!("good_live", """
      schema_version: gn_ten_proof_matrix_v1

      proofs:
        - id: connector_provider_free
          status: implemented
          profile: assembled_offline
        - id: connector_live_provider
          profile: live_provider
          live_provider: true
      """)

    assert {:ok, report} = ConnectorScanner.scan(root: root, mode: :proof)
    assert report.violations == []
  end

  defp source_root!(name, source) do
    root = tmp_root!("stack_lab_connector_scan_#{name}")
    File.mkdir_p!(Path.join(root, "lib"))
    File.write!(Path.join(root, "lib/sample.ex"), source)
    root
  end

  defp proof_root!(name, source) do
    root = tmp_root!("stack_lab_connector_scan_#{name}")
    File.write!(Path.join(root, "proof_matrix.yml"), source)
    root
  end

  defp tmp_root!(prefix) do
    root = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
