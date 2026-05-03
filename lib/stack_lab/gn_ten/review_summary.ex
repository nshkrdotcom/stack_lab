defmodule StackLab.GnTen.ReviewSummary do
  @moduledoc false

  alias StackLab.GnTen.{BatchReceipt, Manifest, TextRules}

  @receipt_schema "gn_ten_batch_receipt_v1"
  @batch_trace_schema "gn_ten_batch_trace_v1"
  @trace_fixture_schema "aitrace.single_node_proof_trace.v1"
  @branch_policy "main_only"
  @required_receipt_fields ~w(
    schema_version
    batch_id
    branch_policy
    primary_owner_repo
    commands
    proof
    trace_evidence
    git_closeout
  )
  @required_command_fields ~w(repo repo_ref command status exit_status evidence_ref)
  @required_closeout_fields ~w(repo branch sha pushed clean)
  @required_not_proven ~w(production_deployment authoritative_audit_truth)
  @denied_keys ~w(raw_prompt provider_payload workflow_history secret api_key token)

  @type report :: %{
          batch_id: String.t() | nil,
          receipt_path: String.t(),
          command_count: non_neg_integer(),
          closeout_count: non_neg_integer(),
          trace_count: non_neg_integer(),
          failures: [map()]
        }

  @spec summarize(String.t(), keyword()) :: {:ok, report()} | {:error, report()}
  def summarize(batch, opts \\ []) when is_binary(batch) do
    root = Keyword.get(opts, :root, File.cwd!())
    receipt_dir = Keyword.get(opts, :receipt_dir, BatchReceipt.default_out_dir())

    with {:ok, path} <- find_receipt(batch, receipt_dir),
         {:ok, receipt} <- read_json(path) do
      receipt
      |> validate_receipt(path, root)
      |> result()
    else
      {:error, failure} ->
        report = empty_report(batch, receipt_dir, failure)
        {:error, report}
    end
  end

  defp find_receipt(batch, receipt_dir) do
    path =
      cond do
        Path.extname(batch) == ".json" and Path.type(batch) == :absolute ->
          batch

        Path.extname(batch) == ".json" ->
          Path.expand(batch, File.cwd!())

        true ->
          receipt_dir
          |> Path.join("*_#{batch}.json")
          |> Path.wildcard()
          |> Enum.sort()
          |> List.last()
      end

    cond do
      is_nil(path) ->
        {:error, failure("review_receipt_missing", batch: batch, receipt_dir: receipt_dir)}

      File.exists?(path) ->
        {:ok, path}

      true ->
        {:error, failure("review_receipt_missing", batch: batch, path: path)}
    end
  end

  defp read_json(path) do
    with {:ok, raw} <- File.read(path),
         {:ok, decoded} <- Jason.decode(raw) do
      {:ok, decoded}
    else
      {:error, reason} -> {:error, failure("review_json_read_failed", path: path, reason: reason)}
    end
  end

  defp validate_receipt(receipt, path, root) do
    traces = trace_reports(receipt, path, root)

    failures =
      []
      |> validate_required_fields(receipt)
      |> require_equal("review_bad_schema", receipt["schema_version"], @receipt_schema)
      |> require_equal("review_bad_branch_policy", receipt["branch_policy"], @branch_policy)
      |> validate_owner(receipt["primary_owner_repo"])
      |> validate_commands(receipt["commands"])
      |> validate_proof(receipt["proof"])
      |> validate_closeout(receipt["git_closeout"])
      |> validate_denied_keys(receipt, "receipt")
      |> Kernel.++(Enum.flat_map(traces, & &1.failures))

    %{
      batch_id: receipt["batch_id"],
      receipt_path: path,
      command_count: count(receipt["commands"]),
      closeout_count: count(receipt["git_closeout"]),
      trace_count: Enum.count(traces),
      failures: failures
    }
  end

  defp validate_required_fields(failures, receipt) do
    missing =
      Enum.filter(@required_receipt_fields, fn field ->
        value = receipt[field]
        is_nil(value) or value == "" or value == []
      end)

    case missing do
      [] -> failures
      fields -> [failure("review_missing_required_field", fields: fields) | failures]
    end
  end

  defp validate_owner(failures, repo) do
    if repo in Manifest.expected_repos() do
      failures
    else
      [failure("review_unknown_owner_repo", repo: repo) | failures]
    end
  end

  defp validate_commands(failures, commands) when is_list(commands) do
    commands
    |> Enum.with_index()
    |> Enum.reduce(failures, fn {command, index}, acc ->
      acc
      |> validate_command_fields(command, index)
      |> validate_command_success(command, index)
    end)
  end

  defp validate_commands(failures, commands) do
    [failure("review_commands_invalid", commands: commands) | failures]
  end

  defp validate_command_fields(failures, command, index) when is_map(command) do
    missing =
      Enum.filter(@required_command_fields, fn field ->
        value = command[field]
        is_nil(value) or value == ""
      end)

    case missing do
      [] -> failures
      fields -> [failure("review_command_missing_field", index: index, fields: fields) | failures]
    end
  end

  defp validate_command_fields(failures, command, index) do
    [failure("review_command_invalid", index: index, command: command) | failures]
  end

  defp validate_command_success(failures, command, index) when is_map(command) do
    if command["status"] == "ok" and command["exit_status"] == 0 do
      failures
    else
      [
        failure("review_command_not_green",
          index: index,
          repo: command["repo"],
          status: command["status"],
          exit_status: command["exit_status"]
        )
        | failures
      ]
    end
  end

  defp validate_command_success(failures, _command, _index), do: failures

  defp validate_proof(failures, %{} = proof) do
    failures
    |> require_present("review_missing_proof_scenario", proof["scenario"])
    |> validate_does_not_prove(proof["does_not_prove"])
  end

  defp validate_proof(failures, proof) do
    [failure("review_proof_invalid", proof: proof) | failures]
  end

  defp validate_does_not_prove(failures, values) when is_list(values) do
    missing = Enum.reject(@required_not_proven, &(&1 in values))

    case missing do
      [] -> failures
      values -> [failure("review_missing_does_not_prove", values: values) | failures]
    end
  end

  defp validate_does_not_prove(failures, values) do
    [failure("review_does_not_prove_invalid", values: values) | failures]
  end

  defp validate_closeout(failures, closeout) when is_list(closeout) do
    closeout
    |> Enum.with_index()
    |> Enum.reduce(failures, fn {entry, index}, acc ->
      acc
      |> validate_closeout_fields(entry, index)
      |> validate_closeout_green(entry, index)
    end)
  end

  defp validate_closeout(failures, closeout) do
    [failure("review_closeout_invalid", closeout: closeout) | failures]
  end

  defp validate_closeout_fields(failures, entry, index) when is_map(entry) do
    missing =
      Enum.filter(@required_closeout_fields, fn field ->
        value = entry[field]
        is_nil(value) or value == ""
      end)

    case missing do
      [] ->
        failures

      fields ->
        [failure("review_closeout_missing_field", index: index, fields: fields) | failures]
    end
  end

  defp validate_closeout_fields(failures, entry, index) do
    [failure("review_closeout_entry_invalid", index: index, entry: entry) | failures]
  end

  defp validate_closeout_green(failures, entry, index) when is_map(entry) do
    sha_ok? = TextRules.lower_hex?(entry["sha"], 40)
    state_ok? = entry["branch"] == "main" and entry["pushed"] == true and entry["clean"] == true

    if sha_ok? and state_ok? do
      failures
    else
      [failure("review_closeout_not_green", index: index, repo: entry["repo"]) | failures]
    end
  end

  defp validate_closeout_green(failures, _entry, _index), do: failures

  defp trace_reports(receipt, receipt_path, root) do
    receipt
    |> Map.get("trace_evidence", [])
    |> List.wrap()
    |> Enum.map(&validate_trace(&1, receipt_path, root))
  end

  defp validate_trace(trace_ref, receipt_path, root) do
    path = resolve_trace_path(trace_ref, receipt_path, root)

    case read_json(path) do
      {:ok, trace} ->
        %{
          path: path,
          failures:
            []
            |> validate_trace_schema(trace)
            |> validate_trace_batch(trace, receipt_path)
            |> validate_trace_posture(trace)
            |> validate_denied_keys(trace, "trace")
        }

      {:error, failure} ->
        %{path: path, failures: [failure]}
    end
  end

  defp resolve_trace_path(trace_ref, _receipt_path, root) do
    case Path.type(trace_ref) do
      :absolute -> trace_ref
      _type -> Path.expand(trace_ref, root)
    end
  end

  defp validate_trace_schema(failures, trace) do
    if trace["schema_version"] in [@batch_trace_schema, @trace_fixture_schema] do
      failures
    else
      [failure("review_trace_bad_schema", schema: trace["schema_version"]) | failures]
    end
  end

  defp validate_trace_batch(failures, trace, _receipt_path) do
    case trace["schema_version"] do
      @batch_trace_schema ->
        require_present(failures, "review_trace_missing_batch_id", trace["batch_id"])

      _schema ->
        failures
    end
  end

  defp validate_trace_posture(failures, %{"proof_posture" => %{} = posture}) do
    safe? =
      posture["authoritative_audit?"] == false and
        posture["production_deployment_proven?"] == false and
        posture["safe_action"] in [
          "use_as_batch_ci_evidence",
          "use_as_development_trace_fixture"
        ]

    if safe?,
      do: failures,
      else: [failure("review_trace_bad_posture", posture: posture) | failures]
  end

  defp validate_trace_posture(failures, trace) do
    [failure("review_trace_bad_posture", posture: trace["proof_posture"]) | failures]
  end

  defp validate_denied_keys(failures, value, scope) do
    value
    |> denied_paths([])
    |> Enum.reduce(failures, fn path, acc ->
      [failure("review_public_denied_key", scope: scope, path: path) | acc]
    end)
  end

  defp denied_paths(%{} = map, path) do
    Enum.flat_map(map, fn {key, value} ->
      child_path = path ++ [to_string(key)]

      if to_string(key) in @denied_keys do
        [Enum.join(child_path, ".")]
      else
        denied_paths(value, child_path)
      end
    end)
  end

  defp denied_paths(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} ->
      denied_paths(value, path ++ [Integer.to_string(index)])
    end)
  end

  defp denied_paths(_value, _path), do: []

  defp require_present(failures, _code, value) when value not in [nil, ""], do: failures
  defp require_present(failures, code, value), do: [failure(code, value: value) | failures]

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected) do
    [failure(code, expected: expected, actual: actual) | failures]
  end

  defp count(value) when is_list(value), do: length(value)
  defp count(_value), do: 0

  defp result(%{failures: []} = report), do: {:ok, report}
  defp result(report), do: {:error, report}

  defp empty_report(batch, receipt_dir, failure) do
    %{
      batch_id: batch,
      receipt_path: receipt_dir,
      command_count: 0,
      closeout_count: 0,
      trace_count: 0,
      failures: [failure]
    }
  end

  defp failure(code, fields) do
    fields
    |> Map.new()
    |> Map.put(:code, code)
  end
end
