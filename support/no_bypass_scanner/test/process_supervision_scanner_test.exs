defmodule StackLab.ProcessSupervisionScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.ProcessSupervisionScanner

  test "passes clean production source" do
    root = tmp_root()
    path = write!(root, "lib/clean.ex", "defmodule Clean do\n  def ok, do: :ok\nend\n")

    assert {:ok, receipt} = ProcessSupervisionScanner.scan([path], target_roots: %{"tmp" => root})
    assert receipt.status == :pass
    assert receipt.findings == []
  end

  test "flags bare production process primitives" do
    root = tmp_root()

    path =
      write!(root, "lib/bad.ex", """
      defmodule Bad do
        def run(fun), do: Task.async(fun)
        def boot(opts), do: GenServer.start(__MODULE__, opts)
        def launch, do: spawn_monitor(fn -> :ok end)
      end
      """)

    assert {:ok, receipt} = ProcessSupervisionScanner.scan([path], target_roots: %{"tmp" => root})
    assert receipt.status == :open_defect

    assert Enum.map(receipt.findings, & &1.primitive) == [
             "Task.async",
             "GenServer.start",
             "spawn_monitor"
           ]
  end

  test "does not flag start_link callback ownership" do
    root = tmp_root()

    path =
      write!(root, "lib/owned.ex", """
      defmodule Owned do
        use Agent
        def start_link(opts), do: Agent.start_link(fn -> opts end, name: __MODULE__)
      end
      """)

    assert {:ok, receipt} = ProcessSupervisionScanner.scan([path], target_roots: %{"tmp" => root})
    assert receipt.status == :pass
  end

  test "classifies test-owned caller processes without failing the gate" do
    root = tmp_root()

    path =
      write!(root, "test/demo_test.exs", """
      defmodule DemoTest do
        def run, do: Task.async(fn -> :ok end)
      end
      """)

    assert {:ok, receipt} = ProcessSupervisionScanner.scan([path], target_roots: %{"tmp" => root})
    assert receipt.status == :pass

    assert [%{classification: :test_owned, primitive: "Task.async"}] =
             receipt.classified_primitives
  end

  test "skips retained generated distribution trees" do
    root = tmp_root()

    write!(
      root,
      "dist/hex/citadel/components/core/generated.ex",
      """
      defmodule GeneratedDistribution do
        def boot(opts), do: GenServer.start(__MODULE__, opts)
      end
      """
    )

    assert {:ok, receipt} = ProcessSupervisionScanner.scan([root], target_roots: %{"tmp" => root})
    assert receipt.status == :pass
    assert receipt.checked_paths == []
    assert [%{path: skipped_path, reason: :excluded_path}] = receipt.skipped_paths
    assert skipped_path == Path.join(root, "dist")
  end

  defp tmp_root do
    root =
      Path.join(
        System.tmp_dir!(),
        "process-supervision-scanner-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end

  defp write!(root, relative_path, contents) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    path
  end
end
