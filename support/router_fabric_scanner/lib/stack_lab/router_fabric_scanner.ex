defmodule StackLab.RouterFabricScanner.Finding do
  @moduledoc "Router fabric scanner finding."
  @enforce_keys [:rule, :reason, :path]
  defstruct [:details | @enforce_keys]
  @type t :: %__MODULE__{}
end

defmodule StackLab.RouterFabricScanner.Receipt do
  @moduledoc "Router fabric scanner receipt."
  @enforce_keys [
    :receipt_ref,
    :fixture_refs,
    :scanner_ref,
    :owner_repo,
    :package_path,
    :status,
    :checked_rules,
    :findings
  ]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end

defmodule StackLab.RouterFabricScanner do
  @moduledoc """
  Ref-only router fabric proof scanner.
  """

  alias StackLab.RouterFabricScanner.{Finding, Receipt}

  @fixture_refs ["AOC-026", "AOC-036", "AOC-043", "AOC-ROUTER-001"]
  @scanner_ref "stack-lab.router-fabric-scanner.v1"
  @rules [
    :no_raw_route_payloads,
    :route_request_contract,
    :route_decision_contract,
    :trinity_adapter_contract,
    :route_policy_consistency,
    :authority_consistency,
    :selected_model_allowlist,
    :handoff_ref_consistency
  ]
  @raw_keys MapSet.new(~w(
              access_token
              api_key
              auth_header
              authorization
              credential
              credential_body
              memory_body
              model_output
              payload
              prompt
              prompt_body
              provider_payload
              provider_response
              raw
              raw_body
              raw_memory
              raw_model_output
              raw_payload
              raw_prompt
              secret
              token
            ))
  @request_fields [
    :tenant_ref,
    :workflow_ref,
    :context_packet_ref,
    :packet_hash,
    :authority_ref,
    :route_policy_ref,
    :model_class_allowlist,
    :model_class_profile_map,
    :trace_ref
  ]
  @decision_fields [
    :route_decision_ref,
    :context_packet_ref,
    :packet_hash,
    :selected_route_kind,
    :selected_model_profile_ref,
    :provider_or_runtime_ref,
    :route_policy_ref,
    :authority_packet_ref,
    :reason_codes,
    :trace_ref
  ]
  @list_ref_fields [:model_class_allowlist, :reason_codes]
  @literal_required_fields [:selected_route_kind, :confidence_band]

  @spec scan(map()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) do
    owner_repo = fetch(attrs, :owner_repo, "stack_lab")
    package_path = fetch(attrs, :package_path, "unknown")

    findings =
      []
      |> Kernel.++(route_request_findings(facts(attrs, :route_requests)))
      |> Kernel.++(route_decision_findings(facts(attrs, :route_decisions)))
      |> Kernel.++(trinity_findings(facts(attrs, :route_decisions)))
      |> Kernel.++(raw_findings(attrs))
      |> Kernel.++(consistency_findings(attrs))

    {:ok,
     %Receipt{
       receipt_ref: "router-fabric-scan://#{owner_repo}/#{package_path}",
       fixture_refs: @fixture_refs,
       scanner_ref: @scanner_ref,
       owner_repo: owner_repo,
       package_path: package_path,
       status: status(findings),
       checked_rules: @rules,
       findings: findings
     }}
  end

  def scan(_attrs), do: {:error, :invalid_router_fabric_scan}

  defp route_request_findings([]) do
    [finding(:route_request_contract, :missing_fact_group, "route_requests", %{})]
  end

  defp route_request_findings(requests) do
    requests
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {request, index} ->
      required_findings(
        request,
        @request_fields,
        :route_request_contract,
        "route_requests:#{index}"
      )
    end)
  end

  defp route_decision_findings([]) do
    [finding(:route_decision_contract, :missing_fact_group, "route_decisions", %{})]
  end

  defp route_decision_findings(decisions) do
    decisions
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {decision, index} ->
      path = "route_decisions:#{index}"

      required_findings(decision, @decision_fields, :route_decision_contract, path) ++
        sha_findings(decision, path)
    end)
  end

  defp trinity_findings(decisions) do
    decisions
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {decision, index} ->
      if fetch(decision, :selected_route_kind) == :trinity_coordinated do
        trinity = fetch(decision, :trinity, %{})
        path = "route_decisions:#{index}.trinity"

        required_findings(
          trinity,
          [:router_artifact_ref, :extractor_ref, :head_ref, :selected_role_ref, :confidence_band],
          :trinity_adapter_contract,
          path
        )
      else
        []
      end
    end)
  end

  defp raw_findings(attrs) do
    attrs
    |> raw_paths()
    |> Enum.map(fn {path, key} ->
      finding(:no_raw_route_payloads, {:forbidden_raw_field, key}, path, %{})
    end)
  end

  defp consistency_findings(attrs) do
    request = attrs |> facts(:route_requests) |> List.first()
    decision = attrs |> facts(:route_decisions) |> List.first()

    if is_nil(request) or is_nil(decision) do
      []
    else
      []
      |> maybe_consistency_finding(
        fetch(request, :route_policy_ref) == fetch(decision, :route_policy_ref),
        :route_policy_consistency,
        :route_policy_mismatch
      )
      |> maybe_consistency_finding(
        fetch(request, :authority_ref) == fetch(decision, :authority_packet_ref),
        :authority_consistency,
        :authority_ref_mismatch
      )
      |> maybe_consistency_finding(
        fetch(request, :context_packet_ref) == fetch(decision, :context_packet_ref) and
          fetch(request, :packet_hash) == fetch(decision, :packet_hash),
        :handoff_ref_consistency,
        :packet_ref_mismatch
      )
      |> maybe_consistency_finding(
        selected_model_allowed?(request, decision),
        :selected_model_allowlist,
        :selected_model_not_allowed
      )
    end
  end

  defp required_findings(fact, fields, rule, path) when is_map(fact) do
    Enum.flat_map(fields, fn field ->
      required_field_findings(fact, field, rule, path)
    end)
  end

  defp required_findings(_fact, _fields, rule, path),
    do: [finding(rule, :invalid_fact, path, %{})]

  defp required_field_findings(fact, field, rule, path) when field in @list_ref_fields do
    fact
    |> fetch(field)
    |> non_empty_strings?()
    |> required_field_result(rule, {:missing_required_refs, field}, path)
  end

  defp required_field_findings(fact, :model_class_profile_map = field, rule, path) do
    fact
    |> fetch(field)
    |> model_class_profile_map?()
    |> required_field_result(rule, {:invalid_model_class_profile_map, field}, path)
  end

  defp required_field_findings(fact, field, rule, path) when field in @literal_required_fields do
    fact
    |> fetch(field)
    |> is_nil()
    |> Kernel.not()
    |> required_field_result(rule, {:missing_required_field, field}, path)
  end

  defp required_field_findings(fact, field, rule, path) do
    fact
    |> fetch(field)
    |> present_string?()
    |> required_field_result(rule, {:missing_required_ref, field}, path)
  end

  defp required_field_result(true, _rule, _reason, _path), do: []

  defp required_field_result(false, rule, reason, path),
    do: [finding(rule, reason, path, %{})]

  defp sha_findings(decision, path) do
    if sha256?(fetch(decision, :packet_hash)) do
      []
    else
      [finding(:route_decision_contract, {:invalid_sha256_ref, :packet_hash}, path, %{})]
    end
  end

  defp maybe_consistency_finding(findings, true, _rule, _reason), do: findings

  defp maybe_consistency_finding(findings, false, rule, reason) do
    [finding(rule, reason, "route_request->route_decision", %{}) | findings]
  end

  defp selected_model_allowed?(request, decision) do
    selected_profile_ref = fetch(decision, :selected_model_profile_ref)
    model_classes = fetch(request, :model_class_allowlist, [])
    profile_map = fetch(request, :model_class_profile_map, %{})

    model_classes
    |> Enum.flat_map(fn class_ref -> List.wrap(Map.get(profile_map, class_ref, [])) end)
    |> Enum.any?(&(&1 == selected_profile_ref))
  end

  defp facts(attrs, key) do
    attrs
    |> fetch(key, [])
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
  end

  defp raw_paths(value, path \\ "$")
  defp raw_paths(%_struct{} = value, path), do: value |> Map.from_struct() |> raw_paths(path)

  defp raw_paths(value, path) when is_map(value) do
    Enum.flat_map(value, fn {key, nested} ->
      key_string = to_string(key)
      next_path = path <> "." <> key_string

      if MapSet.member?(@raw_keys, key_string) do
        [{next_path, key_string}]
      else
        raw_paths(nested, next_path)
      end
    end)
  end

  defp raw_paths(values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} -> raw_paths(value, "#{path}[#{index}]") end)
  end

  defp raw_paths(_value, _path), do: []

  defp non_empty_strings?(values) when is_list(values) and values != [],
    do: Enum.all?(values, &present_string?/1)

  defp non_empty_strings?(_values), do: false

  defp model_class_profile_map?(value) when is_map(value) and map_size(value) > 0 do
    Enum.all?(value, fn {class_ref, profile_refs} ->
      present_string?(class_ref) and non_empty_strings?(List.wrap(profile_refs))
    end)
  end

  defp model_class_profile_map?(_value), do: false
  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp sha256?(value), do: is_binary(value) and String.match?(value, ~r/^sha256:[0-9a-f]{64}$/)

  defp fetch(%{} = attrs, field), do: fetch(attrs, field, nil)

  defp fetch(%_struct{} = value, field, default),
    do: value |> Map.from_struct() |> fetch(field, default)

  defp fetch(%{} = attrs, field, default) do
    string_field = Atom.to_string(field)

    cond do
      Map.has_key?(attrs, field) -> Map.fetch!(attrs, field)
      Map.has_key?(attrs, string_field) -> Map.fetch!(attrs, string_field)
      true -> default
    end
  end

  defp fetch(_other, _field, default), do: default
  defp status([]), do: :pass
  defp status([_ | _]), do: :open_defect

  defp finding(rule, reason, path, details),
    do: %Finding{rule: rule, reason: reason, path: path, details: details}
end
