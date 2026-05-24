defmodule StackLab.ContextABIScanner.Finding do
  @moduledoc "Context ABI scanner finding."
  @enforce_keys [:rule, :reason, :path]
  defstruct [:details | @enforce_keys]
  @type t :: %__MODULE__{}
end

defmodule StackLab.ContextABIScanner.Receipt do
  @moduledoc "Context ABI scanner receipt."
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

defmodule StackLab.ContextABIScanner do
  @moduledoc """
  Ref-only Context ABI proof scanner.

  The scanner is intentionally evidence-driven. It accepts facts emitted by a
  proof harness and checks required refs, tenant consistency, raw-payload
  absence, and the named handoffs across the fugu Context ABI path.
  """

  alias StackLab.ContextABIScanner.{Finding, Receipt}

  @fixture_refs ["AOC-CTX-001", "AOC-CTX-002", "AOC-CTX-003"]
  @scanner_ref "stack-lab.context-abi-scanner.v1"
  @rules [
    :no_raw_context_payloads,
    :context_packet_contract,
    :context_receipt_contract,
    :authority_grant_contract,
    :admission_receipt_contract,
    :route_decision_contract,
    :render_handoff_contract,
    :model_invocation_contract,
    :appkit_projection_contract,
    :aitrace_linkage_contract,
    :tenant_consistency,
    :handoff_ref_consistency
  ]
  @raw_keys MapSet.new(~w(
              access_token
              api_key
              auth_header
              authorization
              body
              credential
              credential_body
              credential_material
              memory_body
              memory_content
              model_output
              operator_private_payload
              password
              payload
              prompt
              prompt_body
              prompt_content
              prompt_text
              provider_payload
              provider_response
              raw
              raw_body
              raw_memory
              raw_model_output
              raw_payload
              raw_prompt
              raw_provider_payload
              refresh_token
              request_body
              response_body
              secret
              secret_token
              stderr
              stdout
              token
            ))

  @fact_groups %{
    context_packets: [
      :tenant_ref,
      :context_packet_ref,
      :packet_hash,
      :user_request_ref,
      :system_instruction_ref,
      :budget_ref,
      :model_class_allowlist,
      :route_policy_ref,
      :trace_ref
    ],
    context_compile_receipts: [
      :receipt_ref,
      :context_packet_ref,
      :tenant_ref,
      :status,
      :packet_hash,
      :trace_ref
    ],
    authority_grants: [
      :authority_ref,
      :tenant_ref,
      :allowed_model_classes,
      :route_policy_ref,
      :trace_ref
    ],
    admission_receipts: [
      :receipt_ref,
      :context_packet_ref,
      :workflow_ref,
      :tenant_ref,
      :authority_ref,
      :packet_hash,
      :status,
      :idempotency_key,
      :trace_ref
    ],
    route_decisions: [
      :route_decision_ref,
      :selected_route_kind,
      :selected_model_profile_ref,
      :route_policy_ref,
      :trace_ref
    ],
    render_results: [
      :tenant_ref,
      :workflow_ref,
      :context_packet_ref,
      :route_decision_ref,
      :prompt_artifact_ref,
      :provider_payload_ref,
      :payload_hash,
      :provider_family,
      :trace_ref
    ],
    model_invocation_receipts: [
      :receipt_ref,
      :invocation_ref,
      :tenant_ref,
      :status,
      :context_packet_ref,
      :route_decision_ref,
      :prompt_artifact_ref,
      :provider_payload_ref,
      :payload_hash,
      :model_profile_ref,
      :provider_ref,
      :endpoint_ref,
      :runtime_ref,
      :runtime_kind,
      :credential_lease_ref,
      :trace_ref,
      :idempotency_key
    ]
  }

  @spec scan(map()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) do
    owner_repo = fetch(attrs, :owner_repo, "stack_lab")
    package_path = fetch(attrs, :package_path, "unknown")

    findings =
      attrs
      |> group_findings()
      |> Kernel.++(appkit_projection_findings(attrs))
      |> Kernel.++(aitrace_linkage_findings(attrs))
      |> Kernel.++(raw_payload_findings(attrs))
      |> Kernel.++(tenant_consistency_findings(attrs))
      |> Kernel.++(handoff_findings(attrs))

    {:ok,
     %Receipt{
       receipt_ref: receipt_ref(owner_repo, package_path),
       fixture_refs: @fixture_refs,
       scanner_ref: @scanner_ref,
       owner_repo: owner_repo,
       package_path: package_path,
       status: status(findings),
       checked_rules: @rules,
       findings: findings
     }}
  end

  def scan(_attrs), do: {:error, :invalid_context_abi_scan}

  defp group_findings(attrs) do
    @fact_groups
    |> Enum.flat_map(fn {group, required_fields} ->
      attrs
      |> facts(group)
      |> required_group_findings(group, required_fields)
    end)
  end

  defp required_group_findings([], group, _required_fields) do
    [finding(rule_for_group(group), :missing_fact_group, Atom.to_string(group), %{})]
  end

  defp required_group_findings(facts, group, required_fields) do
    facts
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {fact, index} ->
      path = "#{group}:#{index}"

      Enum.flat_map(required_fields, fn field ->
        cond do
          field in [:model_class_allowlist, :allowed_model_classes] and
              not non_empty_strings?(value(fact, field)) ->
            [finding(rule_for_group(group), {:missing_required_refs, field}, path, %{})]

          field in [:runtime_kind, :selected_route_kind, :status] and is_nil(value(fact, field)) ->
            [finding(rule_for_group(group), {:missing_required_field, field}, path, %{})]

          field not in [
            :model_class_allowlist,
            :allowed_model_classes,
            :runtime_kind,
            :selected_route_kind,
            :status
          ] and
              not present_string?(value(fact, field)) ->
            [finding(rule_for_group(group), {:missing_required_ref, field}, path, %{})]

          field in [:packet_hash, :payload_hash] and not sha256?(value(fact, field)) ->
            [finding(rule_for_group(group), {:invalid_sha256_ref, field}, path, %{})]

          true ->
            []
        end
      end)
    end)
  end

  defp appkit_projection_findings(attrs) do
    case facts(attrs, :appkit_projections) do
      [] ->
        [
          finding(
            :appkit_projection_contract,
            :missing_fact_group,
            "appkit_projections",
            %{}
          )
        ]

      projections ->
        projections
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {projection, index} ->
          if projection_ref?(projection) do
            []
          else
            [
              finding(
                :appkit_projection_contract,
                :missing_projection_ref,
                "appkit_projections:#{index}",
                %{}
              )
            ]
          end
        end)
    end
  end

  defp aitrace_linkage_findings(attrs) do
    case facts(attrs, :aitrace_facts) do
      [] ->
        [finding(:aitrace_linkage_contract, :missing_fact_group, "aitrace_facts", %{})]

      trace_facts ->
        trace_facts
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {fact, index} ->
          if present_string?(value(fact, :trace_ref)) do
            []
          else
            [
              finding(
                :aitrace_linkage_contract,
                {:missing_required_ref, :trace_ref},
                "aitrace_facts:#{index}",
                %{}
              )
            ]
          end
        end)
    end
  end

  defp raw_payload_findings(attrs) do
    case raw_key(attrs) do
      nil -> []
      key -> [finding(:no_raw_context_payloads, {:forbidden_raw_field, key}, "scan", %{})]
    end
  end

  defp tenant_consistency_findings(attrs) do
    tenants =
      attrs
      |> all_facts()
      |> Enum.map(&value(&1, :tenant_ref))
      |> Enum.filter(&present_string?/1)
      |> Enum.uniq()

    case tenants do
      [] -> [finding(:tenant_consistency, :missing_tenant_refs, "scan", %{})]
      [_tenant] -> []
      tenants -> [finding(:tenant_consistency, :cross_tenant_refs, "scan", %{tenants: tenants})]
    end
  end

  defp handoff_findings(attrs) do
    packet = first_fact(attrs, :context_packets)
    admission = first_fact(attrs, :admission_receipts)
    route = first_fact(attrs, :route_decisions)
    render = first_fact(attrs, :render_results)
    model = first_fact(attrs, :model_invocation_receipts)

    []
    |> ensure_same(:context_packet_ref, packet, admission, "packet->admission")
    |> ensure_same(:context_packet_ref, packet, render, "packet->render")
    |> ensure_same(:context_packet_ref, packet, model, "packet->model")
    |> ensure_same(:route_decision_ref, route, render, "route->render")
    |> ensure_same(:route_decision_ref, route, model, "route->model")
    |> ensure_same(:prompt_artifact_ref, render, model, "render->model")
    |> ensure_same(:provider_payload_ref, render, model, "render->model")
    |> ensure_same(:payload_hash, render, model, "render->model")
  end

  defp ensure_same(findings, _field, nil, _right, _path), do: findings
  defp ensure_same(findings, _field, _left, nil, _path), do: findings

  defp ensure_same(findings, field, left, right, path) do
    if value(left, field) == value(right, field) do
      findings
    else
      [
        finding(:handoff_ref_consistency, {:mismatched_ref, field}, path, %{
          left: value(left, field),
          right: value(right, field)
        })
        | findings
      ]
    end
  end

  defp facts(attrs, group), do: attrs |> fetch(group, []) |> List.wrap() |> Enum.map(&plain/1)
  defp first_fact(attrs, group), do: attrs |> facts(group) |> List.first()

  defp all_facts(attrs) do
    groups = Map.keys(@fact_groups) ++ [:appkit_projections, :aitrace_facts]
    Enum.flat_map(groups, &facts(attrs, &1))
  end

  defp projection_ref?(projection) do
    Enum.any?(
      [
        :context_packet_ref,
        :route_decision_ref,
        :model_invocation_ref,
        :eval_verdict_ref,
        :review_ref
      ],
      &present_string?(value(projection, &1))
    )
  end

  defp rule_for_group(:context_packets), do: :context_packet_contract
  defp rule_for_group(:context_compile_receipts), do: :context_receipt_contract
  defp rule_for_group(:authority_grants), do: :authority_grant_contract
  defp rule_for_group(:admission_receipts), do: :admission_receipt_contract
  defp rule_for_group(:route_decisions), do: :route_decision_contract
  defp rule_for_group(:render_results), do: :render_handoff_contract
  defp rule_for_group(:model_invocation_receipts), do: :model_invocation_contract

  defp plain(%_struct{} = value), do: value |> Map.from_struct() |> plain()

  defp plain(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {key, plain(nested)} end)
  end

  defp plain(values) when is_list(values), do: Enum.map(values, &plain/1)
  defp plain(value), do: value

  defp raw_key(%_struct{} = value), do: value |> Map.from_struct() |> raw_key()

  defp raw_key(value) when is_map(value) do
    Enum.find_value(value, fn {key, nested} ->
      key_string = key |> to_string() |> String.downcase()

      cond do
        MapSet.member?(@raw_keys, key_string) -> key_string
        String.starts_with?(key_string, "raw_") -> key_string
        true -> raw_key(nested)
      end
    end)
  end

  defp raw_key(values) when is_list(values), do: Enum.find_value(values, &raw_key/1)
  defp raw_key(_value), do: nil

  defp value(fact, field) when is_map(fact) do
    Map.get(fact, field) || Map.get(fact, Atom.to_string(field))
  end

  defp value(_fact, _field), do: nil

  defp fetch(attrs, field, default) do
    Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field), default)
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp non_empty_strings?(values) when is_list(values) and values != [] do
    Enum.all?(values, &present_string?/1)
  end

  defp non_empty_strings?(_values), do: false

  defp sha256?("sha256:" <> digest), do: String.length(digest) == 64
  defp sha256?(_value), do: false

  defp status([]), do: :pass
  defp status([_ | _]), do: :open_defect

  defp receipt_ref(owner_repo, package_path) do
    package = String.replace(package_path, "/", "-")
    "context-abi-scan://#{owner_repo}/#{package}"
  end

  defp finding(rule, reason, path, details),
    do: %Finding{rule: rule, reason: reason, path: path, details: details}
end
