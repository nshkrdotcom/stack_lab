defmodule StackLab.Examples.AtomCleanupHarness do
  @moduledoc """
  Dynamic atom cleanup proof helpers for StackLab ATOM phases.
  """

  alias StackLab.GnTenControlPlane
  alias StackLab.SpecCell

  defmodule Finding do
    @moduledoc """
    Redacted dynamic atom finding.
    """

    @enforce_keys [:owner_repo, :path, :line, :pattern]
    defstruct [:owner_repo, :path, :line, :pattern, :classification]

    @type classification ::
            :runtime_external_input
            | :runtime_bounded
            | :compile_time_literal
            | :generated_bounded
            | :test_only_bounded
            | :dead_or_unreachable

    @type t :: %__MODULE__{
            owner_repo: String.t(),
            path: String.t(),
            line: pos_integer(),
            pattern: atom(),
            classification: classification() | nil
          }
  end

  @patterns [
    {"String." <> "to_atom", :string_to_atom},
    {"String." <> "to_existing_atom", :string_to_existing_atom},
    {"binary_to_" <> "atom", :binary_to_atom},
    {"binary_to_" <> "existing_atom", :binary_to_existing_atom},
    {"list_to_" <> "atom", :list_to_atom},
    {"list_to_" <> "existing_atom", :list_to_existing_atom},
    {":" <> "\"" <> "\#{", :interpolated_atom}
  ]

  @classifications [
    :runtime_external_input,
    :runtime_bounded,
    :compile_time_literal,
    :generated_bounded,
    :test_only_bounded,
    :dead_or_unreachable
  ]

  @release_blocking [:runtime_external_input, nil]

  @spec scan_text(String.t(), String.t(), keyword()) :: [Finding.t()]
  def scan_text(path, text, opts \\ []) when is_binary(path) and is_binary(text) do
    owner_repo = Keyword.get(opts, :owner_repo, "unknown")

    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      for {needle, pattern} <- @patterns,
          String.contains?(line, needle) do
        %Finding{owner_repo: owner_repo, path: path, line: line_number, pattern: pattern}
      end
    end)
  end

  @spec classify(Finding.t(), Finding.classification()) ::
          {:ok, Finding.t()} | {:error, :unknown_classification}
  def classify(%Finding{} = finding, classification) when classification in @classifications do
    {:ok, %Finding{finding | classification: classification}}
  end

  def classify(%Finding{}, _classification), do: {:error, :unknown_classification}

  @spec release_blocking?(Finding.t()) :: boolean()
  def release_blocking?(%Finding{classification: classification}) do
    classification in @release_blocking
  end

  @spec spec_cell(String.t(), keyword()) :: SpecCell.t()
  def spec_cell(owner_repo, opts \\ []) when is_binary(owner_repo) do
    requirement_id = Keyword.get(opts, :requirement_id, "ATOM")

    SpecCell.new!(
      requirement_id: requirement_id,
      owner_repo: owner_repo,
      source_docs: [
        "implementation_docset/35_per_repo_atom_cleanup.md",
        "implementation_docset/39_new_package_placement.md"
      ],
      target_code_paths: Keyword.get(opts, :target_code_paths, [owner_repo]),
      proof_command: Keyword.get(opts, :proof_command, "mix test"),
      acceptance_fixture: Keyword.get(opts, :acceptance_fixture, requirement_id),
      scanner_refs: ["atom_cleanup_harness"],
      closeout_state: Keyword.get(opts, :closeout_state, :planned),
      release_claim: "dynamic atom cleanup must be classified before release"
    )
  end

  @spec receipt(SpecCell.t(), keyword()) :: GnTenControlPlane.t()
  def receipt(%SpecCell{} = cell, opts \\ []) do
    requirement_id = Keyword.get(opts, :requirement_id, cell.requirement_id)
    state = Keyword.get(opts, :state, "missing")

    GnTenControlPlane.new!(
      receipt_id: "gn-ten:#{requirement_id}:atom-cleanup",
      requirement_id: requirement_id,
      owner_repo: cell.owner_repo,
      state: state,
      proof_command: cell.proof_command,
      receipt_path:
        Keyword.get(opts, :receipt_path, "docs/receipts/gn_ten/#{requirement_id}.json"),
      spec_cell: cell
    )
  end
end
