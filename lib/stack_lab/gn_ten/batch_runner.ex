defmodule StackLab.GnTen.BatchRunner do
  @moduledoc false

  alias StackLab.GnTen.{BatchReceipt, Manifest, Status}

  @receipt_schema "gn_ten_batch_receipt_v1"
  @trace_schema "gn_ten_batch_trace_v1"
  @branch_policy "main_only"
  @workspace_ref "workspace://nshkrdotcom/gn-ten"
  @groups [
    ["ground_plane"],
    ["execution_plane"],
    ["jido_integration", "citadel"],
    ["outer_brain", "mezzanine"],
    ["app_kit", "extravaganza"],
    ["stack_lab", "AITrace"]
  ]
  @safe_slug ~r/^[a-z0-9][a-z0-9-]*$/

  @type run_result :: {:ok, map()} | {:error, map()}

  @spec run(String.t(), keyword()) :: run_result()
  def run(slug, opts \\ []) when is_binary(slug) do
    with :ok <- validate_slug(slug),
         :ok <- require_resume_confirmation(opts),
         {:ok, manifest} <- load_manifest(opts),
         :ok <- require_clean_main(manifest),
         {:ok, receipt} <- prepare_receipt(slug, manifest, opts),
         {:ok, repos} <- repos_to_run(receipt, manifest, opts),
         result <- run_repos(repos, receipt, opts),
         result <- ensure_non_stacklab_clean(result, manifest, opts) do
      write_artifacts(result)
      finish(result)
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec default_trace_dir() :: String.t()
  def default_trace_dir do
    Path.expand("tmp/gn_ten_traces", File.cwd!())
  end

  defp validate_slug(slug) do
    if Regex.match?(@safe_slug, slug) do
      :ok
    else
      {:error, error("unsafe_slug", slug: slug)}
    end
  end

  defp require_resume_confirmation(opts) do
    if Keyword.get(opts, :resume?, false) and not Keyword.get(opts, :confirm?, false) do
      {:error, error("resume_requires_confirm")}
    else
      :ok
    end
  end

  defp load_manifest(opts) do
    case Keyword.fetch(opts, :manifest) do
      {:ok, manifest} ->
        {:ok, manifest}

      :error ->
        opts
        |> Keyword.get(:manifest_path, Manifest.default_path())
        |> Manifest.validate_file()
        |> case do
          {:ok, manifest} -> {:ok, manifest}
          {:error, failures} -> {:error, error("manifest_invalid", failures: failures)}
        end
    end
  end

  defp require_clean_main(manifest) do
    status = workspace_status(manifest)

    if status.failures == [] do
      :ok
    else
      {:error, error("workspace_not_clean_main", failures: status.failures)}
    end
  end

  defp prepare_receipt(slug, manifest, opts) do
    date = Keyword.get(opts, :date, Date.utc_today())
    out_dir = Keyword.get(opts, :out_dir, BatchReceipt.default_out_dir())
    trace_dir = Keyword.get(opts, :trace_dir, default_trace_dir())
    compact_date = date |> Date.to_iso8601() |> String.replace("-", "")
    filename_root = "#{compact_date}_#{slug}"

    receipt =
      %{
        "schema_version" => @receipt_schema,
        "batch_id" => "#{compact_date}-#{slug}",
        "slug" => slug,
        "date" => Date.to_iso8601(date),
        "run_status" => "scaffold",
        "branch_policy" => @branch_policy,
        "workspace_ref" => Map.get(manifest, :workspace_ref, @workspace_ref),
        "primary_owner_repo" => "stack_lab",
        "contract_producer_repo" => nil,
        "consumer_repos" => [],
        "commands" => [],
        "proof" => %{
          "scenario" => "gn-ten repo-local CI batch",
          "evidence" => [],
          "does_not_prove" => [
            "production_deployment",
            "live_provider_behavior",
            "authoritative_audit_truth"
          ]
        },
        "trace_evidence" => [],
        "git_closeout" => [],
        "post_run_mutations" => [],
        "resume" => nil,
        "notes" => [],
        "paths" => %{
          "markdown" => Path.join(out_dir, "#{filename_root}.md"),
          "json" => Path.join(out_dir, "#{filename_root}.json"),
          "trace" => Path.join(trace_dir, "#{slug}.json")
        }
      }

    if Keyword.get(opts, :resume?, false) do
      load_resume_receipt(receipt)
    else
      write_artifacts(%{receipt: receipt, trace: empty_trace(receipt)})
      {:ok, receipt}
    end
  end

  defp load_resume_receipt(receipt) do
    json_path = receipt["paths"]["json"]

    with {:ok, raw} <- File.read(json_path),
         {:ok, previous} <- Jason.decode(raw),
         %{"resume" => %{"first_failed_repo" => repo}} <- previous do
      {:ok, Map.put(receipt, "resume_from", repo)}
    else
      {:error, reason} ->
        {:error, error("resume_receipt_read_failed", path: json_path, reason: reason)}

      _other ->
        {:error, error("resume_point_missing", path: json_path)}
    end
  end

  defp repos_to_run(receipt, manifest, opts) do
    repos = ordered_repos(manifest)

    if Keyword.get(opts, :resume?, false) do
      resume_from = receipt["resume_from"]
      resumed = Enum.drop_while(repos, &(&1.name != resume_from))

      case resumed do
        [] -> {:error, error("resume_repo_missing", repo: resume_from)}
        repos -> {:ok, repos}
      end
    else
      {:ok, repos}
    end
  end

  defp run_repos(repos, receipt, opts) do
    if Keyword.get(opts, :dry_run?, false) do
      dry_run_result(repos, receipt)
    else
      execute_repos(repos, receipt, opts)
    end
  end

  defp dry_run_result(repos, receipt) do
    commands =
      Enum.map(repos, fn repo ->
        command_entry(repo, "dry_run", 0, 0)
      end)

    receipt =
      receipt
      |> Map.put("run_status", "dry_run")
      |> Map.put("commands", commands)

    %{status: :dry_run, receipt: receipt, trace: trace(receipt, commands)}
  end

  defp execute_repos(repos, receipt, opts) do
    runner = Keyword.get(opts, :command_runner, &default_command_runner/2)

    Enum.reduce_while(repos, %{commands: [], status: :ok}, fn repo, acc ->
      started = System.monotonic_time(:millisecond)
      {status, exit_status} = run_one(runner, repo)
      duration_ms = System.monotonic_time(:millisecond) - started
      command = command_entry(repo, status, exit_status, duration_ms)
      commands = acc.commands ++ [command]

      if status == "ok" do
        {:cont, %{acc | commands: commands}}
      else
        {:halt,
         acc
         |> Map.put(:commands, commands)
         |> Map.put(:status, :failed)
         |> Map.put(:failed_repo, repo.name)}
      end
    end)
    |> finalize_execution(receipt)
  end

  defp run_one(runner, repo) do
    case runner.(repo, repo.ci) do
      {:ok, exit_status, _output} -> {"ok", exit_status}
      {:error, exit_status, _output} -> {"failed", exit_status}
      {:ok, _output} -> {"ok", 0}
      {:error, _output} -> {"failed", 1}
      other -> {"failed", {:unexpected_runner_result, other}}
    end
  rescue
    error -> {"failed", {:exception, Exception.message(error)}}
  end

  defp finalize_execution(%{status: :ok, commands: commands}, receipt) do
    receipt =
      receipt
      |> Map.put("run_status", "ok")
      |> Map.put("commands", commands)

    %{status: :ok, receipt: receipt, trace: trace(receipt, commands)}
  end

  defp finalize_execution(%{status: :failed, commands: commands, failed_repo: repo}, receipt) do
    receipt =
      receipt
      |> Map.put("run_status", "failed")
      |> Map.put("commands", commands)
      |> Map.put("resume", %{
        "first_failed_repo" => repo,
        "command" => "mix gn_ten.batch.run --name #{receipt["slug"]} --resume --confirm"
      })

    %{
      status: :failed,
      code: "batch_repo_failed",
      failed_repo: repo,
      receipt: receipt,
      trace: trace(receipt, commands)
    }
  end

  defp ensure_non_stacklab_clean(%{status: status} = result, _manifest, _opts)
       when status in [:dry_run, :failed] do
    result
  end

  defp ensure_non_stacklab_clean(%{status: :ok} = result, manifest, _opts) do
    mutations = non_stacklab_mutations(manifest)
    failures = Enum.reject(mutations, &allowed_generated_mutation?/1)

    case failures do
      [] ->
        put_post_run_mutations(result, mutations)

      failures ->
        result
        |> Map.put(:status, :failed)
        |> Map.put(:code, "workspace_mutated")
        |> Map.update!(:receipt, &Map.put(&1, "run_status", "failed"))
        |> Map.put(:failures, Enum.map(failures, &mutation_failure/1))
    end
  end

  defp non_stacklab_mutations(manifest) do
    manifest.repo_entries
    |> Enum.reject(&(&1.name == "stack_lab"))
    |> Enum.flat_map(&repo_mutations/1)
  end

  defp repo_mutations(repo) do
    case System.cmd("git", ["status", "--porcelain", "--untracked-files=all"], cd: repo.path) do
      {"", 0} ->
        []

      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&mutation(repo, &1))

      {_output, _status} ->
        [%{repo: repo.name, path: repo.path, status: "git_status_failed"}]
    end
  end

  defp mutation(repo, line) do
    status = line |> String.slice(0, 2) |> String.trim()
    path = String.slice(line, 3..-1//1)

    %{
      repo: repo.name,
      path: path,
      status: status
    }
  end

  defp allowed_generated_mutation?(%{status: "M", path: path}) do
    Regex.match?(~r/^dist\/(hex|monolith)\/[^\/]+\/projection\.lock\.json$/, path)
  end

  defp allowed_generated_mutation?(_mutation), do: false

  defp put_post_run_mutations(result, []), do: result

  defp put_post_run_mutations(result, mutations) do
    public_mutations =
      Enum.map(mutations, fn mutation ->
        %{
          "repo" => mutation.repo,
          "path" => mutation.path,
          "status" => mutation.status,
          "classification" => "repo_owned_generated_projection_lock"
        }
      end)

    Map.update!(result, :receipt, &Map.put(&1, "post_run_mutations", public_mutations))
  end

  defp mutation_failure(mutation) do
    %{
      code: "dirty_worktree",
      repo: mutation.repo,
      path: mutation.path,
      status: mutation.status,
      expected: "clean_or_allowed_generated_projection_lock",
      actual: "dirty"
    }
  end

  defp finish(%{status: :failed, code: code} = result) do
    {:error, Map.take(result, [:code, :failed_repo, :failures]) |> Map.put_new(:code, code)}
  end

  defp finish(%{status: :ok, receipt: receipt}) do
    {:ok,
     %{
       status: :ok,
       batch_id: receipt["batch_id"],
       md_path: receipt["paths"]["markdown"],
       json_path: receipt["paths"]["json"],
       trace_path: receipt["paths"]["trace"]
     }}
  end

  defp finish(%{status: :dry_run, receipt: receipt}) do
    {:ok,
     %{
       status: :dry_run,
       batch_id: receipt["batch_id"],
       md_path: receipt["paths"]["markdown"],
       json_path: receipt["paths"]["json"],
       trace_path: receipt["paths"]["trace"]
     }}
  end

  defp write_artifacts(%{receipt: receipt, trace: trace}) do
    md_path = receipt["paths"]["markdown"]
    json_path = receipt["paths"]["json"]
    trace_path = receipt["paths"]["trace"]

    File.mkdir_p!(Path.dirname(md_path))
    File.mkdir_p!(Path.dirname(trace_path))
    File.write!(md_path, markdown(receipt))
    File.write!(json_path, Jason.encode!(public_receipt(receipt), pretty: true))
    File.write!(trace_path, Jason.encode!(trace, pretty: true))
  end

  defp public_receipt(receipt), do: Map.drop(receipt, ["paths", "resume_from"])

  defp empty_trace(receipt), do: trace(receipt, [])

  defp trace(receipt, commands) do
    %{
      "schema_version" => @trace_schema,
      "trace_id" => "trace://stack_lab/gn-ten-batch/#{receipt["batch_id"]}",
      "batch_id" => receipt["batch_id"],
      "workspace_ref" => receipt["workspace_ref"],
      "proof_posture" => %{
        "authoritative_audit?" => false,
        "production_deployment_proven?" => false,
        "safe_action" => "use_as_batch_ci_evidence"
      },
      "spans" => Enum.map(commands, &span(receipt, &1)),
      "not_proven" => receipt["proof"]["does_not_prove"]
    }
  end

  defp span(receipt, command) do
    %{
      "span_id" => "#{command["repo"]}:repo_local_ci",
      "repo_ref" => command["repo_ref"],
      "status" => command["status"],
      "evidence_ref" => relative_to_stack_lab(receipt["paths"]["json"]),
      "attributes" => %{
        "batch_id" => receipt["batch_id"],
        "duration_ms" => command["duration_ms"],
        "exit_status" => command["exit_status"]
      }
    }
  end

  defp command_entry(repo, status, exit_status, duration_ms) do
    %{
      "repo" => repo.name,
      "repo_ref" => repo.repo_ref,
      "command" => repo.ci,
      "status" => status,
      "exit_status" => exit_status,
      "duration_ms" => duration_ms,
      "evidence_ref" => "repo-local-ci-status"
    }
  end

  defp ordered_repos(manifest) do
    by_name = Map.new(manifest.repo_entries, &{&1.name, &1})

    @groups
    |> Enum.flat_map(fn group ->
      group
      |> Enum.sort()
      |> Enum.map(&Map.fetch!(by_name, &1))
    end)
  end

  defp workspace_status(manifest) do
    repos = Enum.map(manifest.repo_entries, &Status.repo_status/1)
    failures = Enum.flat_map(repos, & &1.failures)

    %{
      repos: repos,
      failures: failures
    }
  end

  defp default_command_runner(repo, command) do
    case System.cmd("sh", ["-lc", command], cd: repo.path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, 0, output}
      {output, status} -> {:error, status, output}
    end
  end

  defp markdown(receipt) do
    """
    # gn-ten Batch Receipt: #{receipt["slug"]}

    Date: #{receipt["date"]}
    Batch ID: #{receipt["batch_id"]}
    Branch policy: #{receipt["branch_policy"]}
    Run status: #{receipt["run_status"]}
    Primary owner repo: #{receipt["primary_owner_repo"]}
    Contract producer repo: #{receipt["contract_producer_repo"] || ""}
    Consumer repos: #{Enum.join(receipt["consumer_repos"], ", ")}

    ## Scope

    - Goal: run repo-local gn-ten CI commands in fixed dependency order
    - Non-goals: branch management, pushing, source mutation, live-provider proof
    - Phase/checklist: Phase G CI And Batch Automation

    ## Commands

    #{commands_markdown(receipt["commands"])}

    ## Proof

    - Scenario: #{receipt["proof"]["scenario"]}
    - Trace evidence: #{relative_to_stack_lab(receipt["paths"]["trace"])}
    - Does not prove: #{Enum.join(receipt["proof"]["does_not_prove"], ", ")}

    ## Git Closeout

    - Repo: stack_lab
    - Branch: main
    - Commit SHA:
    - Pushed:
    - Worktree clean:

    ## Resume

    #{resume_markdown(receipt["resume"])}

    ## Notes

    - Public receipt fields intentionally omit raw command stdout and stderr.
    """
  end

  defp commands_markdown([]), do: "_No commands recorded yet._"

  defp commands_markdown(commands) do
    rows =
      Enum.map(commands, fn command ->
        "| #{command["repo"]} | `#{command["command"]}` | #{command["status"]} | #{command["exit_status"]} | #{command["duration_ms"]} |"
      end)

    Enum.join(
      ["| Repo | Command | Status | Exit | Duration ms |", "| --- | --- | --- | --- | --- |"] ++
        rows,
      "\n"
    )
  end

  defp resume_markdown(nil), do: "_No resume point._"

  defp resume_markdown(%{"first_failed_repo" => repo, "command" => command}) do
    "- First failed repo: #{repo}\n- Command: `#{command}`"
  end

  defp relative_to_stack_lab(path) do
    stack_lab = File.cwd!()

    case Path.relative_to(path, stack_lab) do
      ^path -> path
      relative -> relative
    end
  end

  defp error(code, fields \\ []) do
    fields
    |> Map.new()
    |> Map.put(:code, code)
  end
end
