defmodule StackLab.RuntimeBoundaryScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.RuntimeBoundaryScanner
  alias StackLab.RuntimeBoundaryScanner.ClassifiedCall
  alias StackLab.RuntimeBoundaryScanner.Finding

  @runtime_calls [
    {"Application.put_env(:app, :key, :value)", :application_env_mutation, "Application.put_env"},
    {"Application.delete_env(:app, :key)", :application_env_mutation, "Application.delete_env"},
    {"Application.get_env(:app, :key)", :application_env_read, "Application.get_env"},
    {"Application.fetch_env(:app, :key)", :application_env_read, "Application.fetch_env"},
    {"Application.fetch_env!(:app, :key)", :application_env_read, "Application.fetch_env!"},
    {":persistent_term.put({:app, :key}, :value)", :mutable_persistent_term,
     ":persistent_term.put"},
    {":persistent_term.erase({:app, :key})", :mutable_persistent_term, ":persistent_term.erase"},
    {"System.cmd(\"git\", [\"status\"])", :raw_command_execution, "System.cmd"},
    {"System.get_env(\"TOKEN\")", :system_env_read, "System.get_env"},
    {"Process.put(:trace_id, \"trace\")", :process_dictionary_context, "Process.put"},
    {"Process.get(:trace_id)", :process_dictionary_context, "Process.get"},
    {"Process.delete(:trace_id)", :process_dictionary_context, "Process.delete"}
  ]

  test "negative controls cover hidden runtime globals and raw side-effect calls" do
    for {call_source, rule, call_name} <- @runtime_calls do
      [finding] =
        RuntimeBoundaryScanner.scan_source(
          """
          defmodule Example do
            def call, do: #{call_source}
          end
          """,
          "/home/home/p/g/n/mezzanine/core/workflow_runtime/lib/example.ex"
        )

      assert %Finding{rule: ^rule, call: ^call_name, classification: :production} = finding
    end
  end

  test "test-owned and scanner-owned calls are classified outside hard-gate production scope" do
    [test_call] =
      RuntimeBoundaryScanner.scan_source(
        """
        defmodule ExampleTest do
          def setup_env, do: Application.put_env(:app, :key, :value)
        end
        """,
        "/home/home/p/g/n/extravaganza/apps/extravaganza_core/test/example_test.exs"
      )

    [scanner_call] =
      RuntimeBoundaryScanner.scan_source(
        """
        defmodule StackLab.ScannerHelper do
          def run, do: System.cmd("mix", ["test"])
        end
        """,
        "/home/home/p/g/n/stack_lab/support/no_bypass_scanner/lib/stack_lab/scanner_helper.ex"
      )

    assert %ClassifiedCall{classification: :test_owned} = test_call
    assert %ClassifiedCall{classification: :scanner} = scanner_call
  end

  test "Execution Plane OS boundary owns raw command execution" do
    [os_call] =
      RuntimeBoundaryScanner.scan_source(
        """
        defmodule ExecutionPlane.Process.OS do
          def uid, do: System.cmd("id", ["-u"])
        end
        """,
        "/home/home/p/g/n/execution_plane/runtimes/execution_plane_process/lib/execution_plane/process/os.ex"
      )

    assert %ClassifiedCall{
             classification: :os_boundary,
             rule: :raw_command_execution,
             call: "System.cmd"
           } = os_call
  end

  test "StackLab command runner owns StackLab harness command execution" do
    [runner_call] =
      RuntimeBoundaryScanner.scan_source(
        """
        defmodule StackLab.CommandRunner do
          def run(command, args, opts), do: System.cmd(command, args, opts)
        end
        """,
        "/home/home/p/g/n/stack_lab/support/lab_core/lib/stack_lab/command_runner.ex"
      )

    assert %ClassifiedCall{
             classification: :command_boundary,
             rule: :raw_command_execution,
             call: "System.cmd"
           } = runner_call
  end

  test "StackLab app env sandbox owns StackLab harness app env mutation" do
    [sandbox_call] =
      RuntimeBoundaryScanner.scan_source(
        """
        defmodule StackLab.AppEnvSandbox do
          def put(app, key, value), do: Application.put_env(app, key, value)
        end
        """,
        "/home/home/p/g/n/stack_lab/support/lab_core/lib/stack_lab/app_env_sandbox.ex"
      )

    assert %ClassifiedCall{
             classification: :app_env_sandbox,
             rule: :application_env_mutation,
             call: "Application.put_env"
           } = sandbox_call
  end

  test "scanner receipts separate production findings from classified calls" do
    root =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_runtime_boundary_#{System.unique_integer([:positive])}"
      )

    production_path = Path.join(root, "lib/runtime_bad.ex")
    test_path = Path.join(root, "test/example_test.exs")

    File.mkdir_p!(Path.dirname(production_path))
    File.mkdir_p!(Path.dirname(test_path))

    File.write!(production_path, """
    defmodule RuntimeBad do
      def run, do: System.cmd("git", ["status"])
    end
    """)

    File.write!(test_path, """
    defmodule ExampleTest do
      def env, do: Application.put_env(:app, :key, :value)
    end
    """)

    {:ok, receipt} =
      RuntimeBoundaryScanner.scan(
        [root],
        target_roots: %{"tmp" => root},
        mode: :hard_gate
      )

    assert receipt.status == :open_defect
    assert Enum.any?(receipt.findings, &(&1.rule == :raw_command_execution))
    assert Enum.any?(receipt.classified_calls, &(&1.classification == :test_owned))
  end

  test "baseline mode records findings without failing the receipt status as open defect" do
    root = Path.join(System.tmp_dir!(), "stack_lab_runtime_boundary_baseline")
    File.rm_rf!(root)
    path = Path.join(root, "lib/runtime_bad.ex")
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    defmodule RuntimeBad do
      def read, do: Application.get_env(:app, :key)
    end
    """)

    assert {:ok, receipt} =
             RuntimeBoundaryScanner.scan([root], target_roots: %{"tmp" => root}, mode: :baseline)

    assert receipt.status == :baseline_findings
    assert [%Finding{rule: :application_env_read}] = receipt.findings
  end

  test "skips retained generated distribution trees" do
    root =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_runtime_boundary_dist_#{System.unique_integer([:positive])}"
      )

    dist_path = Path.join(root, "dist/hex/citadel/components/core/generated.ex")
    File.mkdir_p!(Path.dirname(dist_path))

    File.write!(dist_path, """
    defmodule GeneratedDistribution do
      def run, do: System.cmd("git", ["status"])
    end
    """)

    {:ok, receipt} =
      RuntimeBoundaryScanner.scan(
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
