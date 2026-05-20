defmodule StackLab.CitadelSpineHarness.ProviderSmokeCheck do
  @moduledoc """
  Opt-in provider smoke harness for shared lower providers.

  The harness composes existing owner-owned live checks and records one local
  receipt. It does not accept provider object ids from the operator; the lower
  proofs must create, discover, and carry provider identities from provider
  output and runtime receipts.
  """

  alias StackLab.CitadelSpineHarness

  @approved_github_repo "nshkrdotcom/test"
  @default_read_limit 10
  @default_timeout_ms 60_000
  @schema_name "provider_smoke_receipt_v1.json"
  @proof_class "provider_smoke_only"
  @not_proven [
    "product entrypoint",
    "work-control start_run",
    "workflow execution",
    "authority decision",
    "governed lower invocation",
    "receipt reducer projection",
    "product readback path"
  ]
  @static_selector_flags [
    "--github-issue-number",
    "--github-pr-number",
    "--github-comment-id",
    "--github-review-id",
    "--linear-issue-id",
    "--linear-comment-id",
    "--linear-state-id",
    "--codex-session-id",
    "--temporal-workflow-id"
  ]

  @type spec :: %{
          required(:linear_api_key_source) => :stdin | {:file, String.t()},
          required(:github_repo) => String.t(),
          required(:run_label) => String.t(),
          required(:temporal_mode) => :check,
          required(:codex_cwd) => String.t(),
          required(:read_limit) => pos_integer(),
          required(:timeout_ms) => pos_integer(),
          required(:receipt_file) => String.t()
        }

  @spec parse_args([String.t()]) :: {:ok, spec()} | {:error, term()}
  def parse_args(argv) when is_list(argv) do
    with {:ok, opts} <- parse_flags(drop_arg_separator(argv), %{}),
         {:ok, opts} <- normalize_opts(opts),
         :ok <- validate_linear_credential_source(opts),
         :ok <- validate_temporal_mode(opts),
         :ok <- validate_github_repo(opts) do
      {:ok, build_spec(opts)}
    end
  end

  @spec plan(spec()) :: map()
  def plan(%{} = spec) do
    %{
      command: "mix stack_lab.provider_smoke_check",
      run_label: spec.run_label,
      github_repo: spec.github_repo,
      temporal_mode: spec.temporal_mode,
      steps: [
        :temporal_status,
        :linear_terminal_publication,
        :github_disposable_pr,
        :codex_session_turn,
        :receipt_write
      ],
      identity_lifecycle: %{
        linear: :discover_issue_create_update_terminal_comment_from_provider_outputs,
        github: :fetch_repo_create_branch_commit_pr_review_close_delete_from_provider_outputs,
        codex: :session_turn_runtime_refs_from_lower_receipts,
        temporal: :mezzanine_just_substrate_status
      },
      static_provider_selector_acceptance?: false
    }
  end

  @spec run([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def run(argv, opts \\ []) do
    command_runner = Keyword.get(opts, :command_runner, &default_command_runner/3)
    secret_reader = Keyword.get(opts, :secret_reader, &read_linear_secret/1)
    receipt_writer = Keyword.get(opts, :receipt_writer, &write_receipt/2)
    progress = Keyword.get(opts, :progress, &default_progress/2)

    with {:ok, spec} <- parse_args(argv),
         {:ok, linear_stdin} <- maybe_read_linear_stdin(spec, secret_reader),
         :ok <- progress.(spec, :started),
         {:ok, temporal} <- run_temporal(spec, command_runner, progress),
         {:ok, linear} <- run_linear(spec, linear_stdin, command_runner, progress),
         {:ok, github} <- run_github(spec, command_runner, progress),
         {:ok, codex} <- run_codex(spec, command_runner, progress) do
      receipt =
        %{
          schema_name: @schema_name,
          proof_class: @proof_class,
          status: :smoke_test_only,
          provider_smoke_result: :passed,
          command: "mix stack_lab.provider_smoke_check",
          run_label: spec.run_label,
          receipt_file: spec.receipt_file,
          provider_smoke_steps: plan(spec).steps,
          plan: plan(spec),
          not_proven: @not_proven,
          temporal: temporal,
          linear: linear,
          github: github,
          codex: codex,
          cleanup: %{
            github_branch_deleted?: true,
            github_pr_closed?: true,
            linear_terminal_comment_preserved?: true
          }
        }

      with {:ok, _path} <- receipt_writer.(spec.receipt_file, receipt) do
        progress.(spec, :receipt_written)
        {:ok, receipt}
      end
    end
  end

  defp drop_arg_separator(["--" | argv]), do: argv
  defp drop_arg_separator(argv), do: argv

  defp parse_flags([], acc), do: {:ok, acc}

  defp parse_flags([flag | _rest], _acc) when flag in @static_selector_flags do
    {:error, {:static_provider_selector, flag}}
  end

  defp parse_flags(["--linear-api-key-stdin" | rest], acc) do
    parse_flags(rest, Map.put(acc, :linear_api_key_stdin, true))
  end

  defp parse_flags([flag | rest], acc)
       when flag in [
              "--linear-api-key-file",
              "--github-repo",
              "--run-label",
              "--codex-cwd",
              "--receipt-file",
              "--temporal-mode",
              "--read-limit",
              "--timeout-ms"
            ] do
    key = flag_key(flag)

    case value_for(flag, rest) do
      {:ok, value, remaining} -> parse_flags(remaining, Map.put(acc, key, value))
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_flags([unknown | _rest], _acc) do
    {:error, {:unknown_flag, unknown}}
  end

  defp flag_key("--linear-api-key-file"), do: :linear_api_key_file
  defp flag_key("--github-repo"), do: :github_repo
  defp flag_key("--run-label"), do: :run_label
  defp flag_key("--codex-cwd"), do: :codex_cwd
  defp flag_key("--receipt-file"), do: :receipt_file
  defp flag_key("--temporal-mode"), do: :temporal_mode
  defp flag_key("--read-limit"), do: :read_limit
  defp flag_key("--timeout-ms"), do: :timeout_ms

  defp value_for(flag, [next | rest]) when is_binary(next) do
    if String.starts_with?(next, "--") do
      {:error, {:missing_value, flag}}
    else
      {:ok, next, rest}
    end
  end

  defp value_for(flag, []), do: {:error, {:missing_value, flag}}

  defp normalize_opts(opts) do
    with {:ok, read_limit} <- positive_integer("--read-limit", Map.get(opts, :read_limit)),
         {:ok, timeout_ms} <- positive_integer("--timeout-ms", Map.get(opts, :timeout_ms)) do
      {:ok,
       opts
       |> normalize_string(:linear_api_key_file)
       |> normalize_string(:github_repo)
       |> normalize_string(:run_label)
       |> normalize_string(:codex_cwd)
       |> normalize_string(:receipt_file)
       |> normalize_string(:temporal_mode)
       |> Map.put(:read_limit, read_limit || @default_read_limit)
       |> Map.put(:timeout_ms, timeout_ms || @default_timeout_ms)}
    end
  end

  defp normalize_string(opts, key) do
    case Map.get(opts, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> Map.delete(opts, key)
          present -> Map.put(opts, key, present)
        end

      _other ->
        opts
    end
  end

  defp positive_integer(_flag, nil), do: {:ok, nil}

  defp positive_integer(flag, value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _other -> {:error, {:invalid_integer, flag, value}}
    end
  end

  defp validate_linear_credential_source(%{
         linear_api_key_stdin: true,
         linear_api_key_file: _path
       }) do
    {:error, {:duplicate_credential_source, ["--linear-api-key-stdin", "--linear-api-key-file"]}}
  end

  defp validate_linear_credential_source(%{linear_api_key_stdin: true}), do: :ok
  defp validate_linear_credential_source(%{linear_api_key_file: _path}), do: :ok

  defp validate_linear_credential_source(_opts) do
    {:error, {:missing, ["--linear-api-key-stdin", "--linear-api-key-file"]}}
  end

  defp validate_temporal_mode(%{temporal_mode: "check"}), do: :ok

  defp validate_temporal_mode(%{temporal_mode: mode}),
    do: {:error, {:invalid_temporal_mode, mode}}

  defp validate_temporal_mode(_opts), do: :ok

  defp validate_github_repo(%{github_repo: @approved_github_repo}), do: :ok

  defp validate_github_repo(%{github_repo: repo}) do
    {:error, {:invalid_github_write_target, repo, @approved_github_repo}}
  end

  defp validate_github_repo(_opts), do: :ok

  defp build_spec(opts) do
    roots = CitadelSpineHarness.repo_roots()
    run_label = Map.get(opts, :run_label, default_run_label())

    %{
      linear_api_key_source: linear_api_key_source(opts),
      github_repo: Map.get(opts, :github_repo, @approved_github_repo),
      run_label: run_label,
      temporal_mode: temporal_mode(Map.get(opts, :temporal_mode, "check")),
      codex_cwd: Path.expand(Map.get(opts, :codex_cwd, roots.jido_integration)),
      read_limit: Map.fetch!(opts, :read_limit),
      timeout_ms: Map.fetch!(opts, :timeout_ms),
      receipt_file: Path.expand(Map.get(opts, :receipt_file, default_receipt_file(run_label)))
    }
  end

  defp linear_api_key_source(%{linear_api_key_stdin: true}), do: :stdin
  defp linear_api_key_source(%{linear_api_key_file: path}), do: {:file, Path.expand(path)}

  defp temporal_mode("check"), do: :check

  defp maybe_read_linear_stdin(%{linear_api_key_source: :stdin}, secret_reader) do
    secret_reader.(:stdin)
  end

  defp maybe_read_linear_stdin(%{linear_api_key_source: {:file, _path}}, _secret_reader) do
    {:ok, nil}
  end

  defp read_linear_secret(:stdin) do
    case IO.read(:stdio, :eof) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          {:error, :empty_linear_api_key_stdin}
        else
          {:ok, value}
        end

      other ->
        {:error, {:invalid_linear_api_key_stdin, other}}
    end
  end

  defp run_temporal(spec, command_runner, progress) do
    roots = CitadelSpineHarness.repo_roots()

    commands =
      case spec.temporal_mode do
        :check -> [["dev-status"]]
      end

    case run_command_sequence(
           :temporal,
           command_runner,
           "just",
           commands,
           [cd: roots.mezzanine],
           progress
         ) do
      {:ok, outputs} ->
        {:ok, %{mode: spec.temporal_mode, command: "just", outputs: outputs}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_linear(spec, linear_stdin, command_runner, progress) do
    roots = CitadelSpineHarness.repo_roots()
    connector_dir = Path.join(roots.jido_integration, "connectors/linear")
    script = Path.join(connector_dir, "scripts/live_acceptance.sh")

    with_linear_credential_file(spec, linear_stdin, fn path ->
      args = [
        "all",
        "--api-key-file",
        path,
        "--keep-terminal-comment",
        "--read-limit",
        Integer.to_string(spec.read_limit),
        "--timeout-ms",
        Integer.to_string(spec.timeout_ms)
      ]

      case run_step(
             :linear,
             command_runner,
             script,
             args,
             [cd: connector_dir],
             progress
           ) do
        {:ok, output} ->
          {:ok,
           %{
             mode: :all,
             terminal_comment_preserved?: true,
             output: output
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp with_linear_credential_file(%{linear_api_key_source: {:file, path}}, _linear_stdin, fun) do
    fun.(path)
  end

  defp with_linear_credential_file(%{linear_api_key_source: :stdin} = spec, linear_stdin, fun) do
    path =
      System.tmp_dir!()
      |> Path.join(
        "stack_lab_linear_#{slug(spec.run_label)}_#{System.unique_integer([:positive])}"
      )

    try do
      path
      |> Path.dirname()
      |> File.mkdir_p!()

      File.write!(path, linear_stdin)
      File.chmod!(path, 0o600)
      fun.(path)
    after
      File.rm(path)
    end
  end

  defp run_github(spec, command_runner, progress) do
    roots = CitadelSpineHarness.repo_roots()
    connector_dir = Path.join(roots.jido_integration, "connectors/github")
    script = Path.join(connector_dir, "scripts/live_acceptance.sh")

    args = [
      "all",
      "--repo",
      spec.github_repo,
      "--write-repo",
      spec.github_repo,
      "--timeout-ms",
      Integer.to_string(spec.timeout_ms)
    ]

    case run_step(:github, command_runner, script, args, [cd: connector_dir], progress) do
      {:ok, output} ->
        {:ok,
         %{
           repo: spec.github_repo,
           disposable_pr_lifecycle?: true,
           output: output
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_codex(spec, command_runner, progress) do
    roots = CitadelSpineHarness.repo_roots()
    bridge_dir = Path.join(roots.jido_integration, "core/asm_runtime_bridge")

    args = [
      "run",
      "examples/live_codex_app_server_acceptance.exs",
      "--",
      "--cwd",
      spec.codex_cwd
    ]

    case run_step(:codex, command_runner, "mix", args, [cd: bridge_dir], progress) do
      {:ok, output} ->
        {:ok,
         %{
           mode: :codex_session_turn,
           cwd: spec.codex_cwd,
           output: output
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_command_sequence(step, command_runner, command, arg_lists, opts, progress) do
    Enum.reduce_while(arg_lists, {:ok, []}, fn args, {:ok, outputs} ->
      case run_step(step, command_runner, command, args, opts, progress) do
        {:ok, output} -> {:cont, {:ok, outputs ++ [output]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_step(step, command_runner, command, args, opts, progress) do
    progress.(step, :started)

    case command_runner.(command, args, opts) do
      {:ok, output} ->
        progress.(step, :passed)
        {:ok, output}

      {:error, reason} ->
        progress.(step, :failed)
        {:error, %{step: step, command: command, args: args, reason: reason}}
    end
  end

  defp default_progress(%{run_label: run_label, github_repo: github_repo}, :started) do
    Mix.shell().info(
      "Provider smoke check starting run_label=#{run_label} github_repo=#{github_repo}"
    )
  end

  defp default_progress(%{receipt_file: receipt_file}, :receipt_written) do
    Mix.shell().info("Provider smoke check receipt written receipt_file=#{receipt_file}")
  end

  defp default_progress(step, :started) when is_atom(step) do
    Mix.shell().info("Provider smoke check step starting: #{step}")
  end

  defp default_progress(step, :passed) when is_atom(step) do
    Mix.shell().info("Provider smoke check step passed: #{step}")
  end

  defp default_progress(step, :failed) when is_atom(step) do
    Mix.shell().error("Provider smoke check step failed: #{step}")
  end

  defp default_command_runner(command, args, opts) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)
    StackLab.CommandRunner.run_ok(command, args, opts)
  end

  defp write_receipt(path, receipt) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    encoded = Jason.encode_to_iodata!(stringify_atoms(receipt), pretty: true)

    case File.write(path, encoded) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:receipt_write_failed, path, reason}}
    end
  end

  defp stringify_atoms(term) when is_map(term) do
    Map.new(term, fn {key, value} -> {stringify_key(key), stringify_atoms(value)} end)
  end

  defp stringify_atoms(term) when is_list(term), do: Enum.map(term, &stringify_atoms/1)
  defp stringify_atoms(term) when is_atom(term), do: Atom.to_string(term)
  defp stringify_atoms(term), do: term

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: key

  defp default_run_label do
    "m12-#{System.system_time(:second)}-#{System.unique_integer([:positive])}"
  end

  defp default_receipt_file(run_label) do
    Path.join(System.tmp_dir!(), "stack_lab_provider_smoke_check_#{slug(run_label)}.json")
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.to_charlist()
    |> Enum.map(fn
      byte when byte in ?a..?z -> byte
      byte when byte in ?0..?9 -> byte
      ?. -> ?.
      ?_ -> ?_
      ?- -> ?-
      _other -> ?-
    end)
    |> List.to_string()
    |> String.trim("-")
  end
end
