defmodule StackLab.GnTenNodeLab.EnvelopeScanner do
  @moduledoc """
  Distributed envelope scanner for local gn-ten node-lab proof facts.

  This scanner validates harness and owner DTO envelopes before they are used as
  distributed proof facts. It is intentionally shape-focused; domain semantics
  remain with owner repos and their scanners.
  """

  @schema_version "stack_lab.gn_ten_node_lab.envelope_scan.v1"
  @scanner_ref "scanner://stack_lab/gn-ten-node-lab/distributed-envelope/v1"

  @required_fields ~w(tenant_ref correlation_ref idempotency_key origin_node_ref target_profile redaction_class payload_mode issued_at)
  @schema_fields ~w(schema_ref schema_version)
  @trace_fields ~w(trace_ref trace_parent_ref)
  @blocked_key_fragments ~w(raw_prompt prompt_text raw_memory memory_body provider_payload credentials credential secret auth_header private_tool_output)
  @direct_lower_keys ~w(direct_lower_import direct_lower_imports direct_lower_call bypass_import bypass_imports)

  @spec scan(map(), keyword()) :: map()
  def scan(envelope, opts \\ []) when is_map(envelope) and is_list(opts) do
    findings =
      envelope
      |> required_field_findings()
      |> Kernel.++(schema_findings(envelope, opts))
      |> Kernel.++(authority_findings(envelope))
      |> Kernel.++(trace_findings(envelope))
      |> Kernel.++(tenant_findings(envelope))
      |> Kernel.++(direct_lower_findings(envelope))
      |> Kernel.++(walk(envelope, []))

    receipt(envelope, findings)
  end

  @spec scan_many([map()], keyword()) :: map()
  def scan_many(envelopes, opts \\ []) when is_list(envelopes) and is_list(opts) do
    receipts = Enum.map(envelopes, &scan(&1, opts))
    findings = Enum.flat_map(receipts, &Map.fetch!(&1, "findings"))

    %{
      "schema_version" => @schema_version,
      "scanner_ref" => @scanner_ref,
      "status" => status(findings),
      "envelope_count" => length(envelopes),
      "receipts" => receipts,
      "findings" => findings
    }
  end

  @spec scan_file(Path.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def scan_file(path, opts \\ []) when is_binary(path) and is_list(opts) do
    with {:ok, envelope_or_envelopes} <- read_fixture(path) do
      envelopes = List.wrap(envelope_or_envelopes)
      {:ok, scan_many(envelopes, opts)}
    end
  end

  defp receipt(envelope, findings) do
    %{
      "schema_version" => @schema_version,
      "scanner_ref" => @scanner_ref,
      "status" => status(findings),
      "envelope_ref" => envelope_ref(envelope),
      "tenant_ref" => string_field(envelope, "tenant_ref"),
      "correlation_ref" => string_field(envelope, "correlation_ref"),
      "findings" => findings
    }
  end

  defp required_field_findings(envelope) do
    Enum.flat_map(@required_fields, fn field ->
      if present?(field_value(envelope, field)),
        do: [],
        else: [finding(:missing_required_field, :missing_required_field, [], %{"field" => field})]
    end)
  end

  defp schema_findings(envelope, opts) do
    cond do
      not any_present?(envelope, @schema_fields) ->
        [finding(:missing_schema, :missing_schema, [], %{"allowed_fields" => @schema_fields})]

      unsupported_schema?(envelope, opts) ->
        [
          finding(:version_mismatch, :unsupported_schema_version, [], %{
            "schema_version" => string_field(envelope, "schema_version")
          })
        ]

      true ->
        []
    end
  end

  defp authority_findings(envelope) do
    if present?(field_value(envelope, "authority_ref")) or
         field_value(envelope, "authority_required?") == false do
      []
    else
      [finding(:missing_authority, :missing_authority, [], %{})]
    end
  end

  defp trace_findings(envelope) do
    if any_present?(envelope, @trace_fields),
      do: [],
      else: [finding(:missing_trace, :missing_trace, [], %{"allowed_fields" => @trace_fields})]
  end

  defp tenant_findings(envelope) do
    tenant_ref = field_value(envelope, "tenant_ref")

    ~w(read_tenant_ref resource_tenant_ref target_tenant_ref)
    |> Enum.flat_map(fn field ->
      compare_tenant(field, tenant_ref, field_value(envelope, field))
    end)
  end

  defp direct_lower_findings(envelope) do
    @direct_lower_keys
    |> Enum.flat_map(fn field ->
      case field_value(envelope, field) do
        value when value in [nil, [], false] ->
          []

        value ->
          [
            finding(:direct_lower_import, :direct_lower_import_present, [field], %{
              "value" => safe_inspect(value)
            })
          ]
      end
    end)
  end

  defp walk(%_struct{} = value, path), do: walk(Map.from_struct(value), path)

  defp walk(value, path) when is_map(value) do
    Enum.flat_map(value, fn {key, nested_value} ->
      key_path = path ++ [to_string(key)]
      blocked_key_findings(key, nested_value, key_path) ++ walk(nested_value, key_path)
    end)
  end

  defp walk(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {nested_value, index} ->
      walk(nested_value, path ++ [Integer.to_string(index)])
    end)
  end

  defp walk(value, path) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.flat_map(fn {nested_value, index} ->
      walk(nested_value, path ++ [Integer.to_string(index)])
    end)
  end

  defp walk(value, path) when is_pid(value) or is_port(value) or is_reference(value) do
    [
      finding(:local_only_term, :local_only_runtime_term, path, %{
        "term_type" => local_term_type(value)
      })
    ]
  end

  defp walk(value, path) when is_function(value) do
    [finding(:local_only_term, :local_only_runtime_term, path, %{"term_type" => "function"})]
  end

  defp walk(_value, _path), do: []

  defp blocked_key_findings(key, value, path) do
    key_string = key |> to_string() |> String.downcase()

    cond do
      claim_check_ref_key?(key_string) ->
        []

      Enum.any?(@blocked_key_fragments, &String.contains?(key_string, &1)) ->
        [
          finding(:payload_not_allowed, :raw_or_sensitive_payload_field, path, %{
            "value" => safe_inspect(value)
          })
        ]

      true ->
        []
    end
  end

  defp claim_check_ref_key?(key) do
    (String.ends_with?(key, "_ref") or String.ends_with?(key, "_refs")) and
      not String.starts_with?(key, "raw_")
  end

  defp compare_tenant(_field, _tenant_ref, value) when value in [nil, ""], do: []

  defp compare_tenant(field, tenant_ref, value) do
    if tenant_ref == value do
      []
    else
      [
        finding(:cross_tenant_read, :tenant_ref_mismatch, [field], %{
          "tenant_ref" => tenant_ref,
          field => value
        })
      ]
    end
  end

  defp unsupported_schema?(envelope, opts) do
    supported = Keyword.get(opts, :supported_schema_versions, [])
    schema_version = field_value(envelope, "schema_version")
    supported != [] and present?(schema_version) and schema_version not in supported
  end

  defp any_present?(envelope, fields), do: Enum.any?(fields, &present?(field_value(envelope, &1)))

  defp field_value(map, field) when is_map(map) and is_binary(field) do
    Map.get(map, field, Map.get(map, String.to_atom(field)))
  end

  defp string_field(map, field) do
    case field_value(map, field) do
      value when is_binary(value) -> value
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      value when not is_nil(value) -> inspect(value)
      nil -> nil
    end
  end

  defp present?(value), do: not is_nil(value) and value != ""

  defp envelope_ref(envelope) do
    string_field(envelope, "envelope_ref") ||
      string_field(envelope, "correlation_ref") ||
      "envelope://stack_lab/gn-ten-node-lab/unknown"
  end

  defp status([]), do: "pass"
  defp status([_ | _]), do: "open_defect"

  defp finding(rule, reason, path, details) do
    %{
      "rule" => Atom.to_string(rule),
      "reason" => to_string(reason),
      "path" => path,
      "details" => details
    }
  end

  defp local_term_type(value) when is_pid(value), do: "pid"
  defp local_term_type(value) when is_port(value), do: "port"
  defp local_term_type(value) when is_reference(value), do: "reference"

  defp safe_inspect(value), do: inspect(value, limit: 20, printable_limit: 120)

  defp read_fixture(path) do
    case Path.extname(path) do
      ".exs" ->
        {fixture, _binding} = Code.eval_file(path)
        {:ok, fixture}

      ".json" ->
        path
        |> File.read()
        |> case do
          {:ok, body} -> Jason.decode(body)
          {:error, reason} -> {:error, failure("envelope_fixture_read_failed", reason)}
        end

      _other ->
        {:error, failure("unsupported_envelope_fixture")}
    end
  rescue
    error -> {:error, failure("envelope_fixture_eval_failed", Exception.message(error))}
  end

  defp failure(code, reason \\ nil), do: %{code: code, reason: inspect(reason)}
end
