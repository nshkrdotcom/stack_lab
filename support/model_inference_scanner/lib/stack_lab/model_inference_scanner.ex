defmodule StackLab.ModelInferenceScanner.Finding do
  @moduledoc "Model inference scanner finding."
  @enforce_keys [:rule, :reason, :path]
  defstruct [:details | @enforce_keys]
  @type t :: %__MODULE__{}
end

defmodule StackLab.ModelInferenceScanner.Receipt do
  @moduledoc "Model inference scanner receipt."
  @enforce_keys [
    :receipt_ref,
    :fixture_ref,
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

defmodule StackLab.ModelInferenceScanner do
  @moduledoc """
  Governed model inference boundary scanner.
  """

  alias StackLab.ModelInferenceScanner.{Finding, Receipt}

  @fixture_ref "AOC-041"
  @scanner_ref "stack-lab.model-inference-scanner.v1"
  @rules [
    :ambient_provider_fallback,
    :raw_key_projection,
    :endpoint_provider_identity_merge,
    :missing_model_profile_ref,
    :missing_endpoint_profile_ref,
    :missing_operation_policy_ref
  ]
  @fallback_tokens [
    Enum.join(["System", "get_env"], "."),
    Enum.join(["Application", "get_env"], "."),
    Enum.join(["OPENAI", "API", "KEY"], "_"),
    Enum.join(["ANTHROPIC", "API", "KEY"], "_"),
    Enum.join(["GEMINI", "API", "KEY"], "_")
  ]
  @raw_key_tokens [
    Enum.join(["api", "key"], "_"),
    Enum.join(["raw", "api", "key"], "_"),
    "auth_header",
    "Authorization"
  ]

  @spec scan(map()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) do
    owner_repo = Map.get(attrs, :owner_repo, "stack_lab")
    package_path = Map.get(attrs, :package_path, "unknown")

    findings =
      attrs
      |> source_units()
      |> Enum.flat_map(&source_findings/1)
      |> Kernel.++(runtime_findings(List.wrap(Map.get(attrs, :runtime_facts, []))))

    {:ok,
     %Receipt{
       receipt_ref: receipt_ref(owner_repo, package_path),
       fixture_ref: @fixture_ref,
       scanner_ref: @scanner_ref,
       owner_repo: owner_repo,
       package_path: package_path,
       status: status(findings),
       checked_rules: @rules,
       findings: findings
     }}
  end

  def scan(_attrs), do: {:error, :invalid_model_inference_scan}

  defp source_units(attrs) do
    inline_units = List.wrap(Map.get(attrs, :source_units, []))

    path_units =
      attrs
      |> Map.get(:source_paths, [])
      |> List.wrap()
      |> Enum.map(&path_unit/1)

    inline_units ++ path_units
  end

  defp path_unit(path) when is_binary(path) do
    source = if File.regular?(path), do: File.read!(path), else: ""
    %{path: path, source: source, missing?: source == ""}
  end

  defp source_findings(%{missing?: true, path: path}) do
    [finding(:ambient_provider_fallback, :missing_source_path, path, %{})]
  end

  defp source_findings(unit) when is_map(unit) do
    source = Map.get(unit, :source, "")
    path = Map.get(unit, :path, "inline")

    []
    |> maybe_add(source_contains?(source, @fallback_tokens), fn ->
      finding(:ambient_provider_fallback, :ambient_provider_fallback_signal, path, %{})
    end)
    |> maybe_add(source_contains?(source, @raw_key_tokens), fn ->
      finding(:raw_key_projection, :raw_key_projection_signal, path, %{})
    end)
  end

  defp source_findings(_unit), do: []

  defp runtime_findings(facts) do
    facts
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {fact, index} -> runtime_fact_findings(fact, index) end)
  end

  defp runtime_fact_findings(fact, index) when is_map(fact) do
    []
    |> maybe_add(not present_string?(fact, :model_profile_ref), fn ->
      finding(:missing_model_profile_ref, :missing_model_profile_ref, runtime_path(index), %{})
    end)
    |> maybe_add(not present_string?(fact, :endpoint_profile_ref), fn ->
      finding(
        :missing_endpoint_profile_ref,
        :missing_endpoint_profile_ref,
        runtime_path(index),
        %{}
      )
    end)
    |> maybe_add(not present_string?(fact, :operation_policy_ref), fn ->
      finding(
        :missing_operation_policy_ref,
        :missing_operation_policy_ref,
        runtime_path(index),
        %{}
      )
    end)
    |> maybe_add(merged_endpoint_provider_identity?(fact), fn ->
      finding(
        :endpoint_provider_identity_merge,
        :endpoint_identity_matches_provider_credential,
        runtime_path(index),
        %{}
      )
    end)
  end

  defp runtime_fact_findings(_fact, index),
    do: [finding(:missing_model_profile_ref, :invalid_runtime_fact, runtime_path(index), %{})]

  defp merged_endpoint_provider_identity?(fact) do
    endpoint = fetch(fact, :endpoint_identity_ref)
    provider = fetch(fact, :provider_credential_ref)
    is_binary(endpoint) and endpoint == provider
  end

  defp source_contains?(source, tokens) when is_binary(source) do
    Enum.any?(tokens, &String.contains?(source, &1))
  end

  defp source_contains?(_source, _tokens), do: false

  defp maybe_add(findings, true, fun), do: findings ++ [fun.()]
  defp maybe_add(findings, false, _fun), do: findings

  defp present_string?(fact, field) do
    value = fetch(fact, field)
    is_binary(value) and String.trim(value) != ""
  end

  defp fetch(fact, field) do
    string_field = Atom.to_string(field)

    cond do
      Map.has_key?(fact, field) -> Map.fetch!(fact, field)
      Map.has_key?(fact, string_field) -> Map.fetch!(fact, string_field)
      true -> nil
    end
  end

  defp runtime_path(index), do: "runtime_fact:" <> Integer.to_string(index)
  defp status([]), do: :pass
  defp status([_ | _]), do: :open_defect

  defp receipt_ref(owner_repo, package_path),
    do: "model-inference-scan://#{owner_repo}/#{package_path}"

  defp finding(rule, reason, path, details),
    do: %Finding{rule: rule, reason: reason, path: path, details: details}
end
