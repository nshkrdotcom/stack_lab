defmodule StackLab.Examples.EnvRemediationHarness do
  @moduledoc """
  Environment and ambient-auth cleanup proof helpers for StackLab ENV phases.
  """

  alias StackLab.GnTenControlPlane
  alias StackLab.SpecCell

  defmodule Finding do
    @moduledoc """
    Redacted env or ambient-auth finding.
    """

    @enforce_keys [:owner_repo, :path, :line, :token]
    defstruct [
      :owner_repo,
      :path,
      :line,
      :token,
      :classification,
      :production_class,
      :proof_command,
      :receipt_path
    ]

    @type classification ::
            :approved_boot_boundary
            | :standalone_compat_only
            | :test_restored
            | :generated_or_tooling_only
            | :docs_or_prose
            | :governed_hot_path_fix

    @type production_class ::
            :standalone_auth
            | :governed_auth
            | :cli_discovery
            | :test_gate
            | :deployment_config
            | :telemetry_config
            | :fixture_config
            | :generated_tooling
            | :deprecated

    @type t :: %__MODULE__{
            owner_repo: String.t(),
            path: String.t(),
            line: pos_integer(),
            token: atom(),
            classification: classification() | nil,
            production_class: production_class() | nil,
            proof_command: String.t() | nil,
            receipt_path: String.t() | nil
          }
  end

  defmodule PhaseReceipt do
    @moduledoc """
    Redacted proof receipt for an ENV cleanup phase command or state.
    """

    @enforce_keys [:owner_repo, :phase_id, :kind, :state]
    defstruct [
      :owner_repo,
      :phase_id,
      :kind,
      :state,
      :proof_command,
      :receipt_path,
      :commit_sha,
      :remote,
      :open_defect
    ]

    @type kind ::
            :env_scan
            | :redaction_scan
            | :pattern_engine_free_scan
            | :atom_source_scan
            | :repo_qc
            | :commit_push
            | :open_defect_continue

    @type state :: :pass | :fail | :missing | :pushed | :open_defect

    @type t :: %__MODULE__{
            owner_repo: String.t(),
            phase_id: String.t(),
            kind: kind(),
            state: state(),
            proof_command: String.t() | nil,
            receipt_path: String.t() | nil,
            commit_sha: String.t() | nil,
            remote: String.t() | nil,
            open_defect: atom() | nil
          }
  end

  @env_tokens [
    {"System.get_env", :system_get_env},
    {"System.fetch_env", :system_fetch_env},
    {"System.put_env", :system_put_env},
    {"System.delete_env", :system_delete_env},
    {"Application.get_env", :application_get_env},
    {"HOME", :home},
    {"API_KEY", :api_key},
    {"TOKEN", :token},
    {"SECRET", :secret},
    {"PASSWORD", :password},
    {"AUTH", :auth},
    {"auth.json", :auth_json},
    {"oauth", :oauth},
    {"credential", :credential},
    {"bearer", :bearer},
    {"CODEX_HOME", :codex_home},
    {"OPENAI_API_KEY", :openai_api_key},
    {"CODEX_API_KEY", :codex_api_key},
    {"CLAUDE", :claude},
    {"GEMINI", :gemini},
    {"AMP", :amp},
    {"GITHUB", :github},
    {"NOTION", :notion},
    {"LINEAR", :linear},
    {"REQ_LLM", :req_llm},
    {"BASE_URL", :base_url},
    {"default auth", :default_auth_text},
    {"default_auth", :default_auth_identifier},
    {"global client", :global_client_text},
    {"global_client", :global_client_identifier},
    {"singleton", :singleton}
  ]

  @classifications [
    :approved_boot_boundary,
    :standalone_compat_only,
    :test_restored,
    :generated_or_tooling_only,
    :docs_or_prose,
    :governed_hot_path_fix
  ]

  @production_classes [
    :standalone_auth,
    :governed_auth,
    :cli_discovery,
    :test_gate,
    :deployment_config,
    :telemetry_config,
    :fixture_config,
    :generated_tooling,
    :deprecated
  ]

  @receipt_kinds [
    :env_scan,
    :redaction_scan,
    :pattern_engine_free_scan,
    :atom_source_scan,
    :repo_qc,
    :commit_push,
    :open_defect_continue
  ]

  @receipt_states [:pass, :fail, :missing, :pushed, :open_defect]

  @spec scan_text(String.t(), String.t(), keyword()) :: [Finding.t()]
  def scan_text(path, text, opts \\ []) when is_binary(path) and is_binary(text) do
    owner_repo = Keyword.get(opts, :owner_repo, "unknown")

    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      for {needle, token} <- @env_tokens,
          String.contains?(line, needle) do
        %Finding{owner_repo: owner_repo, path: path, line: line_number, token: token}
      end
    end)
  end

  @spec classify(Finding.t(), Finding.classification(), Finding.production_class()) ::
          {:ok, Finding.t()} | {:error, :unknown_classification | :unknown_production_class}
  def classify(%Finding{} = finding, classification, production_class) do
    with :ok <- validate_classification(classification),
         :ok <- validate_production_class(production_class) do
      {:ok,
       %Finding{
         finding
         | classification: classification,
           production_class: production_class
       }}
    end
  end

  @spec attach_receipt(Finding.t(), keyword()) :: Finding.t()
  def attach_receipt(%Finding{} = finding, opts \\ []) do
    %Finding{
      finding
      | proof_command: Keyword.get(opts, :proof_command),
        receipt_path: Keyword.get(opts, :receipt_path)
    }
  end

  @spec governed_hot_path?(Finding.t()) :: boolean()
  def governed_hot_path?(%Finding{classification: :governed_hot_path_fix}), do: true
  def governed_hot_path?(%Finding{}), do: false

  @spec release_blocking?(Finding.t()) :: boolean()
  def release_blocking?(%Finding{classification: nil}), do: true
  def release_blocking?(%Finding{production_class: nil}), do: true
  def release_blocking?(%Finding{classification: :governed_hot_path_fix}), do: true
  def release_blocking?(%Finding{}), do: false

  @spec redacted_receipt(Finding.t()) :: map()
  def redacted_receipt(%Finding{} = finding) do
    %{
      owner_repo: finding.owner_repo,
      path: finding.path,
      line: finding.line,
      token: finding.token,
      classification: finding.classification,
      production_class: finding.production_class,
      proof_command: finding.proof_command,
      receipt_path: finding.receipt_path
    }
  end

  @spec phase_receipt(
          String.t(),
          String.t(),
          PhaseReceipt.kind(),
          PhaseReceipt.state(),
          keyword()
        ) ::
          {:ok, PhaseReceipt.t()} | {:error, :unknown_receipt_kind | :unknown_receipt_state}
  def phase_receipt(owner_repo, phase_id, kind, state, opts \\ [])
      when is_binary(owner_repo) and is_binary(phase_id) do
    with :ok <- validate_receipt_kind(kind),
         :ok <- validate_receipt_state(state) do
      {:ok,
       %PhaseReceipt{
         owner_repo: owner_repo,
         phase_id: phase_id,
         kind: kind,
         state: state,
         proof_command: Keyword.get(opts, :proof_command),
         receipt_path: Keyword.get(opts, :receipt_path),
         commit_sha: Keyword.get(opts, :commit_sha),
         remote: Keyword.get(opts, :remote),
         open_defect: Keyword.get(opts, :open_defect)
       }}
    end
  end

  @spec release_blocking_receipt?(PhaseReceipt.t()) :: boolean()
  def release_blocking_receipt?(%PhaseReceipt{state: :pass}), do: false
  def release_blocking_receipt?(%PhaseReceipt{state: :pushed}), do: false
  def release_blocking_receipt?(%PhaseReceipt{}), do: true

  @spec redacted_phase_receipt(PhaseReceipt.t()) :: map()
  def redacted_phase_receipt(%PhaseReceipt{} = receipt) do
    %{
      owner_repo: receipt.owner_repo,
      phase_id: receipt.phase_id,
      kind: receipt.kind,
      state: receipt.state,
      proof_command: receipt.proof_command,
      receipt_path: receipt.receipt_path,
      commit_sha: receipt.commit_sha,
      remote: receipt.remote,
      open_defect: receipt.open_defect
    }
  end

  @spec spec_cell(String.t(), keyword()) :: SpecCell.t()
  def spec_cell(owner_repo, opts \\ []) when is_binary(owner_repo) do
    requirement_id = Keyword.get(opts, :requirement_id, "ENV")

    SpecCell.new!(
      requirement_id: requirement_id,
      owner_repo: owner_repo,
      source_docs: [
        "implementation_docset/28_environment_variable_governance.md",
        "implementation_docset/36_per_repo_env_cleanup.md",
        "implementation_docset/39_new_package_placement.md"
      ],
      target_code_paths: Keyword.get(opts, :target_code_paths, [owner_repo]),
      proof_command: Keyword.get(opts, :proof_command, "mix test"),
      acceptance_fixture: Keyword.get(opts, :acceptance_fixture, requirement_id),
      scanner_refs: ["env_remediation_harness"],
      closeout_state: Keyword.get(opts, :closeout_state, :planned),
      release_claim: "governed env ingress must be classified before release"
    )
  end

  @spec receipt(SpecCell.t(), keyword()) :: GnTenControlPlane.t()
  def receipt(%SpecCell{} = cell, opts \\ []) do
    requirement_id = Keyword.get(opts, :requirement_id, cell.requirement_id)
    state = Keyword.get(opts, :state, "missing")

    receipt_id = ["gn-ten", requirement_id, "env-remediation"] |> Enum.join(<<58>>)

    GnTenControlPlane.new!(
      receipt_id: receipt_id,
      requirement_id: requirement_id,
      owner_repo: cell.owner_repo,
      state: state,
      proof_command: cell.proof_command,
      receipt_path:
        Keyword.get(opts, :receipt_path, "docs/receipts/gn_ten/#{requirement_id}.json"),
      spec_cell: cell
    )
  end

  defp validate_classification(classification) when classification in @classifications do
    :ok
  end

  defp validate_classification(_classification), do: {:error, :unknown_classification}

  defp validate_production_class(production_class)
       when production_class in @production_classes do
    :ok
  end

  defp validate_production_class(_production_class), do: {:error, :unknown_production_class}

  defp validate_receipt_kind(kind) when kind in @receipt_kinds, do: :ok
  defp validate_receipt_kind(_kind), do: {:error, :unknown_receipt_kind}

  defp validate_receipt_state(state) when state in @receipt_states, do: :ok
  defp validate_receipt_state(_state), do: {:error, :unknown_receipt_state}
end
