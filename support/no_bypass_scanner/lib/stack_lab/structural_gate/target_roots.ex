defmodule StackLab.StructuralGate.TargetRoots do
  @moduledoc """
  Target repo root loading and scan-scope validation for structural gates.
  """

  @manifest_path Path.expand("../../../../../gn-ten.yml", __DIR__)
  @fallback_root_base Path.expand("../../../../../../", __DIR__)
  @expected_repos ~w(
    ground_plane
    execution_plane
    jido_integration
    citadel
    outer_brain
    mezzanine
    app_kit
    extravaganza
    stack_lab
    AITrace
  )

  @fallback_roots Map.new(@expected_repos, &{&1, Path.join(@fallback_root_base, &1)})

  @spec expected_repos() :: [String.t()]
  def expected_repos, do: @expected_repos

  @spec default() :: %{String.t() => String.t()}
  def default do
    case from_manifest(@manifest_path) do
      {:ok, roots} -> roots
      {:error, _reason} -> normalize(@fallback_roots)
    end
  end

  @spec from_manifest(String.t()) :: {:ok, %{String.t() => String.t()}} | {:error, term()}
  def from_manifest(path) do
    with {:ok, content} <- File.read(path),
         roots when map_size(roots) > 0 <- parse_roots(content) do
      {:ok, normalize(roots)}
    else
      {:error, reason} -> {:error, {:manifest_read_failed, path, reason}}
      _empty -> {:error, {:manifest_missing_repo_roots, path}}
    end
  end

  @spec normalize(%{String.t() => String.t()} | [{String.t(), String.t()}]) :: %{
          String.t() => String.t()
        }
  def normalize(roots) when is_map(roots) do
    roots
    |> Enum.map(fn {repo, path} -> {to_string(repo), Path.expand(path)} end)
    |> Map.new()
  end

  def normalize(roots) when is_list(roots), do: roots |> Map.new() |> normalize()

  @spec all_paths(map()) :: [String.t()]
  def all_paths(target_roots) do
    target_roots
    |> Enum.sort_by(fn {repo, _path} -> repo end)
    |> Enum.map(fn {_repo, path} -> path end)
  end

  @spec validate_scope([String.t()], map()) :: {:ok, [String.t()]} | {:error, term()}
  def validate_scope(paths, target_roots) do
    expanded_paths = Enum.map(paths, &Path.expand/1)
    outside_paths = Enum.reject(expanded_paths, &target_path?(&1, target_roots))

    case outside_paths do
      [] -> {:ok, expanded_paths}
      _ -> {:error, {:outside_target_scope, outside_paths}}
    end
  end

  @spec target_path?(String.t(), map()) :: boolean()
  def target_path?(path, target_roots) do
    Enum.any?(target_roots, fn {_repo, root} ->
      path == root or String.starts_with?(path, root <> "/")
    end)
  end

  @spec scope_status(map()) :: :exact_target_roots | :custom_target_roots
  def scope_status(target_roots) do
    if target_roots |> Map.keys() |> Enum.sort() == Enum.sort(@expected_repos) do
      :exact_target_roots
    else
      :custom_target_roots
    end
  end

  defp parse_roots(content) do
    content
    |> String.split("\n")
    |> Enum.reduce({%{}, nil}, &parse_line/2)
    |> elem(0)
  end

  defp parse_line(line, {roots, current_name}) do
    trimmed = String.trim(line)

    cond do
      String.starts_with?(trimmed, "- name: ") ->
        {roots, trimmed |> trim_prefix("- name: ") |> clean_scalar()}

      String.starts_with?(trimmed, "path: ") and is_binary(current_name) ->
        {Map.put(roots, current_name, trimmed |> trim_prefix("path: ") |> clean_scalar()),
         current_name}

      true ->
        {roots, current_name}
    end
  end

  defp trim_prefix(value, prefix),
    do: binary_part(value, byte_size(prefix), byte_size(value) - byte_size(prefix))

  defp clean_scalar(value) do
    value
    |> String.trim()
    |> trim_wrapping_quote(?")
    |> trim_wrapping_quote(?')
  end

  defp trim_wrapping_quote(value, quote) do
    if byte_size(value) >= 2 and :binary.at(value, 0) == quote and
         :binary.at(value, byte_size(value) - 1) == quote do
      binary_part(value, 1, byte_size(value) - 2)
    else
      value
    end
  end
end
