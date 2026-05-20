defmodule StackLab.CitadelSpineHarness.ExtravaganzaCleanupProof do
  @moduledoc """
  Destructive product-path proof for Extravaganza GitHub PR cleanup.

  The proof creates disposable provider objects through the lower GitHub
  connector, passes only the generated provider identities into Extravaganza's
  product command, verifies the governed product receipt/readback path, reruns
  cleanup for idempotence, and then deletes the disposable branch.
  """

  alias StackLab.CitadelSpineHarness
  alias StackLab.CitadelSpineHarness.ExtravaganzaCleanupReceiptProjection

  @approved_write_repo "nshkrdotcom/test"
  @default_timeout_ms 60_000
  @schema_name "extravaganza_cleanup_proof_receipt_v1.json"
  @proof_class "extravaganza_destructive_cleanup_product_path"
  @json_result_marker "JSON_RESULT:"
  @static_selector_flags [
    "--repo",
    "--branch",
    "--pull-number",
    "--github-issue-number",
    "--github-pr-number",
    "--github-comment-id",
    "--github-review-id"
  ]

  @type spec :: %{
          required(:approved_write_repo) => String.t(),
          required(:run_label) => String.t(),
          required(:timeout_ms) => pos_integer(),
          required(:receipt_file) => String.t()
        }

  @spec parse_args([String.t()]) :: {:ok, spec()} | {:error, term()}
  def parse_args(argv) when is_list(argv) do
    with {:ok, opts} <- parse_flags(drop_arg_separator(argv), %{}),
         {:ok, opts} <- normalize_opts(opts),
         :ok <- validate_write_repo(opts) do
      {:ok, build_spec(opts)}
    end
  end

  @spec plan(spec()) :: map()
  def plan(%{} = spec) do
    %{
      command: "mix stack_lab.extravaganza_cleanup_proof",
      run_label: spec.run_label,
      approved_write_repo: spec.approved_write_repo,
      steps: [
        :prepare_disposable_github_pr,
        :extravaganza_product_cleanup,
        :idempotent_product_cleanup_rerun,
        :delete_disposable_branch,
        :receipt_write
      ],
      provider_identity_source: :generated_by_jido_github_connector,
      product_entrypoint: "mix extravaganza.headless.live.github_pr_cleanup",
      product_role_ref: "proposed_change_cleanup",
      execution_route_ref: "generic_substrate:v1",
      static_provider_selector_acceptance?: false
    }
  end

  @spec run([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def run(argv, opts \\ []) do
    command_runner = Keyword.get(opts, :command_runner, &default_command_runner/3)
    receipt_writer = Keyword.get(opts, :receipt_writer, &write_receipt/2)
    progress = Keyword.get(opts, :progress, &default_progress/2)

    with {:ok, spec} <- parse_args(argv),
         :ok <- progress.(spec, :started),
         {:ok, prepared} <- prepare_disposable_pr(spec, command_runner, progress),
         {:ok, cleanup} <- run_product_cleanup(spec, prepared, :first, command_runner, progress),
         {:ok, idempotent} <-
           run_product_cleanup(spec, prepared, :idempotent, command_runner, progress),
         {:ok, branch_cleanup} <-
           delete_disposable_branch(spec, prepared, command_runner, progress),
         {:ok, receipt} <- receipt(spec, prepared, cleanup, idempotent, branch_cleanup) do
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

  defp parse_flags([flag | rest], acc)
       when flag in [
              "--approved-write-repo",
              "--run-label",
              "--receipt-file",
              "--timeout-ms"
            ] do
    key = flag_key(flag)

    case value_for(flag, rest) do
      {:ok, value, remaining} -> parse_flags(remaining, Map.put(acc, key, value))
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_flags([unknown | _rest], _acc), do: {:error, {:unknown_flag, unknown}}

  defp flag_key("--approved-write-repo"), do: :approved_write_repo
  defp flag_key("--run-label"), do: :run_label
  defp flag_key("--receipt-file"), do: :receipt_file
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
    with {:ok, timeout_ms} <- positive_integer("--timeout-ms", Map.get(opts, :timeout_ms)) do
      {:ok,
       opts
       |> normalize_string(:approved_write_repo)
       |> normalize_string(:run_label)
       |> normalize_string(:receipt_file)
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

  defp validate_write_repo(%{approved_write_repo: @approved_write_repo}), do: :ok

  defp validate_write_repo(%{approved_write_repo: repo}) do
    {:error, {:invalid_github_write_target, repo, @approved_write_repo}}
  end

  defp validate_write_repo(_opts), do: {:error, {:missing, ["--approved-write-repo"]}}

  defp build_spec(opts) do
    run_label = Map.get(opts, :run_label, default_run_label())

    %{
      approved_write_repo: Map.fetch!(opts, :approved_write_repo),
      run_label: run_label,
      timeout_ms: Map.fetch!(opts, :timeout_ms),
      receipt_file: Path.expand(Map.get(opts, :receipt_file, default_receipt_file(run_label)))
    }
  end

  defp prepare_disposable_pr(spec, command_runner, progress) do
    roots = CitadelSpineHarness.repo_roots()
    connector_dir = Path.join(roots.jido_integration, "connectors/github")
    script = Path.join(connector_dir, "scripts/live_acceptance.sh")

    args = [
      "prepare-pr",
      "--write-repo",
      spec.approved_write_repo,
      "--timeout-ms",
      Integer.to_string(spec.timeout_ms)
    ]

    with {:ok, output} <-
           run_step(:prepare_disposable_github_pr, command_runner, script, args,
             cd: connector_dir
           ),
         {:ok, prepared} <- decode_json_result(output),
         :ok <- verify_prepared_pr(prepared, spec) do
      progress.(:prepare_disposable_github_pr, :passed)
      {:ok, prepared}
    else
      {:error, reason} ->
        progress.(:prepare_disposable_github_pr, :failed)
        {:error, reason}
    end
  end

  defp run_product_cleanup(spec, prepared, mode, command_runner, progress) do
    roots = CitadelSpineHarness.repo_roots()
    step = product_cleanup_step(mode)
    trace_id = "trace:stack-lab/#{spec.run_label}/github-cleanup/#{mode}"

    args = [
      "extravaganza.headless.live.github_pr_cleanup",
      "--live-product-path",
      "--ack-headless-guardrails",
      "--json",
      "--repo",
      prepared["repo"],
      "--branch",
      prepared["branch"],
      "--pull-number",
      Integer.to_string(prepared["pull_number"]),
      "--confirm-close",
      "--closing-comment",
      closing_comment(spec, mode),
      "--trace-id",
      trace_id
    ]

    with {:ok, output} <-
           run_step(step, command_runner, "mix", args,
             cd: roots.extravaganza,
             env: [{"MIX_ENV", "test"}]
           ),
         {:ok, envelope} <- decode_json_result(output),
         :ok <- verify_cleanup_envelope(envelope, prepared, mode) do
      progress.(step, :passed)
      {:ok, envelope}
    else
      {:error, reason} ->
        progress.(step, :failed)
        {:error, reason}
    end
  end

  defp product_cleanup_step(:first), do: :extravaganza_product_cleanup
  defp product_cleanup_step(:idempotent), do: :idempotent_product_cleanup_rerun

  defp closing_comment(spec, :first) do
    "StackLab destructive cleanup proof #{spec.run_label}: closing disposable PR."
  end

  defp closing_comment(spec, :idempotent) do
    "StackLab destructive cleanup proof #{spec.run_label}: idempotence rerun."
  end

  defp delete_disposable_branch(spec, prepared, command_runner, progress) do
    roots = CitadelSpineHarness.repo_roots()
    connector_dir = Path.join(roots.jido_integration, "connectors/github")
    script = Path.join(connector_dir, "scripts/live_acceptance.sh")

    args = [
      "delete-ref",
      "--write-repo",
      prepared["repo"],
      "--branch",
      prepared["branch"],
      "--timeout-ms",
      Integer.to_string(spec.timeout_ms)
    ]

    with {:ok, output} <-
           run_step(:delete_disposable_branch, command_runner, script, args, cd: connector_dir),
         {:ok, cleanup} <- decode_json_result(output),
         :ok <- verify_branch_cleanup(cleanup, prepared) do
      progress.(:delete_disposable_branch, :passed)
      {:ok, cleanup}
    else
      {:error, reason} ->
        progress.(:delete_disposable_branch, :failed)
        {:error, reason}
    end
  end

  defp run_step(step, command_runner, command, args, opts) do
    case command_runner.(command, args, Keyword.put_new(opts, :stderr_to_stdout, true)) do
      {:ok, output} when is_binary(output) ->
        {:ok, output}

      {:ok, other} ->
        {:error, {:invalid_command_output, step, other}}

      {:error, reason} ->
        {:error, %{step: step, command: command, args: args, reason: reason}}
    end
  end

  defp verify_prepared_pr(prepared, spec) do
    cond do
      prepared["proof_class"] != "github_disposable_pr_preparation" ->
        {:error, {:unexpected_preparation_proof_class, prepared["proof_class"]}}

      prepared["repo"] != spec.approved_write_repo ->
        {:error, {:unexpected_prepared_repo, prepared["repo"]}}

      not present?(prepared["branch"]) ->
        {:error, :missing_prepared_branch}

      not (is_integer(prepared["pull_number"]) and prepared["pull_number"] > 0) ->
        {:error, {:invalid_prepared_pull_number, prepared["pull_number"]}}

      prepared["pull_state"] != "open" ->
        {:error, {:prepared_pull_request_not_open, prepared["pull_state"]}}

      true ->
        :ok
    end
  end

  defp verify_cleanup_envelope(envelope, prepared, :first) do
    effect = provider_effect(envelope)

    with :ok <- verify_common_product_envelope(envelope, prepared),
         :ok <- verify_effect_common(effect, prepared) do
      require_contains(effect["closed_pull_numbers"], prepared["pull_number"])
    end
  end

  defp verify_cleanup_envelope(envelope, prepared, :idempotent) do
    effect = provider_effect(envelope)

    with :ok <- verify_common_product_envelope(envelope, prepared),
         :ok <- verify_effect_common(effect, prepared),
         :ok <- require_not_contains(effect["closed_pull_numbers"], prepared["pull_number"]) do
      require_empty(effect["write_operations"])
    end
  end

  defp verify_common_product_envelope(envelope, prepared) do
    data = Map.get(envelope, "data", %{})

    cond do
      envelope["ok"] != true ->
        {:error, {:product_cleanup_not_ok, envelope["error"]}}

      envelope["execution_route_ref"] != "generic_substrate:v1" ->
        {:error, {:unexpected_execution_route_ref, envelope["execution_route_ref"]}}

      data["product_path_exercised?"] != true ->
        {:error, :product_path_not_exercised}

      data["operation"] != "live.github-pr-cleanup" ->
        {:error, {:unexpected_product_operation, data["operation"]}}

      provider_effect(envelope)["repo"] != prepared["repo"] ->
        {:error, {:cleanup_repo_mismatch, provider_effect(envelope)["repo"]}}

      provider_effect(envelope)["branch"] != prepared["branch"] ->
        {:error, {:cleanup_branch_mismatch, provider_effect(envelope)["branch"]}}

      true ->
        :ok
    end
  end

  defp verify_effect_common(effect, _prepared) do
    required = [
      {"resource_effect_role_ref", "proposed_change_cleanup"},
      {"operation", "github.pr.branch_cleanup"},
      {"provider_request_sent?", true},
      {"provider_response_received?", true},
      {"receipt_recorded?", true},
      {"product_readback_confirmed?", true}
    ]

    case Enum.find(required, fn {key, value} -> Map.get(effect, key) != value end) do
      nil -> :ok
      {key, expected} -> {:error, {:unexpected_cleanup_effect_field, key, effect[key], expected}}
    end
  end

  defp verify_branch_cleanup(cleanup, prepared) do
    cond do
      cleanup["proof_class"] != "github_disposable_ref_cleanup" ->
        {:error, {:unexpected_ref_cleanup_proof_class, cleanup["proof_class"]}}

      cleanup["repo"] != prepared["repo"] ->
        {:error, {:ref_cleanup_repo_mismatch, cleanup["repo"]}}

      cleanup["branch"] != prepared["branch"] ->
        {:error, {:ref_cleanup_branch_mismatch, cleanup["branch"]}}

      cleanup["status"] != "deleted" ->
        {:error, {:ref_cleanup_not_deleted, cleanup["status"]}}

      true ->
        :ok
    end
  end

  defp provider_effect(envelope) do
    envelope
    |> Map.get("data", %{})
    |> Map.get("provider_effect", %{})
  end

  defp require_contains(values, value) when is_list(values) do
    if value in values, do: :ok, else: {:error, {:missing_closed_pull_number, value, values}}
  end

  defp require_contains(values, value),
    do: {:error, {:invalid_closed_pull_numbers, value, values}}

  defp require_not_contains(values, value) when is_list(values) do
    if value in values, do: {:error, {:idempotent_rerun_reclosed_pull_number, value}}, else: :ok
  end

  defp require_not_contains(nil, _value), do: :ok

  defp require_not_contains(values, value),
    do: {:error, {:invalid_idempotent_closed_pull_numbers, value, values}}

  defp require_empty(nil), do: :ok
  defp require_empty([]), do: :ok
  defp require_empty(other), do: {:error, {:expected_no_idempotent_write_operations, other}}

  defp receipt(spec, prepared, cleanup, idempotent, branch_cleanup) do
    first_effect = provider_effect(cleanup)
    idempotent_effect = provider_effect(idempotent)

    with {:ok, generic_projection} <-
           ExtravaganzaCleanupReceiptProjection.build(cleanup, idempotent) do
      {:ok,
       %{
         schema_name: @schema_name,
         proof_class: @proof_class,
         status: :passed,
         command: "mix stack_lab.extravaganza_cleanup_proof",
         run_label: spec.run_label,
         receipt_file: spec.receipt_file,
         plan: plan(spec),
         approved_write_repo: spec.approved_write_repo,
         live_operation_inventory:
           live_operation_inventory(prepared, cleanup, idempotent, branch_cleanup),
         prepared_provider_object: select_prepared_fields(prepared),
         product_cleanup: summarize_cleanup(cleanup),
         idempotent_rerun: summarize_cleanup(idempotent),
         cleanup_leftover_status: branch_cleanup["status"],
         branch_cleanup: branch_cleanup,
         generic_receipt_projection: generic_projection,
         assertions:
           Map.merge(generic_projection.assertions, %{
             product_governed_path?: true,
             execution_route_ref: cleanup["execution_route_ref"],
             resource_effect_role_ref: first_effect["resource_effect_role_ref"],
             provider_request_sent?: first_effect["provider_request_sent?"],
             provider_response_received?: first_effect["provider_response_received?"],
             receipt_recorded?: first_effect["receipt_recorded?"],
             product_readback_confirmed?: first_effect["product_readback_confirmed?"],
             closed_pull_numbers: list_or_empty(first_effect["closed_pull_numbers"]),
             idempotent_closed_pull_numbers:
               list_or_empty(idempotent_effect["closed_pull_numbers"]),
             idempotent_write_operations: list_or_empty(idempotent_effect["write_operations"])
           })
       }}
    end
  end

  defp live_operation_inventory(prepared, cleanup, idempotent, branch_cleanup) do
    [
      %{
        operation: "jido.github.prepare_disposable_pr",
        route: "lower_connector_support",
        repo: prepared["repo"],
        branch: prepared["branch"],
        pull_number: prepared["pull_number"],
        proof_class: prepared["proof_class"]
      },
      product_inventory("extravaganza.live.github_pr_cleanup.first", cleanup),
      product_inventory("extravaganza.live.github_pr_cleanup.idempotent", idempotent),
      %{
        operation: "jido.github.delete_disposable_ref",
        route: "lower_connector_support",
        repo: branch_cleanup["repo"],
        branch: branch_cleanup["branch"],
        proof_class: branch_cleanup["proof_class"],
        status: branch_cleanup["status"]
      }
    ]
  end

  defp product_inventory(operation, envelope) do
    effect = provider_effect(envelope)

    %{
      operation: operation,
      route: "extravaganza_product_governed_path",
      execution_route_ref: envelope["execution_route_ref"],
      resource_effect_role_ref: effect["resource_effect_role_ref"],
      lower_request_ref: effect["lower_request_ref"],
      lower_receipt_ref: effect["lower_receipt_ref"],
      operation_receipt_count: length(list_or_empty(effect["operation_receipts"]))
    }
  end

  defp select_prepared_fields(prepared) do
    Map.take(prepared, [
      "proof_class",
      "status",
      "repo",
      "default_branch",
      "base_sha",
      "branch",
      "delete_ref",
      "scratch_path",
      "scratch_commit_sha",
      "pull_number",
      "pull_state",
      "cleanup_required?",
      "run_ids"
    ])
  end

  defp summarize_cleanup(envelope) do
    effect = provider_effect(envelope)

    %{
      ok: envelope["ok"],
      operation: envelope["operation"],
      execution_route_ref: envelope["execution_route_ref"],
      trace_id: envelope["trace_id"],
      status: envelope |> Map.get("data", %{}) |> Map.get("status"),
      product_path_exercised?:
        envelope |> Map.get("data", %{}) |> Map.get("product_path_exercised?"),
      provider_effect:
        Map.take(effect, [
          "resource_effect_role_ref",
          "status",
          "operation",
          "repo",
          "branch",
          "pull_numbers",
          "closed_pull_numbers",
          "provider_request_sent?",
          "provider_response_received?",
          "receipt_recorded?",
          "product_readback_confirmed?",
          "write_operations",
          "lower_request_ref",
          "lower_receipt_ref",
          "authority_handoff_ref",
          "connector_binding_ref",
          "credential_lease_ref",
          "operation_receipts"
        ])
    }
  end

  defp list_or_empty(nil), do: []
  defp list_or_empty(values) when is_list(values), do: values

  defp decode_json_result(output) when is_binary(output) do
    with {:ok, encoded} <- json_payload(output),
         {:ok, decoded} <- Jason.decode(encoded),
         true <- is_map(decoded) || {:error, :json_payload_not_object} do
      {:ok, decoded}
    end
  end

  defp json_payload(output) do
    case marker_payload(output) do
      {:ok, payload} -> {:ok, payload}
      :error -> first_json_object(output)
    end
  end

  defp marker_payload(output) do
    output
    |> String.split("\n")
    |> Enum.find_value(:error, fn line ->
      if String.starts_with?(line, @json_result_marker) do
        {:ok, String.trim_leading(line, @json_result_marker)}
      end
    end)
  end

  defp first_json_object(output) do
    bytes = :binary.bin_to_list(output)

    with {:ok, start} <- first_open_brace(bytes, 0),
         candidate_bytes <- Enum.drop(bytes, start),
         {:ok, length} <- balanced_object_length(candidate_bytes, 0, 0, false, false) do
      {:ok, binary_part(output, start, length)}
    end
  end

  defp first_open_brace([], _index), do: {:error, :json_object_not_found}
  defp first_open_brace([?{ | _rest], index), do: {:ok, index}
  defp first_open_brace([_byte | rest], index), do: first_open_brace(rest, index + 1)

  defp balanced_object_length([], _offset, _depth, _in_string?, _escaped?),
    do: {:error, :unterminated_json_object}

  defp balanced_object_length([_byte | rest], offset, depth, true, true),
    do: balanced_object_length(rest, offset + 1, depth, true, false)

  defp balanced_object_length([?\\ | rest], offset, depth, true, false),
    do: balanced_object_length(rest, offset + 1, depth, true, true)

  defp balanced_object_length([?" | rest], offset, depth, true, false),
    do: balanced_object_length(rest, offset + 1, depth, false, false)

  defp balanced_object_length([_byte | rest], offset, depth, true, false),
    do: balanced_object_length(rest, offset + 1, depth, true, false)

  defp balanced_object_length([?" | rest], offset, depth, false, false),
    do: balanced_object_length(rest, offset + 1, depth, true, false)

  defp balanced_object_length([?{ | rest], offset, depth, false, false),
    do: balanced_object_length(rest, offset + 1, depth + 1, false, false)

  defp balanced_object_length([?} | rest], offset, depth, false, false) do
    next_depth = depth - 1

    if next_depth == 0 do
      {:ok, offset + 1}
    else
      balanced_object_length(rest, offset + 1, next_depth, false, false)
    end
  end

  defp balanced_object_length([_byte | rest], offset, depth, false, false),
    do: balanced_object_length(rest, offset + 1, depth, false, false)

  defp present?(value), do: value not in [nil, "", []]

  defp default_progress(%{run_label: run_label, approved_write_repo: repo}, :started) do
    Mix.shell().info("Extravaganza cleanup proof starting run_label=#{run_label} repo=#{repo}")
  end

  defp default_progress(%{receipt_file: receipt_file}, :receipt_written) do
    Mix.shell().info("Extravaganza cleanup proof receipt written receipt_file=#{receipt_file}")
  end

  defp default_progress(step, :passed) when is_atom(step) do
    Mix.shell().info("Extravaganza cleanup proof step passed: #{step}")
  end

  defp default_progress(step, :failed) when is_atom(step) do
    Mix.shell().error("Extravaganza cleanup proof step failed: #{step}")
  end

  defp default_progress(_step, _event), do: :ok

  defp default_command_runner(command, args, opts) do
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
  defp stringify_atoms(term) when is_boolean(term), do: term
  defp stringify_atoms(nil), do: nil
  defp stringify_atoms(term) when is_atom(term), do: Atom.to_string(term)
  defp stringify_atoms(term), do: term

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: key

  defp default_run_label do
    "cleanup-proof-#{System.system_time(:second)}-#{System.unique_integer([:positive])}"
  end

  defp default_receipt_file(run_label) do
    Path.join(System.tmp_dir!(), "stack_lab_extravaganza_cleanup_proof_#{slug(run_label)}.json")
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
