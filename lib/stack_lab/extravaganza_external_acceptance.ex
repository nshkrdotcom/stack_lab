defmodule StackLab.ExtravaganzaExternalAcceptance do
  @moduledoc false

  @schema_version "stack_lab.extravaganza_external_acceptance.v1"
  @product_schema "extravaganza.headless.response.v1"
  @product_args ["extravaganza.headless.smoke", "--deterministic", "--same-run", "--json"]
  @projection_proof_step "mezzanine_runtime_projection_projected"

  @required_refs ~w(
    subject_ref
    run_ref
    workflow_ref
    product_role_ref
    binding_ref
    manifest_ref
    authority_ref
    connector_binding_ref
    connector_manifest_ref
    capability_negotiation_ref
    credential_lease_ref
    lower_request_ref
    receipt_ref
    source_publication_ref
    projection_ref
    evidence_ref
    evidence_chain_ref
    event_page_ref
    trace_ref
  )

  @required_readbacks ~w(
    state
    queue
    subject
    run
    evidence
    route_evidence
    context_ai_summary
    events
    reviews
    review_decision
    source_preview
    source_publish
    source_publication
    refresh
    control
    read_lease
    stream_attach_lease
    profile
    profile_validate
    profile_reload
    status
    logs
    live_preflight_denial
    command_coverage
    route_coverage
    error_classes
  )

  @required_route_evidence ~w(
    product_role_ref
    binding_ref
    manifest_ref
    authority_ref
    connector_binding_ref
    credential_lease_ref
    lower_request_ref
    receipt_ref
    projection_ref
    evidence_ref
    trace_ref
  )

  @required_context_ai_summary_paths [
    ["context_packet", "context_packet_ref"],
    ["context_packet", "packet_hash"],
    ["context_packet", "receipt_ref"],
    ["route_decision", "route_decision_ref"],
    ["model_invocation", "model_invocation_ref"],
    ["model_invocation", "model_receipt_ref"],
    ["model_invocation", "prompt_artifact_ref"],
    ["model_invocation", "provider_payload_ref"],
    ["model_invocation", "payload_hash"],
    ["eval_verdict", "eval_verdict_ref"],
    ["operator_review", "review_ref"]
  ]

  @spec command_args() :: [String.t()]
  def command_args, do: @product_args

  @spec default_extravaganza_root() :: String.t()
  def default_extravaganza_root do
    Path.expand("../../../extravaganza", __DIR__)
  end

  @spec default_receipt_path() :: String.t()
  def default_receipt_path do
    Path.expand("tmp/stack_lab/extravaganza_external_acceptance/single_node.json", File.cwd!())
  end

  @spec run(keyword()) :: {:ok, map()} | {:error, map()}
  def run(opts \\ []) do
    with {:ok, product_receipt} <- run_product_command(opts),
         :ok <- validate_product_receipt(product_receipt) do
      {:ok, external_receipt(product_receipt, opts)}
    end
  end

  @spec write_receipt!(map(), String.t()) :: String.t()
  def write_receipt!(receipt, path) when is_binary(path) do
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(receipt, pretty: true))
    path
  end

  defp run_product_command(opts) do
    root = Keyword.get(opts, :extravaganza_root, default_extravaganza_root())
    runner = Keyword.get(opts, :runner, &StackLab.CommandRunner.system_cmd/3)
    command = Keyword.get(opts, :mix_executable, mix_executable())

    case runner.(command, @product_args, command_opts(root)) do
      {output, 0} when is_binary(output) ->
        decode_product_receipt(output)

      {output, status} when is_binary(output) ->
        {:error,
         error("extravaganza_command_failed",
           exit_status: status,
           output_excerpt: output_excerpt(output)
         )}

      other ->
        {:error, error("extravaganza_command_return_invalid", returned: inspect(other))}
    end
  end

  defp command_opts(root) do
    [
      cd: root,
      env: [{"MIX_ENV", "test"}],
      env_allowlist: ["MIX_ENV"],
      stderr_to_stdout: true
    ]
  end

  defp decode_product_receipt(output) do
    case decode_json_receipt(output) do
      {:ok, %{} = receipt} ->
        {:ok, receipt}

      {:ok, decoded} ->
        {:error, error("extravaganza_receipt_not_object", decoded: inspect(decoded))}

      {:error, reason} ->
        {:error,
         error("extravaganza_receipt_json_invalid",
           reason: Exception.message(reason),
           output_excerpt: output_excerpt(output)
         )}
    end
  end

  defp decode_json_receipt(output) do
    trimmed = String.trim(output)

    case Jason.decode(trimmed) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> decode_trailing_json_receipt(trimmed)
    end
  end

  defp decode_trailing_json_receipt(output) do
    output
    |> :binary.matches("{")
    |> Enum.map(fn {position, 1} ->
      binary_part(output, position, byte_size(output) - position)
    end)
    |> Enum.reverse()
    |> Enum.find_value(fn candidate ->
      case Jason.decode(String.trim(candidate)) do
        {:ok, %{"schema" => @product_schema} = receipt} -> {:ok, receipt}
        {:ok, %{} = receipt} -> {:ok, receipt}
        _other -> nil
      end
    end)
    |> case do
      nil -> Jason.decode(output)
      decoded -> decoded
    end
  end

  defp validate_product_receipt(%{} = receipt) do
    with :ok <-
           require_equal(receipt["schema"], @product_schema, "extravaganza_receipt_bad_schema"),
         :ok <- require_equal(receipt["ok"], true, "extravaganza_receipt_not_ok"),
         :ok <- require_equal(receipt["operation"], "smoke", "extravaganza_receipt_bad_operation"),
         :ok <- require_proof_class(receipt),
         :ok <- require_required_refs(receipt),
         :ok <- require_lower_terminal_ref(receipt),
         :ok <- require_readbacks(receipt),
         :ok <- require_route_evidence(receipt),
         :ok <- require_context_ai_summary(receipt) do
      require_projection_proof(receipt)
    end
  end

  defp validate_product_receipt(_receipt), do: {:error, error("extravaganza_receipt_invalid")}

  defp require_equal(actual, expected, _code) when actual == expected, do: :ok

  defp require_equal(actual, expected, code),
    do: {:error, error(code, actual: actual, expected: expected)}

  defp require_proof_class(receipt) do
    proof = proof(receipt)

    with :ok <-
           require_equal(
             proof["proof_class"],
             "product_same_run_deterministic",
             "extravaganza_receipt_bad_proof_class"
           ) do
      require_equal(
        proof["all_readbacks_share_refs"],
        true,
        "extravaganza_receipt_readbacks_diverged"
      )
    end
  end

  defp require_required_refs(receipt) do
    refs = refs(receipt)
    missing = Enum.reject(@required_refs, &safe_ref?(refs[&1]))

    if missing == [] do
      :ok
    else
      {:error, error("extravaganza_receipt_missing_refs", missing_refs: missing)}
    end
  end

  defp require_lower_terminal_ref(receipt) do
    case lower_terminal_ref(refs(receipt)) do
      nil -> {:error, error("extravaganza_receipt_missing_lower_terminal_ref")}
      _ref -> :ok
    end
  end

  defp require_readbacks(receipt) do
    readbacks = readbacks(receipt)
    names = Enum.map(readbacks, & &1["name"])
    missing = @required_readbacks -- names

    cond do
      missing != [] ->
        {:error, error("extravaganza_receipt_missing_readbacks", missing_readbacks: missing)}

      Enum.any?(readbacks, &(&1["ok"] != true)) ->
        {:error, error("extravaganza_receipt_readback_not_ok")}

      true ->
        :ok
    end
  end

  defp require_projection_proof(receipt) do
    proof_steps = proof_steps(receipt)

    if @projection_proof_step in proof_steps do
      :ok
    else
      {:error, error("extravaganza_receipt_missing_projection_proof")}
    end
  end

  defp require_route_evidence(receipt) do
    route_evidence = route_evidence(receipt)
    missing = Enum.reject(@required_route_evidence, &safe_ref?(route_evidence[&1]))

    cond do
      missing != [] ->
        {:error, error("extravaganza_receipt_missing_route_evidence", missing_fields: missing)}

      get_in(route_evidence, ["trace_replay", "status"]) in [nil, ""] ->
        {:error, error("extravaganza_receipt_missing_trace_replay_status")}

      true ->
        :ok
    end
  end

  defp require_context_ai_summary(receipt) do
    summary = context_ai_summary(receipt)

    with :ok <- require_context_summary_present(summary),
         :ok <- require_context_summary_surface(summary),
         :ok <- require_context_summary_product_safe(summary),
         :ok <- require_context_summary_hashes(summary) do
      require_context_summary_refs(summary)
    end
  end

  defp require_context_summary_present(%{} = summary) when map_size(summary) > 0, do: :ok

  defp require_context_summary_present(_summary) do
    {:error, error("extravaganza_receipt_missing_context_ai_summary")}
  end

  defp require_context_summary_surface(%{"surface" => "AppKit.ContextSurface"}), do: :ok

  defp require_context_summary_surface(summary) do
    {:error, error("extravaganza_receipt_bad_context_surface", surface: summary["surface"])}
  end

  defp require_context_summary_product_safe(summary) do
    if summary["live_provider_required?"] == false and summary["lower_stack_imports?"] == false and
         summary["forbidden_raw_fields_present?"] == false do
      :ok
    else
      context_summary_safety_error(summary)
    end
  end

  defp context_summary_safety_error(%{"forbidden_raw_fields_present?" => value})
       when value != false do
    {:error, error("extravaganza_receipt_context_summary_has_raw_fields")}
  end

  defp context_summary_safety_error(_summary) do
    {:error, error("extravaganza_receipt_context_summary_not_product_safe")}
  end

  defp require_context_summary_hashes(summary) do
    cond do
      not safe_sha?(get_in(summary, ["context_packet", "packet_hash"])) ->
        {:error, error("extravaganza_receipt_context_packet_hash_invalid")}

      not safe_sha?(get_in(summary, ["model_invocation", "payload_hash"])) ->
        {:error, error("extravaganza_receipt_model_payload_hash_invalid")}

      true ->
        :ok
    end
  end

  defp require_context_summary_refs(summary) do
    missing =
      @required_context_ai_summary_paths
      |> Enum.reject(fn path -> safe_ref?(get_in(summary, path)) end)
      |> Enum.map(&Enum.join(&1, "."))

    if missing == [] do
      :ok
    else
      {:error,
       error("extravaganza_receipt_context_summary_missing_refs", missing_fields: missing)}
    end
  end

  defp external_receipt(product_receipt, opts) do
    root = Keyword.get(opts, :extravaganza_root, default_extravaganza_root())
    refs = refs(product_receipt)

    %{
      "schema_version" => @schema_version,
      "status" => "pass",
      "owner_repo" => "stack_lab",
      "product_repo" => "extravaganza",
      "product_acceptance_owner" => "extravaganza",
      "stack_lab_role" => "external_acceptance",
      "command" => %{
        "cwd" => root,
        "env" => %{"MIX_ENV" => "test"},
        "argv" => ["mix" | @product_args]
      },
      "proof_posture" => %{
        "imports_extravaganza_internals?" => false,
        "product_implementation_in_stack_lab?" => false,
        "provider_smoke_is_product_acceptance?" => false,
        "single_node_external_acceptance_proven?" => true,
        "multi_node_topology_proven?" => false
      },
      "validated_refs" => validated_refs(refs),
      "validated_route_evidence" => route_evidence(product_receipt),
      "validated_context_ai_summary" => compact_context_summary(product_receipt),
      "product_receipt" => product_summary(product_receipt),
      "provider_smoke" => %{
        "classification" => "separate_provider_only_not_product_acceptance",
        "run_by_this_acceptance?" => false
      },
      "not_proven" => [
        "multi_node_topology",
        "production_deployment",
        "live_provider_behavior"
      ]
    }
  end

  defp validated_refs(refs) do
    refs
    |> Map.take(@required_refs)
    |> Map.put("lower_terminal_ref", lower_terminal_ref(refs))
  end

  defp product_summary(receipt) do
    proof = proof(receipt)

    %{
      "schema" => receipt["schema"],
      "ok" => receipt["ok"],
      "operation" => receipt["operation"],
      "generated_at" => receipt["generated_at"],
      "trace_id" => receipt["trace_id"],
      "runtime_profile_ref" => receipt["runtime_profile_ref"],
      "proof_class" => proof["proof_class"],
      "all_readbacks_share_refs" => proof["all_readbacks_share_refs"],
      "readbacks" => Enum.map(readbacks(receipt), & &1["name"]),
      "steps" => proof_steps(receipt),
      "route_evidence" => route_evidence(receipt),
      "context_ai_summary" => compact_context_summary(receipt),
      "refs" =>
        Map.take(
          refs(receipt),
          @required_refs ++
            ~w(runtime_profile_ref decision_ref lower_receipt_ref lower_denial_ref)
        )
    }
  end

  defp lower_terminal_ref(refs) do
    Enum.find_value(~w(lower_receipt_ref lower_denial_ref), fn key ->
      ref = refs[key]
      if safe_ref?(ref), do: ref
    end)
  end

  defp refs(%{} = receipt), do: map_or_empty(receipt["refs"])
  defp proof(%{} = receipt), do: map_or_empty(get_in(receipt, ["data", "proof"]))
  defp proof_steps(receipt), do: proof(receipt)["steps"] || proof(receipt)["proof_steps"] || []

  defp route_evidence(receipt) do
    direct = map_or_empty(get_in(receipt, ["data", "route_evidence"]))
    proof_route = map_or_empty(get_in(receipt, ["data", "proof", "route_evidence"]))

    cond do
      direct != %{} ->
        direct

      proof_route != %{} ->
        proof_route

      true ->
        receipt
        |> readbacks()
        |> Enum.find_value(%{}, &route_evidence_readback/1)
    end
  end

  defp route_evidence_readback(%{"name" => "route_evidence"} = readback) do
    map_or_empty(readback["data"])
  end

  defp route_evidence_readback(_readback), do: nil

  defp context_ai_summary(receipt) do
    direct = map_or_empty(get_in(receipt, ["data", "context_ai_summary"]))
    proof_summary = map_or_empty(get_in(receipt, ["data", "proof", "context_ai_summary"]))

    cond do
      direct != %{} ->
        direct

      proof_summary != %{} ->
        proof_summary

      true ->
        receipt
        |> readbacks()
        |> Enum.find_value(%{}, &context_ai_summary_readback/1)
    end
  end

  defp context_ai_summary_readback(%{"name" => "context_ai_summary"} = readback) do
    map_or_empty(readback["data"])
  end

  defp context_ai_summary_readback(_readback), do: nil

  defp compact_context_summary(receipt) do
    summary = context_ai_summary(receipt)

    %{
      "surface" => summary["surface"],
      "proof_class" => summary["proof_class"],
      "context_packet_ref" => get_in(summary, ["context_packet", "context_packet_ref"]),
      "packet_hash" => get_in(summary, ["context_packet", "packet_hash"]),
      "route_decision_ref" => get_in(summary, ["route_decision", "route_decision_ref"]),
      "model_invocation_ref" => get_in(summary, ["model_invocation", "model_invocation_ref"]),
      "model_receipt_ref" => get_in(summary, ["model_invocation", "model_receipt_ref"]),
      "eval_verdict_ref" => get_in(summary, ["eval_verdict", "eval_verdict_ref"]),
      "review_ref" => get_in(summary, ["operator_review", "review_ref"]),
      "prompt_artifact_ref" => get_in(summary, ["model_invocation", "prompt_artifact_ref"]),
      "provider_payload_ref" => get_in(summary, ["model_invocation", "provider_payload_ref"]),
      "payload_hash" => get_in(summary, ["model_invocation", "payload_hash"])
    }
  end

  defp readbacks(receipt) do
    case proof(receipt)["readbacks"] do
      readbacks when is_list(readbacks) -> readbacks
      _readbacks -> []
    end
  end

  defp map_or_empty(%{} = map), do: map
  defp map_or_empty(_value), do: %{}

  defp safe_ref?(value), do: is_binary(value) and String.trim(value) != ""
  defp safe_sha?("sha256:" <> hash), do: byte_size(hash) == 64
  defp safe_sha?(_value), do: false

  defp mix_executable, do: System.find_executable("mix") || "mix"

  defp output_excerpt(output) do
    output
    |> String.split()
    |> Enum.join(" ")
    |> String.slice(0, 500)
  end

  defp error(code, fields \\ []) do
    fields
    |> Map.new()
    |> Map.put(:code, code)
  end
end
