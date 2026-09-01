defmodule StackLab.DynamicAtomScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.DynamicAtomScanner
  alias StackLab.DynamicAtomScanner.ClassifiedConversion
  alias StackLab.DynamicAtomScanner.Finding

  @forbidden_constructors [
    {"String.to_atom(value)", "String.to_atom"},
    {"String.to_existing_atom(value)", "String.to_existing_atom"},
    {"binary_to_atom(value)", "binary_to_atom"},
    {"binary_to_existing_atom(value)", "binary_to_existing_atom"},
    {"list_to_atom(value)", "list_to_atom"},
    {"list_to_existing_atom(value)", "list_to_existing_atom"},
    {":erlang.binary_to_atom(value, :utf8)", ":erlang.binary_to_atom"},
    {":erlang.binary_to_existing_atom(value, :utf8)", ":erlang.binary_to_existing_atom"}
  ]

  test "negative controls cover every forbidden atom constructor" do
    for {call, constructor} <- @forbidden_constructors do
      [finding] =
        DynamicAtomScanner.scan_source(
          """
          defmodule Example do
            def convert(value), do: #{call}
          end
          """,
          "/home/home/p/g/n/extravaganza/apps/extravaganza_core/lib/example.ex"
        )

      assert %Finding{constructor: ^constructor, classification: :production} = finding
    end
  end

  test "build support conversions are classified without opening a runtime defect" do
    [classified] =
      DynamicAtomScanner.scan_source(
        """
        defmodule Example do
          def normalize(value), do: String.to_atom(value)
        end
        """,
        "/workspace/app_kit/build_support/static_manifest.exs"
      )

    assert %ClassifiedConversion{
             constructor: "String.to_atom",
             classification: :build_support_static_manifest
           } = classified
  end

  test "test-owned conversions are classified outside runtime scope" do
    [classified] =
      DynamicAtomScanner.scan_source(
        """
        defmodule ExampleTest do
          def fixture(value), do: String.to_existing_atom(value)
        end
        """,
        "/home/home/p/g/n/jido_integration/core/contracts/test/example_test.exs"
      )

    assert %ClassifiedConversion{
             constructor: "String.to_existing_atom",
             classification: :test_owned
           } = classified
  end

  test "scanner-owned negative fixture conversions are classified" do
    [classified] =
      DynamicAtomScanner.scan_source(
        """
        defmodule StackLab.GapClosureNegativeFixtures do
          def fetch(map, key), do: Map.get(map, String.to_atom(key))
        end
        """,
        "/home/home/p/g/n/stack_lab/support/no_bypass_scanner/lib/stack_lab/gap_closure_negative_fixtures.ex"
      )

    assert %ClassifiedConversion{
             constructor: "String.to_atom",
             classification: :scanner_negative_fixture
           } = classified
  end

  test "scanner receipts separate findings from classified conversions" do
    root =
      Path.join(System.tmp_dir!(), "stack_lab_dynamic_atom_#{System.unique_integer([:positive])}")

    production_path = Path.join(root, "lib/runtime_bad.ex")
    test_path = Path.join(root, "test/example_test.exs")

    File.mkdir_p!(Path.dirname(production_path))
    File.mkdir_p!(Path.dirname(test_path))

    File.write!(production_path, """
    defmodule RuntimeBad do
      def convert(value), do: String.to_atom(value)
    end
    """)

    File.write!(test_path, """
    defmodule ExampleTest do
      def convert(value), do: String.to_existing_atom(value)
    end
    """)

    {:ok, receipt} =
      DynamicAtomScanner.scan(
        [root],
        target_roots: %{"tmp" => root},
        mode: :hard_gate
      )

    assert receipt.status == :open_defect
    assert Enum.any?(receipt.findings, &(&1.constructor == "String.to_atom"))
    assert Enum.any?(receipt.classified_conversions, &(&1.classification == :test_owned))
  end

  test "skips retained generated distribution trees" do
    root =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_dynamic_atom_dist_#{System.unique_integer([:positive])}"
      )

    dist_path = Path.join(root, "dist/hex/citadel/components/core/generated.ex")
    File.mkdir_p!(Path.dirname(dist_path))

    File.write!(dist_path, """
    defmodule GeneratedDistribution do
      def convert(value), do: String.to_atom(value)
    end
    """)

    {:ok, receipt} =
      DynamicAtomScanner.scan(
        [root],
        target_roots: %{"tmp" => root},
        mode: :hard_gate
      )

    assert receipt.status == :pass
    assert receipt.checked_paths == []
    assert [%{path: skipped_path, reason: :excluded_path}] = receipt.skipped_paths
    assert skipped_path == Path.join(root, "dist")
  end
end
