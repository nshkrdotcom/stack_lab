defmodule StackLab.StructuralGate.Allowlists do
  @moduledoc """
  Structural scanner allowlist normalization, validation, and matching.
  """

  alias StackLab.StructuralGateScanner.{AllowlistEntry, Finding}

  @protected_allowlist_fragments [
    "/app_kit/core/",
    "/mezzanine/core/workflow_runtime/",
    "/mezzanine/core/source_engine/",
    "/mezzanine/core/projection_engine/",
    "/mezzanine/core/evidence_engine/",
    "/citadel/core/policy_packs/",
    "/stack_lab/examples/toy_document_review/"
  ]

  @spec normalize([map() | keyword() | AllowlistEntry.t()]) ::
          {:ok, [AllowlistEntry.t()]} | {:error, term()}
  def normalize(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case normalize_entry(entry) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec validate([AllowlistEntry.t()]) :: :ok | {:error, term()}
  def validate(entries) do
    case Enum.find(entries, &blanket_protected_allowlist?/1) do
      nil -> :ok
      entry -> {:error, {:blanket_allowlist_rejected, entry.path}}
    end
  end

  @spec apply(Finding.t(), [AllowlistEntry.t()]) :: Finding.t()
  def apply(%Finding{} = finding, allowlist) do
    case Enum.find(allowlist, &matches?(&1, finding)) do
      nil -> finding
      entry -> %{finding | allowlist_entry: entry, severity: :warning}
    end
  end

  defp normalize_entry(%AllowlistEntry{} = entry), do: {:ok, entry}

  defp normalize_entry(entry) when is_list(entry) or is_map(entry) do
    map = normalize_map(entry)

    required = [:token, :path, :reason, :owner, :expires, :permanent_zone]
    missing = Enum.reject(required, &Map.has_key?(map, &1))

    case missing do
      [] -> {:ok, struct!(AllowlistEntry, Map.take(map, required))}
      [_ | _] -> {:error, {:invalid_allowlist_entry, :missing_keys, missing}}
    end
  end

  defp normalize_map(value) when is_list(value), do: value |> Map.new() |> normalize_map()

  defp normalize_map(value) when is_map(value) do
    Map.new(value, fn
      {key, val} when is_binary(key) -> {string_key(key), val}
      {key, val} -> {key, val}
    end)
  end

  defp string_key("token"), do: :token
  defp string_key("path"), do: :path
  defp string_key("reason"), do: :reason
  defp string_key("owner"), do: :owner
  defp string_key("expires"), do: :expires
  defp string_key("permanent_zone"), do: :permanent_zone
  defp string_key(key), do: key

  defp blanket_protected_allowlist?(%AllowlistEntry{} = entry) do
    broad_path?(entry.path) and
      Enum.any?(@protected_allowlist_fragments, &String.contains?(entry.path, &1))
  end

  defp broad_path?(path) do
    String.ends_with?(path, "/**") or String.ends_with?(path, "/*") or path == "*"
  end

  defp matches?(%AllowlistEntry{} = entry, %Finding{} = finding) do
    token_match?(entry.token, finding.token) and path_match?(entry.path, finding.path)
  end

  defp token_match?(:any, _token), do: true
  defp token_match?("any", _token), do: true
  defp token_match?(token, finding_token), do: to_string(token) == to_string(finding_token)

  defp path_match?("*", _path), do: true

  defp path_match?(entry_path, finding_path) do
    cond do
      String.ends_with?(entry_path, "/**") ->
        prefix = trim_suffix(entry_path, "/**")
        String.starts_with?(finding_path, prefix <> "/") or finding_path == prefix

      String.ends_with?(entry_path, "/*") ->
        prefix = trim_suffix(entry_path, "/*")
        Path.dirname(finding_path) == prefix

      true ->
        finding_path == entry_path
    end
  end

  defp trim_suffix(value, suffix) do
    binary_part(value, 0, byte_size(value) - byte_size(suffix))
  end
end
