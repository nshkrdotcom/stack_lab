defmodule StackLab.GnTen.RepoAgentInstructions do
  @moduledoc false

  alias StackLab.GnTen.Manifest

  @drafts_root Path.expand(
                 "/home/home/p/g/j/jido_brainstorm/nshkrdotcom/docs/20260428/gn-ten_cleanup/repo_agent_instructions"
               )

  @start ~r/<!-- gn-ten:repo-agent:start repo=(?<repo>[A-Za-z0-9_]+)(?: source_sha=(?<sha>[0-9a-f]+))? -->/
  @finish "<!-- gn-ten:repo-agent:end -->"

  @spec default_drafts_root() :: String.t()
  def default_drafts_root, do: @drafts_root

  @spec validate(keyword()) :: {:ok, map()} | {:error, map()}
  def validate(opts \\ []) do
    manifest_path = Keyword.get(opts, :manifest_path, Manifest.default_path())
    drafts_root = Keyword.get(opts, :drafts_root, @drafts_root)

    case Manifest.validate_file(manifest_path) do
      {:ok, manifest} ->
        validate_entries(manifest.repo_entries, drafts_root: drafts_root)

      {:error, failures} ->
        {:error, report([], [failure("repo_agent_manifest_invalid", details: inspect(failures))])}
    end
  end

  @spec validate_entries([map()], keyword()) :: {:ok, map()} | {:error, map()}
  def validate_entries(entries, opts \\ []) when is_list(entries) do
    drafts_root = Keyword.get(opts, :drafts_root, @drafts_root)
    repo_results = Enum.map(entries, &validate_repo(&1, drafts_root))
    failures = Enum.flat_map(repo_results, & &1.failures)

    repo_results
    |> report(failures)
    |> result()
  end

  defp validate_repo(repo, drafts_root) do
    repo_name = repo_name(repo)
    repo_path = repo_path(repo)
    draft_path = Path.join(drafts_root, "#{repo_name}.md")
    agents_path = Path.join(repo_path, "AGENTS.md")
    onboarding_path = Path.join(repo_path, "ONBOARDING.md")
    claude_path = Path.join(repo_path, "CLAUDE.md")

    with {:ok, draft_body} <- read_draft(draft_path),
         {:ok, agents_content} <- read_agents(agents_path),
         {:ok, section} <- extract_section(agents_content) do
      failures =
        repo_name
        |> section_failures(draft_body, section)
        |> onboarding_failures(repo_name, agents_content, onboarding_path)
        |> claude_failures(repo_name, claude_path)

      repo_result(
        repo_name,
        draft_path,
        agents_path,
        onboarding_path,
        claude_path,
        section,
        failures
      )
    else
      {:error, :draft_missing} ->
        repo_result(repo_name, draft_path, agents_path, onboarding_path, claude_path, nil, [
          failure("repo_agent_source_missing", repo: repo_name)
        ])

      {:error, :agents_missing} ->
        repo_result(repo_name, draft_path, agents_path, onboarding_path, claude_path, nil, [
          failure("repo_agent_missing_agents", repo: repo_name)
        ])

      {:error, :section_missing} ->
        repo_result(repo_name, draft_path, agents_path, onboarding_path, claude_path, nil, [
          failure("repo_agent_missing_section", repo: repo_name)
        ])
    end
  end

  defp repo_name(%{name: name}), do: name
  defp repo_name(%{"name" => name}), do: name

  defp repo_path(%{path: path}), do: path
  defp repo_path(%{"path" => path}), do: path

  defp section_failures(repo_name, draft_body, section) do
    cond do
      section.marker_repo != repo_name ->
        [
          failure("repo_agent_wrong_repo_marker",
            repo: repo_name,
            marker_repo: section.marker_repo
          )
        ]

      normalize(section.body) != normalize(draft_body) ->
        [failure("repo_agent_drift", repo: repo_name)]

      true ->
        []
    end
  end

  defp onboarding_failures(failures, repo_name, agents_content, onboarding_path) do
    cond do
      not File.regular?(onboarding_path) ->
        [failure("repo_agent_missing_onboarding", repo: repo_name) | failures]

      not String.contains?(agents_content, "ONBOARDING.md") ->
        [failure("repo_agent_agents_missing_onboarding_reference", repo: repo_name) | failures]

      true ->
        failures
    end
  end

  defp claude_failures(failures, repo_name, claude_path) do
    case File.read(claude_path) do
      {:ok, content} when content in ["@AGENTS.md", "@AGENTS.md\n"] ->
        failures

      {:ok, _content} ->
        [failure("repo_agent_bad_claude_shim", repo: repo_name) | failures]

      {:error, :enoent} ->
        [failure("repo_agent_missing_claude", repo: repo_name) | failures]

      {:error, reason} ->
        [failure("repo_agent_claude_read_failed", repo: repo_name, reason: reason) | failures]
    end
  end

  defp repo_result(
         repo_name,
         draft_path,
         agents_path,
         onboarding_path,
         claude_path,
         section,
         failures
       ) do
    %{
      repo: repo_name,
      draft_path: draft_path,
      agents_path: agents_path,
      onboarding_path: onboarding_path,
      claude_path: claude_path,
      marker_repo: if(section, do: section.marker_repo),
      source_sha: if(section, do: section.source_sha),
      status: if(failures == [], do: "ok", else: "fail"),
      failures: failures
    }
  end

  defp read_draft(path) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, :enoent} -> {:error, :draft_missing}
      {:error, reason} -> {:error, {:draft_read_failed, reason}}
    end
  end

  defp read_agents(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :agents_missing}
      {:error, reason} -> {:error, {:agents_read_failed, reason}}
    end
  end

  defp extract_section(content) do
    lines = String.split(content, "\n")
    start = Enum.find_index(lines, &Regex.match?(@start, &1))

    if is_nil(start) do
      {:error, :section_missing}
    else
      finish =
        lines
        |> Enum.with_index()
        |> Enum.find(fn {line, index} -> index > start and String.trim(line) == @finish end)

      case finish do
        nil ->
          {:error, :section_missing}

        {_line, finish_index} ->
          marker = Enum.at(lines, start)
          captures = Regex.named_captures(@start, marker)

          body =
            lines
            |> Enum.slice((start + 1)..(finish_index - 1)//1)
            |> Enum.join("\n")

          {:ok,
           %{
             marker_repo: captures["repo"],
             source_sha: blank_to_nil(captures["sha"]),
             body: body
           }}
      end
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp normalize(body) do
    body
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.map_join("\n", &String.trim_trailing/1)
    |> String.trim()
  end

  defp result(%{failures: []} = summary), do: {:ok, summary}
  defp result(summary), do: {:error, summary}

  defp report(repo_results, failures) do
    %{
      repo_count: length(repo_results),
      failure_count: length(failures),
      repos: Enum.map(repo_results, &Map.drop(&1, [:failures])),
      failures: failures
    }
  end

  defp failure(code, attrs) do
    attrs
    |> Map.new()
    |> Map.put(:code, code)
  end
end
