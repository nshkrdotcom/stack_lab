defmodule StackLab.GnTen.Manifest do
  @moduledoc """
  Validator for the local `gn-ten` ranked workspace manifest.

  This intentionally validates a narrow YAML subset used by `gn-ten.yml`.
  It does not attempt to be a general YAML parser; the manifest is a human
  coordination file and the validator protects the required ownership facts.
  """

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

  @schema_version "gn_ten_manifest_v1"
  @branch_policy "main_only"
  @main_branch "main"
  @default_path Path.expand("../../../gn-ten.yml", __DIR__)

  @type result :: %{
          schema_version: String.t(),
          workspace_ref: String.t(),
          branch_policy: String.t(),
          proof_matrix: String.t(),
          repos: [String.t()],
          repo_refs: [String.t()],
          paths: [String.t()],
          default_branches: [String.t()],
          repo_entries: [map()]
        }

  @spec expected_repos() :: [String.t()]
  def expected_repos, do: @expected_repos

  @spec main_branch() :: String.t()
  def main_branch, do: @main_branch

  @spec default_path() :: String.t()
  def default_path, do: @default_path

  @spec validate_file(String.t()) :: {:ok, result()} | {:error, [term()]}
  def validate_file(path \\ @default_path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        manifest = parse(content)
        failures = validate(manifest, path)

        case failures do
          [] -> {:ok, manifest}
          failures -> {:error, failures}
        end

      {:error, reason} ->
        {:error, [{:manifest_read_failed, path, reason}]}
    end
  end

  defp parse(content) do
    repo_entries = repo_entries(content)
    repos = Enum.map(repo_entries, & &1.name)
    repo_refs = Enum.map(repo_entries, & &1.repo_ref)
    paths = Enum.map(repo_entries, & &1.path)
    default_branches = Enum.map(repo_entries, & &1.default_branch)
    ci_commands = Enum.map(repo_entries, & &1.ci)

    %{
      schema_version: scalar(content, "schema_version"),
      workspace_ref: scalar(content, "workspace_ref"),
      branch_policy: scalar(content, "branch_policy"),
      proof_matrix: scalar(content, "proof_matrix"),
      repos: repos,
      repo_refs: repo_refs,
      paths: paths,
      default_branches: default_branches,
      ci_commands: ci_commands,
      repo_entries: repo_entries,
      content: content
    }
  end

  defp validate(manifest, manifest_path) do
    []
    |> require_equal(:schema_version, manifest.schema_version, @schema_version)
    |> require_equal(:workspace_ref, manifest.workspace_ref, "workspace://nshkrdotcom/gn-ten")
    |> require_equal(:branch_policy, manifest.branch_policy, @branch_policy)
    |> require_equal(:repos, manifest.repos, @expected_repos)
    |> require_repo_refs(manifest.repo_refs)
    |> require_repo_paths(manifest.paths)
    |> require_main_branches(manifest.default_branches)
    |> require_repo_entry_count(manifest.repo_entries)
    |> require_proof_matrix(manifest, manifest_path)
  end

  defp require_equal(failures, _field, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, field, actual, expected) do
    [{:mismatch, field, expected, actual} | failures]
  end

  defp require_repo_refs(failures, refs) do
    expected_refs = Enum.map(@expected_repos, &"repo://nshkrdotcom/#{&1}")

    if refs == expected_refs do
      failures
    else
      [{:mismatch, :repo_refs, expected_refs, refs} | failures]
    end
  end

  defp require_repo_paths(failures, paths) do
    expected_paths = Enum.map(@expected_repos, &"/home/home/p/g/n/#{&1}")

    if paths == expected_paths do
      failures
    else
      [{:mismatch, :paths, expected_paths, paths} | failures]
    end
  end

  defp require_main_branches(failures, branches) do
    expected_branches = List.duplicate(@main_branch, length(@expected_repos))

    if branches == expected_branches do
      failures
    else
      [{:mismatch, :default_branches, expected_branches, branches} | failures]
    end
  end

  defp require_repo_entry_count(failures, entries)
       when length(entries) == length(@expected_repos) do
    failures
  end

  defp require_repo_entry_count(failures, entries) do
    [{:mismatch, :repo_entry_count, length(@expected_repos), length(entries)} | failures]
  end

  defp require_proof_matrix(failures, %{proof_matrix: nil}, _manifest_path) do
    [{:missing, :proof_matrix} | failures]
  end

  defp require_proof_matrix(failures, manifest, manifest_path) do
    proof_path = Path.expand(manifest.proof_matrix, Path.dirname(manifest_path))

    case File.read(proof_path) do
      {:ok, proof_content} ->
        missing_repos =
          Enum.reject(@expected_repos, fn repo ->
            String.contains?(proof_content, "`#{repo}`") and
              String.contains?(proof_content, "repo://nshkrdotcom/#{repo}")
          end)

        case missing_repos do
          [] -> failures
          missing -> [{:proof_matrix_missing_repos, missing} | failures]
        end

      {:error, reason} ->
        [{:proof_matrix_read_failed, proof_path, reason} | failures]
    end
  end

  defp scalar(content, key) do
    case Regex.run(~r/^#{Regex.escape(key)}:\s*(.+?)\s*$/m, content) do
      [_match, value] -> value
      nil -> nil
    end
  end

  defp repo_entries(content) do
    ~r/^\s+- name:\s*[A-Za-z0-9_]+\s*$.*?(?=^\s+- name:\s*[A-Za-z0-9_]+\s*$|\z)/ms
    |> Regex.scan(content)
    |> List.flatten()
    |> Enum.map(&repo_entry/1)
  end

  defp repo_entry(block) do
    %{
      name: block_scalar(block, "name"),
      repo_ref: block_scalar(block, "repo_ref"),
      path: block_scalar(block, "path"),
      default_branch: block_scalar(block, "default_branch"),
      ci: block_scalar(block, "ci"),
      layer: block_scalar(block, "layer"),
      role: block_scalar(block, "role"),
      variant: block_scalar(block, "variant"),
      strategy: block_scalar(block, "strategy"),
      order: block_scalar(block, "order"),
      produces: block_list(block, "produces"),
      consumes: block_list(block, "consumes"),
      proof_owner: block_scalar(block, "proof_owner")
    }
  end

  defp block_scalar(block, "name") do
    case Regex.run(~r/^\s*-\s*name:\s*(.+?)\s*$/m, block) do
      [_match, value] -> value
      nil -> nil
    end
  end

  defp block_scalar(block, key) do
    case Regex.run(~r/^\s*#{Regex.escape(key)}:\s*(.+?)\s*$/m, block) do
      [_match, value] -> value
      nil -> nil
    end
  end

  defp block_list(block, key) do
    case Regex.run(~r/^\s*#{Regex.escape(key)}:\s*\n(?<items>(?:\s+- .+\n?)*)/m, block,
           capture: ["items"]
         ) do
      [items] ->
        items
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.replace_prefix(&1, "- ", ""))

      nil ->
        []
    end
  end
end
