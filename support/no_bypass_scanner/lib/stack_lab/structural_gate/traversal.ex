defmodule StackLab.StructuralGate.Traversal do
  @moduledoc """
  Filesystem traversal for structural scanner target roots.
  """

  alias StackLab.StructuralGate.Zones
  alias StackLab.StructuralGateScanner.{CheckedPath, SkippedPath}

  @source_extensions [".ex", ".exs", ".heex", ".leex", ".eex", ".md"]

  @spec walk(String.t(), map()) :: [{:checked, CheckedPath.t()} | {:skipped, SkippedPath.t()}]
  def walk(path, target_roots) do
    cond do
      not File.exists?(path) ->
        [{:skipped, %SkippedPath{path: path, reason: :missing_path}}]

      Zones.excluded_path?(path) ->
        [{:skipped, %SkippedPath{path: path, reason: :excluded_path}}]

      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.sort()
        |> Enum.flat_map(&walk(Path.join(path, &1), target_roots))

      source_path?(path) ->
        [{:checked, checked_path(path, target_roots)}]

      true ->
        [{:skipped, %SkippedPath{path: path, reason: :unsupported_file_type}}]
    end
  end

  defp checked_path(path, target_roots) do
    {repo, root} = repo_for_path(path, target_roots)

    %CheckedPath{
      path: path,
      repo: repo,
      zone: Zones.classify(repo, path),
      package_path: package_path(root, path)
    }
  end

  defp repo_for_path(path, target_roots) do
    Enum.find(target_roots, fn {_repo, root} ->
      path == root or String.starts_with?(path, root <> "/")
    end)
  end

  defp package_path(root, path) do
    path
    |> package_candidates(root)
    |> Enum.find(&File.exists?/1)
    |> case do
      nil -> nil
      mix_path -> Path.dirname(mix_path)
    end
  end

  defp package_candidates(root, path) do
    path
    |> Path.dirname()
    |> ancestors_until(root)
    |> Enum.map(&Path.join(&1, "mix.exs"))
  end

  defp ancestors_until(path, root) do
    cond do
      path == root -> [path]
      not String.starts_with?(path, root <> "/") -> []
      true -> [path | ancestors_until(Path.dirname(path), root)]
    end
  end

  defp source_path?(path), do: Path.extname(path) in @source_extensions
end
