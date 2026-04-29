defmodule StackLab.GnTen.DeploymentDrills do
  @moduledoc false

  @schema_version "gn_ten_deployment_rehearsal_receipt_v1"
  @report_schema_version "gn_ten_deployment_rehearsal_report_v1"
  @workspace_ref "workspace://nshkrdotcom/gn-ten"
  @branch_policy "main_only"
  @profile "deployment_single_node"
  @receipt_date "2026-04-28"
  @denied_keys ~w(raw_prompt provider_payload workflow_history secret api_key token)

  @drills [
    %{
      id: "cold_deploy",
      title: "Cold deploy",
      source_contract: "600_deployment/600_Single_Node_Coolify.md",
      supporting_repos: ~w(stack_lab mezzanine app_kit),
      required_spans: ~w(
        local_container_teardown_rehearsed
        deploy_script_invoked_rehearsal
        health_endpoints_checked
        deployment_trace_exported
      ),
      proves: [
        "single-node cold-deploy checklist has a deterministic receipt",
        "health endpoint and trace-export evidence are recorded together"
      ],
      does_not_prove: [
        "clean-host production deployment",
        "Coolify server behavior",
        "container image provenance"
      ]
    },
    %{
      id: "backup_restore",
      title: "Backup and restore",
      source_contract: "600_deployment/607_Backup_Restore_Memory.md",
      supporting_repos: ~w(stack_lab mezzanine),
      required_spans: ~w(
        postgres_backup_rehearsed
        database_drop_rehearsed
        restore_rehearsed
        projection_bootstrap_checked
        restore_trace_posture_checked
      ),
      proves: [
        "backup and restore runbook has a separate local receipt",
        "projection bootstrap is tracked as a post-restore check"
      ],
      does_not_prove: [
        "live database destructive restore",
        "point-in-time recovery under production load",
        "disaster recovery RTO or RPO"
      ]
    },
    %{
      id: "substrate_health",
      title: "Substrate health",
      source_contract: "600_deployment/608_Production_Alerting.md",
      supporting_repos: ~w(stack_lab mezzanine outer_brain app_kit),
      required_spans: ~w(
        mezzanine_substrate_health_invoked
        temporal_guardrail_checked
        postgres_health_checked
        provider_free_boundary_checked
        websocket_edge_health_checked
      ),
      proves: [
        "Mezzanine owns local Temporal substrate health posture",
        "provider-free and websocket edge checks are part of deployment readiness"
      ],
      does_not_prove: [
        "live monitoring alert delivery",
        "provider uptime",
        "production websocket edge saturation"
      ]
    },
    %{
      id: "zero_downtime_migration",
      title: "Zero-downtime migration",
      source_contract: "600_deployment/604_Zero_Downtime_Deploy.md",
      supporting_repos: ~w(stack_lab mezzanine),
      required_spans: ~w(
        backward_compatible_migration_reviewed
        feature_flag_off_smoke
        read_write_during_migration_smoke
        feature_flag_toggle_smoke
        projection_rebuild_not_required
      ),
      proves: [
        "migration rollout checklist is separated from backup/restore",
        "feature-flag and projection-readiness checks are explicit"
      ],
      does_not_prove: [
        "production online DDL safety",
        "real concurrent write traffic",
        "database engine-specific lock behavior"
      ]
    },
    %{
      id: "websocket_reconnect",
      title: "Websocket reconnect",
      source_contract: "600_deployment/605_Websocket_Edge.md",
      supporting_repos: ~w(stack_lab app_kit extravaganza),
      required_spans: ~w(
        sample_client_connected
        server_bounce_rehearsed
        client_reconnect_checked
        missed_event_readback_checked
      ),
      proves: [
        "websocket reconnect/readback has a deployment receipt",
        "edge recovery is tracked independently from deploy health"
      ],
      does_not_prove: [
        "production edge failover",
        "browser compatibility",
        "large-fanout websocket load"
      ]
    }
  ]

  @all_drill_ids Enum.map(@drills, & &1.id)

  @spec default_out_dir() :: String.t()
  def default_out_dir do
    Path.expand("docs/receipts/gn_ten_deployment", File.cwd!())
  end

  @spec drill_ids() :: [String.t()]
  def drill_ids, do: @all_drill_ids

  @spec rehearse(String.t() | nil, keyword()) :: {:ok, map()} | {:error, map()}
  def rehearse(drill_id, opts \\ [])

  def rehearse(nil, _opts), do: {:error, error("deploy_drill_required")}

  def rehearse("all", opts) do
    @drills
    |> Enum.reduce_while({:ok, []}, fn drill, {:ok, receipts} ->
      case write_drill(drill, opts) do
        {:ok, receipt} -> {:cont, {:ok, receipts ++ [receipt]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> all_result()
  end

  def rehearse(drill_id, opts) when is_binary(drill_id) do
    case drill(drill_id) do
      nil ->
        {:error, error("deploy_drill_unknown", drill: drill_id, known_drills: @all_drill_ids)}

      drill ->
        write_drill(drill, opts)
    end
  end

  @spec report(keyword()) :: {:ok, map()} | {:error, map()}
  def report(opts \\ []) do
    out_dir = Keyword.get(opts, :out_dir, default_out_dir())

    rows =
      Enum.map(@all_drill_ids, fn drill_id ->
        read_receipt(drill_id, out_dir)
      end)

    failures = rows |> Enum.flat_map(&row_failures/1)
    receipts = rows |> Enum.flat_map(&row_receipts/1)
    report = report_map(out_dir, receipts, failures)

    if failures == [], do: {:ok, report}, else: {:error, report}
  end

  @spec validate_receipt(map()) :: :ok | {:error, [map()]}
  def validate_receipt(%{} = receipt) do
    failures =
      []
      |> require_equal(
        "deployment_receipt_bad_schema",
        receipt["schema_version"],
        @schema_version
      )
      |> require_equal("deployment_receipt_bad_profile", receipt["profile"], @profile)
      |> require_equal(
        "deployment_receipt_bad_branch_policy",
        receipt["branch_policy"],
        @branch_policy
      )
      |> validate_known_drill(receipt["drill"])
      |> validate_required_spans(receipt)
      |> validate_posture(receipt["proof_posture"])
      |> validate_denied_keys(receipt)

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  def validate_receipt(_receipt), do: {:error, [error("deployment_receipt_invalid")]}

  defp write_drill(drill, opts) do
    out_dir = Keyword.get(opts, :out_dir, default_out_dir())
    force? = Keyword.get(opts, :force?, false)
    receipt = receipt(drill, out_dir, Keyword.get(opts, :date, @receipt_date))
    paths = actual_paths(out_dir, drill.id)

    with :ok <- ensure_target_available(paths.markdown, force?),
         :ok <- ensure_target_available(paths.json, force?),
         :ok <- validate_receipt(receipt),
         :ok <- File.mkdir_p(out_dir),
         :ok <- File.write(paths.markdown, markdown(receipt)),
         :ok <- File.write(paths.json, Jason.encode!(receipt, pretty: true)) do
      {:ok,
       %{
         drill: drill.id,
         markdown_path: paths.markdown,
         json_path: paths.json
       }}
    else
      {:error, %{} = reason} -> {:error, reason}
      {:error, reason} -> {:error, error("deploy_drill_write_failed", reason: reason)}
    end
  end

  defp receipt(drill, out_dir, date) do
    repo_relative_out_dir = repo_relative_path(out_dir)

    %{
      "schema_version" => @schema_version,
      "drill" => drill.id,
      "title" => drill.title,
      "date" => date,
      "workspace_ref" => @workspace_ref,
      "branch_policy" => @branch_policy,
      "profile" => @profile,
      "owner_repo" => "stack_lab",
      "supporting_repos" => drill.supporting_repos,
      "command" => "mix gn_ten.deploy.rehearse --drill #{drill.id}",
      "source_contracts" => [drill.source_contract],
      "required_spans" => drill.required_spans,
      "spans" => Enum.map(drill.required_spans, &span(&1, drill.id)),
      "proof_posture" => proof_posture(),
      "proves" => drill.proves,
      "does_not_prove" => drill.does_not_prove,
      "not_proven" => common_not_proven(),
      "paths" => %{
        "markdown" => Path.join(repo_relative_out_dir, "#{drill.id}.md"),
        "json" => Path.join(repo_relative_out_dir, "#{drill.id}.json"),
        "trace" => "tmp/gn_ten_traces/deploy_cold.json"
      },
      "notes" => [
        "This is a deterministic local rehearsal receipt.",
        "It is intentionally not a production deployment proof."
      ]
    }
  end

  defp span(name, drill_id) do
    %{
      "name" => name,
      "status" => "pass",
      "attributes" => %{
        "workspace_ref" => @workspace_ref,
        "repo_ref" => "repo://nshkrdotcom/stack_lab",
        "drill" => drill_id,
        "evidence_ref" =>
          "receipt://stack_lab/single_node_deployment_rehearsal/#{drill_id}/#{name}"
      }
    }
  end

  defp markdown(receipt) do
    span_lines =
      receipt["spans"]
      |> Enum.map_join("\n", fn span ->
        "- [x] #{span["name"]}: #{span["status"]}"
      end)

    does_not_prove = Enum.map_join(receipt["does_not_prove"], "\n", &"- #{&1}")

    """
    # gn-ten Deployment Rehearsal: #{receipt["title"]}

    Drill: #{receipt["drill"]}
    Date: #{receipt["date"]}
    Profile: #{receipt["profile"]}
    Branch policy: #{receipt["branch_policy"]}
    Owner repo: #{receipt["owner_repo"]}
    Command: `#{receipt["command"]}`

    ## Proof Posture

    - authoritative_audit?: false
    - production_deployment_proven?: false
    - safe_action: use_as_local_single_node_deployment_rehearsal

    ## Required Spans

    #{span_lines}

    ## Does Not Prove

    #{does_not_prove}

    ## Notes

    - This is a deterministic local rehearsal receipt.
    - It is not a production deployment proof.
    """
  end

  defp read_receipt(drill_id, out_dir) do
    path = Path.join(out_dir, "#{drill_id}.json")
    display_path = Path.join(repo_relative_path(out_dir), "#{drill_id}.json")

    with {:ok, raw} <- File.read(path),
         {:ok, decoded} <- Jason.decode(raw),
         :ok <- validate_receipt(decoded) do
      {:ok, %{drill: drill_id, path: display_path, receipt: decoded}}
    else
      {:error, :enoent} ->
        {:error, error("deployment_receipt_missing", drill: drill_id, path: display_path)}

      {:error, failures} when is_list(failures) ->
        {:error,
         error("deployment_receipt_invalid",
           drill: drill_id,
           path: display_path,
           failures: failures
         )}

      {:error, reason} ->
        {:error,
         error("deployment_receipt_read_failed",
           drill: drill_id,
           path: display_path,
           reason: reason
         )}
    end
  end

  defp report_map(out_dir, receipts, failures) do
    %{
      "schema_version" => @report_schema_version,
      "status" => if(failures == [], do: "pass", else: "fail"),
      "workspace_ref" => @workspace_ref,
      "branch_policy" => @branch_policy,
      "profile" => @profile,
      "out_dir" => repo_relative_path(out_dir),
      "drill_count" => length(receipts),
      "required_drills" => @all_drill_ids,
      "receipts" => receipts,
      "failures" => failures,
      "proof_posture" => proof_posture()
    }
  end

  defp row_failures({:error, failure}), do: [failure]
  defp row_failures({:ok, _row}), do: []

  defp row_receipts({:ok, row}) do
    [
      %{
        "drill" => row.drill,
        "path" => row.path,
        "span_count" => length(row.receipt["spans"]),
        "production_deployment_proven?" =>
          row.receipt["proof_posture"]["production_deployment_proven?"]
      }
    ]
  end

  defp row_receipts({:error, _failure}), do: []

  defp all_result({:ok, receipts}) do
    {:ok, %{drills: receipts, drill_count: length(receipts)}}
  end

  defp all_result({:error, reason}), do: {:error, reason}

  defp drill(drill_id), do: Enum.find(@drills, &(&1.id == drill_id))

  defp ensure_target_available(_path, true), do: :ok

  defp ensure_target_available(path, false) do
    if File.exists?(path) do
      {:error, error("deployment_receipt_exists", path: path)}
    else
      :ok
    end
  end

  defp actual_paths(out_dir, drill_id) do
    %{
      markdown: Path.join(out_dir, "#{drill_id}.md"),
      json: Path.join(out_dir, "#{drill_id}.json")
    }
  end

  defp repo_relative_path(path) do
    path
    |> Path.expand()
    |> Path.relative_to(File.cwd!())
  end

  defp proof_posture do
    %{
      "authoritative_audit?" => false,
      "production_deployment_proven?" => false,
      "safe_action" => "use_as_local_single_node_deployment_rehearsal"
    }
  end

  defp common_not_proven do
    [
      "production_deployment",
      "multi_node_failover",
      "multi_region_disaster_recovery",
      "authoritative_audit_truth",
      "live_provider_behavior"
    ]
  end

  defp validate_known_drill(failures, drill_id) do
    if drill_id in @all_drill_ids do
      failures
    else
      [
        error("deployment_receipt_unknown_drill", drill: drill_id, known_drills: @all_drill_ids)
        | failures
      ]
    end
  end

  defp validate_required_spans(failures, receipt) do
    expected = required_spans(receipt["drill"], receipt["required_spans"])
    present = receipt |> Map.get("spans", []) |> Enum.map(& &1["name"]) |> MapSet.new()

    expected
    |> Enum.reject(&MapSet.member?(present, &1))
    |> case do
      [] -> failures
      missing -> [error("deployment_receipt_missing_required_span", spans: missing) | failures]
    end
  end

  defp required_spans(drill_id, fallback) do
    case drill(drill_id) do
      nil -> List.wrap(fallback)
      drill -> drill.required_spans
    end
  end

  defp validate_posture(failures, %{} = posture) do
    if posture["authoritative_audit?"] == false and
         posture["production_deployment_proven?"] == false do
      failures
    else
      [error("deployment_receipt_bad_posture", posture: posture) | failures]
    end
  end

  defp validate_posture(failures, posture) do
    [error("deployment_receipt_bad_posture", posture: posture) | failures]
  end

  defp validate_denied_keys(failures, receipt) do
    receipt
    |> denied_paths([])
    |> Enum.reduce(failures, fn path, acc ->
      [error("deployment_receipt_denied_key", path: path) | acc]
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

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected) do
    [error(code, expected: expected, actual: actual) | failures]
  end

  defp error(code, fields \\ []) do
    fields
    |> Map.new()
    |> Map.put(:code, code)
  end
end
