defmodule StackLab.GnTen.Plan do
  @moduledoc false

  alias StackLab.GnTen.Manifest

  @repo_agent_root Path.expand(
                     "/home/home/p/g/j/jido_brainstorm/nshkrdotcom/docs/20260428/gn-ten_cleanup/repo_agent_instructions"
                   )

  @spec for_repo(String.t(), keyword()) :: {:ok, map() | String.t()} | {:error, term()}
  def for_repo(repo_name, opts \\ []) when is_binary(repo_name) do
    with {:ok, manifest} <- Manifest.validate_file(),
         {:ok, repo} <- fetch_repo(manifest, repo_name) do
      plan = plan(repo, manifest)

      if Keyword.get(opts, :json?, false) do
        {:ok, plan}
      else
        {:ok, format_text(plan)}
      end
    end
  end

  defp fetch_repo(manifest, repo_name) do
    case Enum.find(manifest.repo_entries, &(&1.name == repo_name)) do
      nil -> {:error, {:unknown_repo, repo_name}}
      repo -> {:ok, repo}
    end
  end

  defp plan(repo, manifest) do
    %{
      repo: repo.name,
      owner: repo.name,
      layer: repo.layer,
      role: repo.role,
      path: repo.path,
      default_branch: repo.default_branch,
      ci: repo.ci,
      produces: repo.produces,
      consumes: repo.consumes,
      proof_owner: repo.proof_owner,
      proof_matrix: manifest.proof_matrix,
      repo_agent_draft: Path.join(@repo_agent_root, "#{repo.name}.md"),
      next: [
        "confirm repo is on main and clean",
        "read repo-agent draft",
        "run repo-local CI before commit",
        "record pushed SHA in the active checklist"
      ]
    }
  end

  defp format_text(plan) do
    [
      "repo: #{plan.repo}",
      "owner: #{plan.owner}",
      "layer: #{plan.layer}",
      "role: #{plan.role}",
      "path: #{plan.path}",
      "default_branch: #{plan.default_branch}",
      "ci: #{plan.ci}",
      "produces:\n#{bullets(plan.produces)}",
      "consumes:\n#{bullets(plan.consumes)}",
      "proof_owner: #{plan.proof_owner}",
      "proof_matrix: #{plan.proof_matrix}",
      "repo_agent_draft: #{plan.repo_agent_draft}",
      "next:\n#{bullets(plan.next)}"
    ]
    |> Enum.join("\n")
  end

  defp bullets([]), do: "  - (none)"

  defp bullets(items) do
    Enum.map_join(items, "\n", &"  - #{&1}")
  end
end
