defmodule StackLab.GnTen.BatchReceipt do
  @moduledoc false

  alias StackLab.GnTen.Manifest

  @schema_version "gn_ten_batch_receipt_v1"
  @branch_policy "main_only"

  @safe_slug ~r/^[a-z0-9][a-z0-9-]*$/

  @spec default_out_dir() :: String.t()
  def default_out_dir do
    Path.expand("docs/receipts/gn_ten_batches", File.cwd!())
  end

  @spec new(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def new(slug, opts \\ []) when is_binary(slug) do
    with :ok <- validate_slug(slug),
         {:ok, repo} <- validate_repo(Keyword.get(opts, :repo, "stack_lab")),
         {:ok, date} <- validate_date(Keyword.get(opts, :date, Date.utc_today())) do
      receipt = receipt(slug, repo, date, opts)
      write_receipt(receipt, opts)
    end
  end

  defp validate_slug(slug) do
    if Regex.match?(@safe_slug, slug) do
      :ok
    else
      {:error, {:unsafe_slug, slug}}
    end
  end

  defp validate_repo(nil), do: {:ok, nil}

  defp validate_repo(repo) do
    with {:ok, manifest} <- Manifest.validate_file() do
      if Enum.member?(manifest.repos, repo) do
        {:ok, repo}
      else
        {:error, {:unknown_repo, repo}}
      end
    end
  end

  defp validate_date(%Date{} = date), do: {:ok, date}
  defp validate_date(date), do: {:error, {:invalid_date, date}}

  defp receipt(slug, repo, date, opts) do
    compact_date = date |> Date.to_iso8601() |> String.replace("-", "")
    out_dir = Keyword.get(opts, :out_dir, default_out_dir())
    filename_root = "#{compact_date}_#{slug}"

    %{
      schema_version: @schema_version,
      slug: slug,
      date: date,
      batch_id: "#{compact_date}-#{slug}",
      branch_policy: @branch_policy,
      primary_owner_repo: repo,
      contract_producer_repo: Keyword.get(opts, :contract_producer_repo),
      consumer_repos: Keyword.get(opts, :consumer_repos, []),
      commands: [],
      proof: %{
        scenario: nil,
        evidence: [],
        does_not_prove: []
      },
      trace_evidence: [],
      git_closeout: [],
      notes: [],
      md_path: Path.join(out_dir, "#{filename_root}.md"),
      json_path: Path.join(out_dir, "#{filename_root}.json")
    }
  end

  defp write_receipt(receipt, opts) do
    force? = Keyword.get(opts, :force?, false)

    with :ok <- ensure_target_available(receipt.md_path, force?),
         :ok <- ensure_target_available(receipt.json_path, force?),
         :ok <- File.mkdir_p(Path.dirname(receipt.md_path)),
         :ok <- File.write(receipt.md_path, markdown(receipt)),
         :ok <- File.write(receipt.json_path, json(receipt)) do
      {:ok, Map.take(receipt, [:batch_id, :md_path, :json_path])}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_target_available(_path, true), do: :ok

  defp ensure_target_available(path, false) do
    if File.exists?(path) do
      {:error, {:receipt_exists, path}}
    else
      :ok
    end
  end

  defp markdown(receipt) do
    """
    # gn-ten Batch Receipt: #{receipt.slug}

    Date: #{Date.to_iso8601(receipt.date)}
    Batch ID: #{receipt.batch_id}
    Branch policy: #{receipt.branch_policy}
    Primary owner repo: #{receipt.primary_owner_repo || ""}
    Contract producer repo:
    Consumer repos:

    ## Scope

    - Owner repo:
    - Producer artifact:
    - Consumer repos:
    - Phase/checklist:

    ## Commands

    - [ ] command:
      - result:
      - evidence:

    ## Proof

    - Scenario:
    - Proves:
    - Does not prove:
    - Trace evidence:

    ## Git Closeout

    - Repo:
    - Branch:
    - Commit SHA:
    - Pushed:
    - Worktree clean:

    ## Notes

    - 
    """
  end

  defp json(receipt) do
    receipt
    |> Map.take([
      :schema_version,
      :batch_id,
      :branch_policy,
      :primary_owner_repo,
      :contract_producer_repo,
      :consumer_repos,
      :commands,
      :proof,
      :trace_evidence,
      :git_closeout,
      :notes
    ])
    |> Jason.encode!(pretty: true)
  end
end
