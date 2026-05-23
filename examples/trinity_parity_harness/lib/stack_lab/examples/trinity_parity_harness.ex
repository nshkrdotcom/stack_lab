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

  @phase15_rows [
    :source_inventory,
    :task_surface,
    :prompt_eval_fixtures,
    :no_bypass_fixtures,
    :cuda_parity,
    :stage_parity,
    :python_scripts
  ]

  @all_task_count 17
  @coordinator_monolith_source_count 60
  @coordinator_shim_source_count 18

  @spec run(keyword()) :: {:ok, Receipt.t()}
  def run(opts \\ []) do
    coordinator_root = Keyword.get(opts, :coordinator_root, default_coordinator_root())
    framework_root = Keyword.get(opts, :framework_root, default_framework_root())

    rows =
      opts
      |> selected_rows()
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

  @spec run!(keyword()) :: Receipt.t()
  def run!(opts) do
    {:ok, receipt} = run(opts)
    receipt
  end

  @spec phase15_rows() :: [atom()]
  def phase15_rows, do: @phase15_rows

  defp run_row(:source_inventory, coordinator_root, _framework_root, _opts) do
    files =
      coordinator_root
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()

    actual_count = length(files)
    expected_counts = [@coordinator_monolith_source_count, @coordinator_shim_source_count]

    posture =
      cond do
        actual_count == @coordinator_shim_source_count -> :shim
        actual_count == @coordinator_monolith_source_count -> :monolith
        true -> :unknown
      end

    status = if actual_count in expected_counts, do: :pass, else: :open_defect

    %Row{
      id: :source_inventory,
      description: "coordinator lib source inventory matches monolith baseline or Phase 16 shim",
      status: status,
      details: %{
        expected_monolith: @coordinator_monolith_source_count,
        expected_shim: @coordinator_shim_source_count,
        actual: actual_count,
        posture: posture
      }
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

  defp run_row(:cuda_parity, _coordinator_root, _framework_root, opts) do
    phase15_dir = phase15_dir(opts)
    old_snapshot = Path.join(phase15_dir, "coordinator_cuda_qwen_router_prompt_eval_logits.json")
    new_snapshot = Path.join(phase15_dir, "framework_cuda_qwen_router_prompt_eval_logits.json")
    old_log = Path.join(phase15_dir, "coordinator_cuda_qwen_router_prompt_eval.log")
    new_log = Path.join(phase15_dir, "framework_cuda_qwen_router_prompt_eval.log")

    details = cuda_parity_details(old_snapshot, new_snapshot, old_log, new_log)
    status = if details.pass?, do: :pass, else: :open_defect

    %Row{
      id: :cuda_parity,
      description:
        "old/new CUDA prompt-eval snapshots pass 37/37 and match decision-stable invariants",
      status: status,
      details: Map.delete(details, :pass?)
    }
  end

  defp run_row(:stage_parity, _coordinator_root, _framework_root, opts) do
    summary_path = Path.join(phase15_dir(opts), "stage_parity_summary.json")

    details =
      if File.regular?(summary_path) do
        summary = summary_path |> File.read!() |> Jason.decode!()

        %{
          pass?: summary["ok"] == true and summary["exit_status"] == 0,
          summary_path: summary_path,
          python_report: summary["python_report"],
          elixir_report: summary["elixir_report"],
          strict_stage_tolerances?: "--strict-stage-tolerances" in summary["comparator_args"]
        }
      else
        %{pass?: false, summary_path: summary_path, reason: :missing_summary}
      end

    %Row{
      id: :stage_parity,
      description: "strict Python/Elixir stage tolerance comparator completed successfully",
      status: if(details.pass?, do: :pass, else: :open_defect),
      details: Map.delete(details, :pass?)
    }
  end

  defp run_row(:python_scripts, coordinator_root, _framework_root, _opts) do
    expected = %{
      py: [
        "compare_sakana_parity_reports.py",
        "convert_router_vector_to_safetensors.py",
        "debug_sakana_large_tensor_chunks.py",
        "debug_sakana_parity_sample.py",
        "debug_sakana_router_trace.py",
        "export_sakana_trinity_safetensors.py"
      ],
      sh: ["run_expensive_all_selected_decompose.sh", "run_original_submission_svd_weights.sh"],
      md: ["SVD_PARITY_DEBUG.md"]
    }

    script_dir = Path.join(coordinator_root, "priv/sakana_trinity/scripts")

    missing =
      expected
      |> Map.values()
      |> List.flatten()
      |> Enum.reject(&File.regular?(Path.join(script_dir, &1)))

    %Row{
      id: :python_scripts,
      description: "Sakana Python parity scripts remain preserved as the external reference gate",
      status: if(missing == [], do: :pass, else: :open_defect),
      details: %{
        script_dir: script_dir,
        expected: expected,
        missing: missing,
        preservation: :coordinator_external_reference_until_shim_cutover
      }
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

  defp selected_rows(opts) do
    if Keyword.get(opts, :phase15, false),
      do: @phase15_rows,
      else: Keyword.get(opts, :rows, @default_rows)
  end

  defp cuda_parity_details(old_snapshot, new_snapshot, old_log, new_log) do
    with {:old_snapshot, true} <- {:old_snapshot, File.regular?(old_snapshot)},
         {:new_snapshot, true} <- {:new_snapshot, File.regular?(new_snapshot)},
         {:old_log, true} <- {:old_log, File.regular?(old_log)},
         {:new_log, true} <- {:new_log, File.regular?(new_log)} do
      old_cases = snapshot_cases!(old_snapshot)
      new_cases = snapshot_cases!(new_snapshot)
      count = length(old_cases)
      stable_keys = ~w(id agent_id role_id token_count transcript_hash)
      stable_matches = Map.new(stable_keys, &{&1, matching_count(old_cases, new_cases, &1)})
      route_hash_matches = matching_count(old_cases, new_cases, "route_hash")
      old_log_pass? = qwen_log_pass?(old_log)
      new_log_pass? = qwen_log_pass?(new_log)

      %{
        pass?:
          count == 37 and length(new_cases) == 37 and old_log_pass? and new_log_pass? and
            Enum.all?(stable_matches, fn {_key, matches} -> matches == 37 end),
        old_snapshot: old_snapshot,
        new_snapshot: new_snapshot,
        old_log: old_log,
        new_log: new_log,
        old_case_count: count,
        new_case_count: length(new_cases),
        stable_matches: stable_matches,
        route_hash_matches: route_hash_matches,
        route_hash_policy: :diagnostic_across_processes
      }
    else
      {missing, false} ->
        %{pass?: false, reason: :missing_file, missing: missing}
    end
  end

  defp snapshot_cases!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("cases")
  end

  defp matching_count(old_cases, new_cases, key) do
    old_cases
    |> Enum.zip(new_cases)
    |> Enum.count(fn {old_case, new_case} -> Map.get(old_case, key) == Map.get(new_case, key) end)
  end

  defp qwen_log_pass?(path) do
    log = File.read!(path)

    String.contains?(log, "passed: 37") and String.contains?(log, "failed: 0") and
      String.contains?(log, "PASS qwen_router_prompt_eval")
  end

  defp phase15_dir(opts), do: Keyword.get(opts, :phase15_dir, "tmp/phase15")

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
