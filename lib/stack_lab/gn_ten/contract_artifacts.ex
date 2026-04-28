defmodule StackLab.GnTen.ContractArtifacts do
  @moduledoc """
  Narrow validator for the local gn-ten contract artifact ledger.

  The ledger is a reviewed coordination file, not a package manager lockfile.
  Phase A treats source SHA drift as a warning so self-referential StackLab
  artifacts can be bootstrapped without forcing recursive commits.
  """

  alias GroundPlane.Contracts.{ArtifactRef, WorkspaceRef}
  alias StackLab.GnTen.Manifest

  @schema_version "gn_ten_contract_artifacts_v1"
  @workspace_ref WorkspaceRef.new!("nshkrdotcom", "gn-ten").ref
  @branch_policy "main_only"
  @main_ref "main"
  @allowed_statuses ~w(proposed bootstrap projected stable deprecated)
  @required_fields ~w(
    name
    artifact_ref
    producer_repo
    producer_repo_ref
    producer_path
    source_ref
    source_sha
    build_command
    status
    consumers
  )a
  @default_path Path.expand("../../../contract_artifacts.yml", __DIR__)

  @type report :: %{
          schema_version: String.t() | nil,
          workspace_ref: String.t() | nil,
          branch_policy: String.t() | nil,
          artifact_count: non_neg_integer(),
          stale_count: non_neg_integer(),
          artifacts: [map()],
          warnings: [map()],
          failures: [map()]
        }

  @spec default_path() :: String.t()
  def default_path, do: @default_path

  @spec validate(String.t(), String.t()) :: {:ok, report()} | {:error, report()}
  def validate(path \\ @default_path, manifest_path \\ Manifest.default_path()) do
    with {:ok, manifest} <- manifest(manifest_path),
         {:ok, content} <- read(path) do
      content
      |> parse()
      |> validate_ledger(manifest)
      |> result()
    end
  end

  defp manifest(path) do
    case Manifest.validate_file(path) do
      {:ok, manifest} -> {:ok, manifest}
      {:error, failures} -> {:error, manifest_report(failures)}
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, content} ->
        {:ok, content}

      {:error, :enoent} ->
        {:error, empty_report([failure("artifact_ledger_missing")])}

      {:error, reason} ->
        {:error, empty_report([failure("artifact_ledger_read_failed", reason: reason)])}
    end
  end

  defp parse(content) do
    %{
      schema_version: scalar(content, "schema_version"),
      workspace_ref: scalar(content, "workspace_ref"),
      branch_policy: scalar(content, "branch_policy"),
      artifacts: artifact_blocks(content) |> Enum.map(&artifact/1)
    }
  end

  defp validate_ledger(ledger, manifest) do
    repo_names = MapSet.new(manifest.repos)

    failures =
      []
      |> validate_envelope(ledger)
      |> validate_artifact_count(ledger.artifacts)
      |> validate_required_fields(ledger.artifacts)
      |> validate_unique_names(ledger.artifacts)
      |> validate_statuses(ledger.artifacts)
      |> validate_deprecated_consumers(ledger.artifacts)
      |> validate_repo_refs(ledger.artifacts, repo_names)
      |> validate_source_refs(ledger.artifacts)
      |> validate_artifact_refs(ledger.artifacts)

    sha_findings = validate_source_shas(ledger.artifacts, manifest)
    sha_failures = Enum.filter(sha_findings, &(&1.severity == "failure"))
    warnings = Enum.filter(sha_findings, &(&1.severity == "warning"))

    %{
      schema_version: ledger.schema_version,
      workspace_ref: ledger.workspace_ref,
      branch_policy: ledger.branch_policy,
      artifact_count: length(ledger.artifacts),
      stale_count: Enum.count(sha_findings, &(&1.code == "artifact_source_sha_stale")),
      artifacts: Enum.map(ledger.artifacts, &safe_artifact/1),
      warnings: Enum.reverse(warnings),
      failures: Enum.reverse(sha_failures ++ failures)
    }
  end

  defp result(%{failures: []} = report), do: {:ok, report}
  defp result(report), do: {:error, report}

  defp validate_envelope(failures, ledger) do
    failures
    |> require_equal("artifact_bad_schema_version", ledger.schema_version, @schema_version)
    |> require_equal("artifact_bad_workspace_ref", ledger.workspace_ref, @workspace_ref)
    |> require_equal("artifact_bad_branch_policy", ledger.branch_policy, @branch_policy)
  end

  defp validate_artifact_count(failures, [_artifact | _rest]), do: failures
  defp validate_artifact_count(failures, []), do: [failure("artifact_empty_ledger") | failures]

  defp validate_required_fields(failures, artifacts) do
    Enum.reduce(artifacts, failures, fn artifact, acc ->
      missing =
        Enum.filter(@required_fields, fn field ->
          field_missing?(artifact, field)
        end)

      case missing do
        [] ->
          acc

        fields ->
          [
            failure("artifact_missing_required_field", artifact: artifact.name, fields: fields)
            | acc
          ]
      end
    end)
  end

  defp field_missing?(%{status: "deprecated"}, :consumers), do: false

  defp field_missing?(artifact, field) do
    value = Map.get(artifact, field)
    is_nil(value) or value == "" or value == []
  end

  defp validate_unique_names(failures, artifacts) do
    artifacts
    |> Enum.frequencies_by(& &1.name)
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.reduce(failures, fn {name, _count}, acc ->
      [failure("artifact_duplicate_name", artifact: name) | acc]
    end)
  end

  defp validate_statuses(failures, artifacts) do
    Enum.reduce(artifacts, failures, fn artifact, acc ->
      if artifact.status in @allowed_statuses do
        acc
      else
        [
          failure("artifact_unknown_status", artifact: artifact.name, status: artifact.status)
          | acc
        ]
      end
    end)
  end

  defp validate_deprecated_consumers(failures, artifacts) do
    Enum.reduce(artifacts, failures, fn artifact, acc ->
      if artifact.status == "deprecated" and artifact.consumers != [] do
        [
          failure("artifact_deprecated_consumers_remain",
            artifact: artifact.name,
            consumers: artifact.consumers
          )
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp validate_repo_refs(failures, artifacts, repo_names) do
    Enum.reduce(artifacts, failures, fn artifact, acc ->
      acc
      |> validate_producer(artifact, repo_names)
      |> validate_consumers(artifact, repo_names)
      |> validate_producer_ref(artifact)
    end)
  end

  defp validate_producer(failures, artifact, repo_names) do
    if MapSet.member?(repo_names, artifact.producer_repo) do
      failures
    else
      [
        failure("artifact_unknown_producer",
          artifact: artifact.name,
          repo: artifact.producer_repo
        )
        | failures
      ]
    end
  end

  defp validate_consumers(failures, artifact, repo_names) do
    artifact.consumers
    |> Enum.reject(&MapSet.member?(repo_names, &1))
    |> Enum.reduce(failures, fn consumer, acc ->
      [failure("artifact_unknown_consumer", artifact: artifact.name, repo: consumer) | acc]
    end)
  end

  defp validate_producer_ref(failures, artifact) do
    expected = "repo://nshkrdotcom/#{artifact.producer_repo}"

    if artifact.producer_repo_ref == expected do
      failures
    else
      [
        failure("artifact_bad_producer_repo_ref",
          artifact: artifact.name,
          expected: expected,
          actual: artifact.producer_repo_ref
        )
        | failures
      ]
    end
  end

  defp validate_source_refs(failures, artifacts) do
    Enum.reduce(artifacts, failures, fn artifact, acc ->
      if artifact.source_ref == @main_ref do
        acc
      else
        [
          failure("artifact_bad_source_ref", artifact: artifact.name, actual: artifact.source_ref)
          | acc
        ]
      end
    end)
  end

  defp validate_artifact_refs(failures, artifacts) do
    Enum.reduce(artifacts, failures, fn artifact, acc ->
      expected = ArtifactRef.new!("nshkrdotcom", artifact.producer_repo, artifact.name).ref

      if artifact.artifact_ref == expected do
        acc
      else
        [
          failure("artifact_bad_ref",
            artifact: artifact.name,
            expected: expected,
            actual: artifact.artifact_ref
          )
          | acc
        ]
      end
    end)
  end

  defp validate_source_shas(artifacts, manifest) do
    Enum.reduce(artifacts, [], fn artifact, acc ->
      case local_head(artifact, manifest) do
        {:ok, actual} when actual == artifact.source_sha ->
          acc

        {:ok, actual} ->
          stale_source_sha(artifact, actual, acc)

        :skip ->
          acc
      end
    end)
  end

  defp stale_source_sha(%{status: "proposed"}, _actual, acc), do: acc

  defp stale_source_sha(%{status: "bootstrap"} = artifact, actual, acc) do
    [
      failure("artifact_source_sha_stale",
        artifact: artifact.name,
        expected: artifact.source_sha,
        actual: actual,
        severity: "warning"
      )
      | acc
    ]
  end

  defp stale_source_sha(artifact, actual, acc) do
    [
      failure("artifact_source_sha_stale",
        artifact: artifact.name,
        expected: artifact.source_sha,
        actual: actual,
        severity: "failure"
      )
      | acc
    ]
  end

  defp local_head(artifact, manifest) do
    with repo when not is_nil(repo) <-
           Enum.find(manifest.repo_entries, &(&1.name == artifact.producer_repo)),
         {sha, 0} <- System.cmd("git", ["rev-parse", "HEAD"], cd: repo.path) do
      {:ok, String.trim(sha)}
    else
      _ -> :skip
    end
  end

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected) do
    [failure(code, expected: expected, actual: actual) | failures]
  end

  defp safe_artifact(artifact) do
    %{
      name: artifact.name,
      artifact_ref: artifact.artifact_ref,
      producer_repo: artifact.producer_repo,
      source_ref: artifact.source_ref,
      source_sha: artifact.source_sha,
      status: artifact.status,
      consumers: artifact.consumers,
      successor: artifact.successor
    }
  end

  defp artifact_blocks(content) do
    content
    |> String.split("\n")
    |> Enum.reduce([], fn line, blocks ->
      cond do
        Regex.match?(~r/^\s+- name:\s*.+$/, line) ->
          [[line] | blocks]

        blocks == [] ->
          blocks

        true ->
          [current | rest] = blocks
          [[line | current] | rest]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(&Enum.reverse/1)
    |> Enum.map(&Enum.join(&1, "\n"))
  end

  defp artifact(block) do
    %{
      name: block_scalar(block, "name"),
      artifact_ref: block_scalar(block, "artifact_ref"),
      producer_repo: block_scalar(block, "producer_repo"),
      producer_repo_ref: block_scalar(block, "producer_repo_ref"),
      producer_path: block_scalar(block, "producer_path"),
      source_ref: block_scalar(block, "source_ref"),
      source_sha: block_scalar(block, "source_sha"),
      build_command: block_scalar(block, "build_command"),
      status: block_scalar(block, "status"),
      successor: block_scalar(block, "successor"),
      consumers: block_list(block, "consumers"),
      notes: block_scalar(block, "notes")
    }
  end

  defp scalar(content, key) do
    case Regex.run(~r/^#{Regex.escape(key)}:\s*(.+?)\s*$/m, content) do
      [_match, value] -> value
      nil -> nil
    end
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

  defp manifest_report(failures) do
    empty_report([failure("artifact_manifest_invalid", failures: failures)])
  end

  defp empty_report(failures) do
    %{
      schema_version: nil,
      workspace_ref: nil,
      branch_policy: nil,
      artifact_count: 0,
      stale_count: 0,
      artifacts: [],
      warnings: [],
      failures: failures
    }
  end

  defp failure(code, fields \\ []) do
    fields
    |> Map.new()
    |> Map.put(:code, code)
  end
end
