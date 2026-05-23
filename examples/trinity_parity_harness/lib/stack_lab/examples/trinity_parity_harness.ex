defmodule StackLab.Examples.TRINITYParityHarness.Row do
  @moduledoc "One executable TRINITY parity harness row."
  @enforce_keys [:id, :description, :status]
  defstruct [:id, :description, :status, :details]
  @type t :: %__MODULE__{}
end

defmodule StackLab.Examples.TRINITYParityHarness.Receipt do
  @moduledoc "TRINITY parity harness receipt."
  @enforce_keys [:receipt_ref, :status, :coordinator_root, :framework_root, :rows]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end

defmodule StackLab.Examples.TRINITYParityHarness do
  @moduledoc """
  Executable parity rows for the monolith-to-framework migration.
  """

  alias StackLab.Examples.TRINITYParityHarness.{NoBypassFixtures, Receipt, Row}

  @default_rows [
    :source_inventory,
    :task_surface,
    :prompt_eval_fixtures,
    :no_bypass_fixtures,
    :deferred_cuda_parity,
    :deferred_stage_parity
  ]

  @all_task_count 17
  @coordinator_source_count 60

  @spec run(keyword()) :: {:ok, Receipt.t()}
  def run(opts \\ []) do
    coordinator_root = Keyword.get(opts, :coordinator_root, default_coordinator_root())
    framework_root = Keyword.get(opts, :framework_root, default_framework_root())

    rows =
      opts
      |> Keyword.get(:rows, @default_rows)
      |> Enum.map(&run_row(&1, coordinator_root, framework_root, opts))

    status =
      if Enum.all?(rows, &(&1.status in [:pass, :deferred])), do: :pass, else: :open_defect

    {:ok,
     %Receipt{
       receipt_ref: "stack-lab-trinity-parity-harness://phase-13",
       status: status,
       coordinator_root: coordinator_root,
       framework_root: framework_root,
       rows: rows
     }}
  end

  @spec run!() :: Receipt.t()
  def run! do
    {:ok, receipt} = run()
    receipt
  end

  defp run_row(:source_inventory, coordinator_root, _framework_root, _opts) do
    files =
      coordinator_root
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()

    status = if length(files) == @coordinator_source_count, do: :pass, else: :open_defect

    %Row{
      id: :source_inventory,
      description: "coordinator lib source inventory has the expected 60-file baseline",
      status: status,
      details: %{expected: @coordinator_source_count, actual: length(files)}
    }
  end

  defp run_row(:task_surface, coordinator_root, framework_root, opts) do
    runner = Keyword.get(opts, :command_runner, &run_mix/2)

    old_tasks = mix_help_tasks!(runner, coordinator_root)
    new_tasks = mix_help_tasks!(runner, framework_root)

    status =
      if old_tasks == new_tasks and length(old_tasks) == @all_task_count do
        :pass
      else
        :open_defect
      end

    %Row{
      id: :task_surface,
      description: "old and new mix help surfaces expose the same 17 trinity tasks",
      status: status,
      details: %{expected_count: @all_task_count, old: old_tasks, new: new_tasks}
    }
  end

  defp run_row(:prompt_eval_fixtures, coordinator_root, framework_root, _opts) do
    old_cases =
      Path.join(coordinator_root, "examples/fixtures/qwen_router_prompt_eval_cases.json")

    new_cases =
      Path.join(
        framework_root,
        "examples/qwen_router_prompt_eval/fixtures/qwen_router_prompt_eval_cases.json"
      )

    old_snapshot =
      Path.join(coordinator_root, "examples/fixtures/qwen_router_prompt_eval_logits.json")

    new_snapshot =
      Path.join(
        framework_root,
        "examples/qwen_router_prompt_eval/fixtures/qwen_router_prompt_eval_logits.json"
      )

    old_cases_hash = sha256!(old_cases)
    new_cases_hash = sha256!(new_cases)
    old_snapshot_hash = sha256!(old_snapshot)
    new_snapshot_hash = sha256!(new_snapshot)
    case_count = case_count!(old_cases)

    status =
      if old_cases_hash == new_cases_hash and old_snapshot_hash == new_snapshot_hash and
           case_count == 37 do
        :pass
      else
        :open_defect
      end

    %Row{
      id: :prompt_eval_fixtures,
      description: "prompt-eval cases and snapshot fixtures are byte-identical",
      status: status,
      details: %{
        case_count: case_count,
        old_cases_sha256: old_cases_hash,
        new_cases_sha256: new_cases_hash,
        old_snapshot_sha256: old_snapshot_hash,
        new_snapshot_sha256: new_snapshot_hash
      }
    }
  end

  defp run_row(:no_bypass_fixtures, _coordinator_root, _framework_root, _opts) do
    results = NoBypassFixtures.run()

    status =
      if Enum.all?(results, &(&1.status == &1.expected_status)), do: :pass, else: :open_defect

    %Row{
      id: :no_bypass_fixtures,
      description: "intentional TRINITY boundary fixtures fail/pass as expected",
      status: status,
      details: %{results: results}
    }
  end

  defp run_row(:deferred_cuda_parity, _coordinator_root, _framework_root, _opts) do
    %Row{
      id: :deferred_cuda_parity,
      description: "37/37 live CUDA decision-stable parity is the Phase 15 opt-in row",
      status: :deferred,
      details: %{phase: 15, reason: :requires_live_cuda_runtime}
    }
  end

  defp run_row(:deferred_stage_parity, _coordinator_root, _framework_root, _opts) do
    %Row{
      id: :deferred_stage_parity,
      description: "strict Python/Elixir stage tolerance parity is the Phase 15 opt-in row",
      status: :deferred,
      details: %{phase: 15, reason: :requires_stage_reports}
    }
  end

  defp run_row(id, _coordinator_root, _framework_root, _opts) do
    %Row{
      id: id,
      description: "unknown parity row",
      status: :open_defect,
      details: %{reason: :unknown_row}
    }
  end

  defp mix_help_tasks!(runner, root) do
    output = runner.(root, ["help", "--search", "trinity"])

    output
    |> String.split("\n")
    |> Enum.map(&Regex.run(~r/^mix\s+(trinity\.[^\s]+)/, &1, capture: :all_but_first))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&List.first/1)
    |> Enum.sort()
  end

  defp run_mix(root, args) do
    {output, status} =
      System.cmd("mix", args,
        cd: root,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    if status == 0, do: output, else: raise("mix #{Enum.join(args, " ")} failed:\n#{output}")
  end

  defp case_count!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("cases")
    |> length()
  end

  defp sha256!(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp default_coordinator_root, do: "/home/home/p/g/n/trinity_coordinator"
  defp default_framework_root, do: "/home/home/p/g/n/trinity_framework"
end
