defmodule StackLab.FoundationGateScanner do
  @moduledoc """
  Minimal Phase 0A source gate for foundation work.
  """

  defmodule Finding do
    @moduledoc """
    Source gate finding.
    """
    @enforce_keys [:rule, :reason, :path, :line, :zone, :owner_phase, :severity]
    @type t :: %__MODULE__{
            rule: atom(),
            reason: atom(),
            path: String.t(),
            line: non_neg_integer(),
            zone: atom(),
            owner_phase: String.t(),
            severity: :error | :warning,
            token: String.t() | nil,
            remediation: String.t()
          }
    defstruct [:rule, :reason, :path, :line, :zone, :owner_phase, :severity, :token, :remediation]
  end

  defmodule SkippedPath do
    @moduledoc """
    Path skipped by scanner traversal.
    """
    @enforce_keys [:path, :reason]
    @type t :: %__MODULE__{path: String.t(), reason: atom()}
    defstruct [:path, :reason]
  end

  defmodule CheckedPath do
    @moduledoc """
    Path checked by scanner traversal.
    """
    @enforce_keys [:path, :repo, :zone]
    @type t :: %__MODULE__{path: String.t(), repo: String.t(), zone: atom()}
    defstruct [:path, :repo, :zone]
  end

  defmodule Receipt do
    @moduledoc """
    Scanner receipt for the Phase 0A foundation gate.
    """
    @enforce_keys [
      :scanner,
      :scanner_version,
      :mode,
      :target_roots,
      :checked_paths,
      :skipped_paths,
      :zones,
      :findings,
      :status,
      :phase_6a_deferred_proofs
    ]
    @type t :: %__MODULE__{
            scanner: String.t(),
            scanner_version: String.t(),
            mode: atom(),
            target_roots: %{String.t() => String.t()},
            checked_paths: [CheckedPath.t()],
            skipped_paths: [SkippedPath.t()],
            zones: %{atom() => non_neg_integer()},
            findings: [Finding.t()],
            status: :pass | :open_defect | :baseline_findings,
            phase_6a_deferred_proofs: [atom()]
          }
    defstruct @enforce_keys
  end

  @scanner "stack_lab.foundation_gate_scanner"
  @scanner_version "0.1.0"

  @target_roots %{
    "AITrace" => "/home/home/p/g/n/AITrace",
    "app_kit" => "/home/home/p/g/n/app_kit",
    "citadel" => "/home/home/p/g/n/citadel",
    "execution_plane" => "/home/home/p/g/n/execution_plane",
    "extravaganza" => "/home/home/p/g/n/extravaganza",
    "ground_plane" => "/home/home/p/g/n/ground_plane",
    "jido_integration" => "/home/home/p/g/n/jido_integration",
    "mezzanine" => "/home/home/p/g/n/mezzanine",
    "outer_brain" => "/home/home/p/g/n/outer_brain",
    "stack_lab" => "/home/home/p/g/n/stack_lab"
  }

  @excluded_segments [".git", "_build", "deps", "dist", "node_modules"]
  @doc_segments ["doc", "docs"]
  @fixture_segments ["fixture", "fixtures", "test", "tests", "test_support"]
  @source_extensions [".ex", ".exs", ".heex", ".leex", ".eex", ".md"]
  @code_extensions [".ex", ".exs", ".heex", ".leex", ".eex"]

  @provider_tokens [
    "Linear",
    "linear",
    "Github",
    "GitHub",
    "github",
    "Codex",
    "codex",
    "Symphony",
    "symphony",
    "OpenAI",
    "openai",
    "pull_number",
    "pull_request",
    "issue_id",
    "repo_full_name",
    "commit_sha",
    "GH_TOKEN",
    "GITHUB_TOKEN",
    "LINEAR_API_KEY",
    "OPENAI_API_KEY",
    "CODEX_API_KEY",
    "LinearIssue",
    "LinearSourceFlow",
    "LinearSourceDispatcher",
    "LinearGraphqlToolExecutor",
    "CodexAgentRuntime",
    "GitHubPrEvidence",
    "GitHubPrEvidenceRuntime",
    "GitHubPrBranchCleanupRuntime",
    "GitHubPrDispatcher",
    "GitHubPrEvidenceReceipt",
    "GitHubPrBranchCleanupReceipt"
  ]

  @provider_shaped_fields [
    "linear_issue_id",
    "linear_issue_number",
    "linear_comment_id",
    "github_pr_id",
    "github_pr_number",
    "github_issue_id",
    "github_issue_number",
    "codex_session_id",
    "codex_turn_id",
    "codex_api_key",
    "github_token",
    "linear_api_key"
  ]

  @app_kit_public_tokens [
    "def sync_linear",
    "def fetch_linear",
    "def current_linear",
    "def publish_linear",
    "def execute_linear",
    "def fetch_github",
    "def cleanup_github",
    "defcallback sync_linear",
    "defcallback fetch_linear",
    "defcallback current_linear",
    "defcallback publish_linear",
    "defcallback execute_linear",
    "defcallback fetch_github",
    "defcallback cleanup_github"
  ]

  @ground_plane_higher_layer_tokens [
    "AI",
    "AiRun",
    "ai_run",
    "workflow",
    "Workflow",
    "product",
    "Product",
    "provider",
    "Provider",
    "connector",
    "Connector",
    "manifest",
    "Manifest",
    "model",
    "Model",
    "runtime",
    "Runtime",
    "lane",
    "Lane",
    "source",
    "Source",
    "evidence",
    "Evidence",
    "review",
    "Review",
    "policy_pack",
    "PolicyPack"
  ]

  @deferred_proofs [
    :ast_public_api_scan,
    :manifest_dependency_scan,
    :bridge_root_import_call_scan,
    :generic_dispatch_dataflow_proof
  ]

  @type scan_option ::
          {:target_roots, %{String.t() => String.t()} | [{String.t(), String.t()}]}
          | {:mode, :hard_gate | :baseline}

  @spec target_roots() :: %{String.t() => String.t()}
  def target_roots, do: @target_roots

  @spec scan([String.t()], [scan_option()]) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(paths, opts \\ []) when is_list(paths) do
    target_roots = opts |> Keyword.get(:target_roots, @target_roots) |> normalize_roots()
    mode = Keyword.get(opts, :mode, :hard_gate)

    with :ok <- validate_mode(mode),
         {:ok, scan_paths} <- validate_scope(paths, target_roots) do
      {checked_paths, skipped_paths} =
        scan_paths
        |> Enum.flat_map(&walk(&1, target_roots))
        |> Enum.split_with(&match?({:checked, _}, &1))

      checked_paths = Enum.map(checked_paths, fn {:checked, checked_path} -> checked_path end)
      skipped_paths = Enum.map(skipped_paths, fn {:skipped, skipped_path} -> skipped_path end)

      findings =
        checked_paths
        |> Enum.flat_map(&scan_checked_path/1)
        |> Enum.sort_by(&{&1.path, &1.line, Atom.to_string(&1.rule), &1.token || ""})

      {:ok,
       %Receipt{
         scanner: @scanner,
         scanner_version: @scanner_version,
         mode: mode,
         target_roots: target_roots,
         checked_paths: checked_paths,
         skipped_paths: skipped_paths,
         zones: count_zones(checked_paths),
         findings: findings,
         status: status(mode, findings),
         phase_6a_deferred_proofs: @deferred_proofs
       }}
    end
  end

  @spec all_target_paths() :: [String.t()]
  def all_target_paths do
    @target_roots
    |> Enum.sort_by(fn {repo, _path} -> repo end)
    |> Enum.map(fn {_repo, path} -> path end)
  end

  @spec summary(Receipt.t()) :: map()
  def summary(%Receipt{} = receipt) do
    %{
      scanner: receipt.scanner,
      scanner_version: receipt.scanner_version,
      mode: receipt.mode,
      status: receipt.status,
      target_repos: receipt.target_roots |> Map.keys() |> Enum.sort(),
      checked_path_count: length(receipt.checked_paths),
      skipped_path_count: length(receipt.skipped_paths),
      zones: receipt.zones,
      finding_count: length(receipt.findings),
      findings_by_rule: count_by(receipt.findings, & &1.rule),
      findings_by_owner_phase: count_by(receipt.findings, & &1.owner_phase),
      phase_6a_deferred_proofs: receipt.phase_6a_deferred_proofs
    }
  end

  defp validate_mode(mode) when mode in [:hard_gate, :baseline], do: :ok
  defp validate_mode(mode), do: {:error, {:invalid_scan_mode, mode}}

  defp validate_scope(paths, target_roots) do
    expanded_paths = Enum.map(paths, &Path.expand/1)
    outside_paths = Enum.reject(expanded_paths, &target_path?(&1, target_roots))

    case outside_paths do
      [] -> {:ok, expanded_paths}
      _ -> {:error, {:outside_target_scope, outside_paths}}
    end
  end

  defp target_path?(path, target_roots) do
    Enum.any?(target_roots, fn {_repo, root} ->
      path == root or String.starts_with?(path, root <> "/")
    end)
  end

  defp walk(path, target_roots) do
    cond do
      excluded_path?(path) ->
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
    {repo, _root} = repo_for_path(path, target_roots)
    %CheckedPath{path: path, repo: repo, zone: classify_zone(repo, path)}
  end

  defp repo_for_path(path, target_roots) do
    Enum.find(target_roots, fn {_repo, root} ->
      path == root or String.starts_with?(path, root <> "/")
    end)
  end

  defp scan_checked_path(%CheckedPath{path: path} = checked_path) do
    content = File.read!(path)

    []
    |> Kernel.++(provider_noun_findings(checked_path, content))
    |> Kernel.++(provider_shaped_field_findings(checked_path, content))
    |> Kernel.++(app_kit_public_findings(checked_path, content))
    |> Kernel.++(ground_plane_name_findings(checked_path, content))
    |> Kernel.++(no_regular_expression_findings(checked_path, content))
  end

  defp provider_noun_findings(%CheckedPath{zone: zone} = checked_path, content)
       when zone in [
              :foundation_app_kit,
              :foundation_citadel,
              :foundation_ground_plane,
              :foundation_mezzanine
            ] do
    token_findings(checked_path, content, @provider_tokens, :provider_noun_in_foundation, %{
      reason: :provider_noun_in_foundation_zone,
      owner_phase: owner_phase(checked_path),
      remediation:
        "Move provider vocabulary into product, connector, explicit adapter, receipt, trace, fixture, or doc zones."
    })
  end

  defp provider_noun_findings(_checked_path, _content), do: []

  defp provider_shaped_field_findings(%CheckedPath{zone: zone} = checked_path, content)
       when zone in [:foundation_app_kit, :foundation_mezzanine] do
    token_findings(checked_path, content, @provider_shaped_fields, :provider_shaped_field, %{
      reason: :provider_shaped_field_in_generic_contract,
      owner_phase: owner_phase(checked_path),
      remediation:
        "Replace provider-shaped fields with generic refs, role refs, payload envelopes, or metadata."
    })
  end

  defp provider_shaped_field_findings(_checked_path, _content), do: []

  defp app_kit_public_findings(%CheckedPath{repo: "app_kit", zone: zone} = checked_path, content)
       when zone in [:foundation_app_kit, :other_project_code] do
    token_findings(
      checked_path,
      content,
      @app_kit_public_tokens,
      :provider_named_app_kit_public_api,
      %{
        reason: :provider_named_public_api,
        owner_phase: "Phase 3",
        remediation:
          "Expose product role refs and generic source/runtime/evidence methods from AppKit."
      }
    )
  end

  defp app_kit_public_findings(_checked_path, _content), do: []

  defp ground_plane_name_findings(
         %CheckedPath{zone: :foundation_ground_plane} = checked_path,
         content
       ) do
    attrs = %{
      reason: :higher_layer_name_in_ground_plane_foundation,
      owner_phase: "Phase 1",
      remediation:
        "Rename GroundPlane public packages, modules, functions, and fields to lower primitive terminology."
    }

    path_token_findings(
      checked_path,
      @ground_plane_higher_layer_tokens,
      :ground_plane_higher_layer_name,
      attrs
    ) ++
      token_findings(
        checked_path,
        content,
        @ground_plane_higher_layer_tokens,
        :ground_plane_higher_layer_name,
        attrs
      )
  end

  defp ground_plane_name_findings(_checked_path, _content), do: []

  defp no_regular_expression_findings(%CheckedPath{path: path} = checked_path, content) do
    if Path.extname(path) in @code_extensions do
      token_findings(
        checked_path,
        content,
        no_regular_expression_tokens(),
        :regular_expression_usage,
        %{
          reason: :regular_expression_token_present,
          owner_phase: "Phase 6B",
          remediation: "Replace with explicit string, tokenizer, parser, or AST logic."
        }
      )
    else
      []
    end
  end

  defp token_findings(checked_path, content, tokens, rule, attrs) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line_content, line_number} ->
      tokens
      |> Enum.filter(&line_contains_token?(line_content, &1))
      |> Enum.reject(&ignored_finding?(checked_path, line_content, &1, rule))
      |> Enum.map(fn token ->
        %Finding{
          rule: rule,
          reason: Map.fetch!(attrs, :reason),
          path: checked_path.path,
          line: line_number,
          zone: checked_path.zone,
          owner_phase: Map.fetch!(attrs, :owner_phase),
          severity: :error,
          token: token,
          remediation: Map.fetch!(attrs, :remediation)
        }
      end)
    end)
  end

  defp path_token_findings(checked_path, tokens, rule, attrs) do
    tokens
    |> Enum.filter(&line_contains_token?(checked_path.path, &1))
    |> Enum.map(fn token ->
      %Finding{
        rule: rule,
        reason: Map.fetch!(attrs, :reason),
        path: checked_path.path,
        line: 0,
        zone: checked_path.zone,
        owner_phase: Map.fetch!(attrs, :owner_phase),
        severity: :error,
        token: token,
        remediation: Map.fetch!(attrs, :remediation)
      }
    end)
  end

  defp line_contains_token?(line_content, token) do
    cond do
      token_has_separator?(token) ->
        String.contains?(line_content, token)

      true ->
        line_content
        |> token_windows(byte_size(token))
        |> Enum.any?(fn {before_token, candidate, after_token} ->
          candidate == token and token_boundary?(before_token) and token_boundary?(after_token)
        end)
    end
  end

  defp token_has_separator?(token) do
    token
    |> String.to_charlist()
    |> Enum.any?(&(not ascii_alnum?(&1)))
  end

  defp token_windows(line_content, token_size) do
    max_start = byte_size(line_content) - token_size

    if max_start < 0 do
      []
    else
      Enum.map(0..max_start, fn start ->
        before_token = if start == 0, do: nil, else: :binary.at(line_content, start - 1)
        candidate = binary_part(line_content, start, token_size)

        after_index = start + token_size

        after_token =
          if after_index >= byte_size(line_content),
            do: nil,
            else: :binary.at(line_content, after_index)

        {before_token, candidate, after_token}
      end)
    end
  end

  defp token_boundary?(nil), do: true
  defp token_boundary?(byte), do: not ascii_alnum?(byte)

  defp ascii_alnum?(byte), do: byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9

  defp ignored_finding?(
         %CheckedPath{path: path, zone: :foundation_ground_plane},
         line_content,
         "runtime",
         :ground_plane_higher_layer_name
       ) do
    Path.basename(path) == "mix.exs" and String.contains?(line_content, "runtime:")
  end

  defp ignored_finding?(
         %CheckedPath{path: path, zone: :foundation_ground_plane},
         line_content,
         "source",
         :ground_plane_higher_layer_name
       ) do
    Path.basename(path) == "mix.exs" and
      (String.contains?(line_content, "source_url:") or
         String.contains?(line_content, "source_ref:"))
  end

  defp ignored_finding?(_checked_path, _line_content, _token, _rule), do: false

  defp no_regular_expression_tokens do
    [
      "Re" <> "gex",
      "~" <> "r",
      ":" <> "re" <> ".",
      ":" <> "re" <> ",",
      ":" <> "re" <> ")",
      ":" <> "re" <> " "
    ]
  end

  defp classify_zone(repo, path) do
    segments = path_segments(path)
    basename = Path.basename(path)

    cond do
      any_segment?(segments, @doc_segments) or String.ends_with?(basename, ".md") ->
        :docs

      any_segment?(segments, @fixture_segments) ->
        :fixtures_tests

      repo == "stack_lab" and Enum.member?(segments, "no_bypass_scanner") ->
        :scanner

      repo == "extravaganza" ->
        :product

      repo == "jido_integration" and Enum.member?(segments, "connectors") ->
        :connector

      repo == "mezzanine" and adapter_path?(segments) ->
        :adapter

      repo == "app_kit" and Enum.member?(segments, "core") ->
        :foundation_app_kit

      repo == "mezzanine" and Enum.member?(segments, "core") ->
        :foundation_mezzanine

      repo == "citadel" and citadel_generic_policy_path?(segments) ->
        :foundation_citadel

      repo == "ground_plane" and Enum.member?(segments, "core") ->
        :foundation_ground_plane

      true ->
        :other_project_code
    end
  end

  defp adapter_path?(segments) do
    Enum.member?(segments, "provider_adapters") or
      contains_ordered_segments?(segments, ["bridges", "integration_bridge", "provider_adapters"])
  end

  defp citadel_generic_policy_path?(segments) do
    contains_ordered_segments?(segments, ["core", "policy_packs"]) or
      contains_ordered_segments?(segments, ["core", "authority_contract"]) or
      contains_ordered_segments?(segments, ["core", "execution_governance_contract"]) or
      contains_ordered_segments?(segments, ["core", "citadel_kernel"])
  end

  defp contains_ordered_segments?(segments, wanted) do
    segments
    |> Enum.chunk_every(length(wanted), 1, :discard)
    |> Enum.any?(&(&1 == wanted))
  end

  defp excluded_path?(path), do: any_segment?(path_segments(path), @excluded_segments)
  defp source_path?(path), do: Path.extname(path) in @source_extensions
  defp any_segment?(segments, wanted), do: Enum.any?(wanted, &Enum.member?(segments, &1))

  defp path_segments(path) do
    path
    |> Path.expand()
    |> Path.split()
  end

  defp count_zones(checked_paths) do
    Enum.reduce(checked_paths, %{}, fn checked_path, counts ->
      Map.update(counts, checked_path.zone, 1, &(&1 + 1))
    end)
  end

  defp count_by(values, fun) do
    Enum.reduce(values, %{}, fn value, counts ->
      Map.update(counts, fun.(value), 1, &(&1 + 1))
    end)
  end

  defp status(_mode, []), do: :pass
  defp status(:baseline, [_ | _]), do: :baseline_findings
  defp status(:hard_gate, [_ | _]), do: :open_defect

  defp owner_phase(%CheckedPath{repo: "app_kit"}), do: "Phase 3"
  defp owner_phase(%CheckedPath{repo: "mezzanine"}), do: "Phase 2 or Phase 4"
  defp owner_phase(%CheckedPath{repo: "citadel"}), do: "Phase 4B"
  defp owner_phase(%CheckedPath{repo: "ground_plane"}), do: "Phase 1"
  defp owner_phase(_checked_path), do: "Phase 6A"

  defp normalize_roots(roots) when is_map(roots) do
    roots
    |> Enum.map(fn {repo, path} -> {repo, Path.expand(path)} end)
    |> Map.new()
  end

  defp normalize_roots(roots) when is_list(roots), do: roots |> Map.new() |> normalize_roots()
end
