defmodule StackLab.CoordinationFabricScanner.Finding do
  @moduledoc "Coordination fabric scanner finding."
  @enforce_keys [:rule, :reason, :path]
  defstruct [:details | @enforce_keys]
  @type t :: %__MODULE__{}
end

defmodule StackLab.CoordinationFabricScanner.Receipt do
  @moduledoc "Coordination fabric scanner receipt."
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

defmodule StackLab.CoordinationFabricScanner do
  @moduledoc """
  Governed TRINITY coordination fabric scanner.
  """

  alias StackLab.CoordinationFabricScanner.{Finding, Receipt}

  @fixture_refs ["AOC-026", "AOC-043"]
  @scanner_ref "stack-lab.coordination-fabric-scanner.v1"
  @rules [
    :router_artifact_refs,
    :router_eval_refs,
    :calibration_refs,
    :drift_detection_refs,
    :parity_check_refs,
    :role_prompt_refs,
    :provider_pool_refs,
    :governed_inference_boundary_ref,
    :verifier_refs,
    :handoff_scope_ref,
    :trace_refs,
    :replay_refs
  ]
  @required_string_rules [
    :governed_inference_boundary_ref,
    :handoff_scope_ref
  ]
  @raw_keys [
    :api_key,
    :auth_header,
    :credential_body,
    :memory_body,
    :model_output,
    :provider_payload,
    :raw_body,
    :raw_message,
    :raw_model_output,
    :raw_payload,
    :raw_prompt,
    :secret,
    :token,
    "api_key",
    "auth_header",
    "credential_body",
    "memory_body",
    "model_output",
    "provider_payload",
    "raw_body",
    "raw_message",
    "raw_model_output",
    "raw_payload",
    "raw_prompt",
    "secret",
    "token"
  ]

  @spec scan(map()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) do
    owner_repo = Map.get(attrs, :owner_repo, "stack_lab")
    package_path = Map.get(attrs, :package_path, "unknown")

    findings =
      attrs
      |> Map.get(:coordination_facts, [])
      |> List.wrap()
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {fact, index} -> fact_findings(fact, index) end)

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

  def scan(_attrs), do: {:error, :invalid_coordination_fabric_scan}

  defp fact_findings(fact, index) when is_map(fact) do
    path = fact_path(index)

    required_findings =
      Enum.flat_map(@rules, fn field ->
        if field in @required_string_rules do
          required_string_findings(fact, field, path)
        else
          required_list_findings(fact, field, path)
        end
      end)

    required_findings ++ redaction_findings(fact, path) ++ raw_findings(fact, path)
  end

  defp fact_findings(_fact, index) do
    [finding(:router_artifact_refs, :invalid_coordination_fact, fact_path(index), %{})]
  end

  defp redaction_findings(fact, path) do
    if fetch(fact, :trace_redaction, :redacted) == :redacted do
      []
    else
      [finding(:trace_refs, :trace_refs_not_redacted, path, %{})]
    end
  end

  defp raw_findings(fact, path) do
    case raw_key(fact) do
      nil -> []
      key -> [finding(:raw_payload, {:forbidden_raw_field, key}, path, %{})]
    end
  end

  defp raw_key(%_struct{} = value), do: value |> Map.from_struct() |> raw_key()

  defp raw_key(value) when is_map(value) do
    Enum.find_value(value, fn {key, nested} ->
      if key in @raw_keys, do: key, else: raw_key(nested)
    end)
  end

  defp raw_key(values) when is_list(values), do: Enum.find_value(values, &raw_key/1)
  defp raw_key(_value), do: nil

  defp required_string_findings(fact, field, path) do
    if present_string?(fetch(fact, field)) do
      []
    else
      [finding(field, :missing_required_ref, path, %{})]
    end
  end

  defp required_list_findings(fact, field, path) do
    if non_empty_string_list?(fetch(fact, field)) do
      []
    else
      [finding(field, :missing_required_refs, path, %{})]
    end
  end

  defp non_empty_string_list?(values) when is_list(values) and values != [] do
    Enum.all?(values, &present_string?/1)
  end

  defp non_empty_string_list?(_values), do: false
  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp fetch(fact, field, default \\ nil) do
    string_field = Atom.to_string(field)

    cond do
      Map.has_key?(fact, field) -> Map.fetch!(fact, field)
      Map.has_key?(fact, string_field) -> Map.fetch!(fact, string_field)
      true -> default
    end
  end

  defp fact_path(index), do: "coordination_fact:" <> Integer.to_string(index)
  defp status([]), do: :pass
  defp status([_ | _]), do: :open_defect

  defp receipt_ref(owner_repo, package_path),
    do: "coordination-fabric-scan://#{owner_repo}/#{package_path}"

  defp finding(rule, reason, path, details),
    do: %Finding{rule: rule, reason: reason, path: path, details: details}
end
