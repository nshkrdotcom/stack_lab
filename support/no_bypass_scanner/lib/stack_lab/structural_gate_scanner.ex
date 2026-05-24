defmodule StackLab.StructuralGateScanner do
  @moduledoc """
  Phase 6A structural scanner gate for generic stack cutovers.

  This scanner intentionally uses exact string, token, and AST traversal only.
  """

  alias StackLab.StructuralGate.{
    Allowlists,
    ProofBundleRegistry,
    Reporter,
    RuleText,
    TargetRoots,
    Traversal,
    Zones
  }

  alias StackLab.StructuralGateScanner.{
    AllowlistEntry,
    CheckedPath,
    Finding,
    ProofBundle,
    Receipt
  }

  @scanner "stack_lab.structural_gate_scanner"
  @scanner_version "0.1.0"

  @ast_extensions [".ex", ".exs"]

  @provider_tokens [
    "Linear",
    "linear.",
    "linear_",
    "/linear",
    "Github",
    "GitHub",
    "github.",
    "github_",
    "/github",
    "Codex",
    "codex.",
    "codex_",
    "/codex",
    "Symphony",
    "symphony.",
    "symphony_",
    "/symphony",
    "OpenAI",
    "openai.",
    "openai_",
    "/openai",
    "pull_number",
    "pull_request",
    "issue_id",
    "repo_full_name",
    "commit_sha",
    "GH_TOKEN",
    "GITHUB_TOKEN",
    "LINEAR_API_KEY",
    "OPENAI_API_KEY",
    "CODEX_API_KEY"
  ]

  @provider_module_tokens [
    "LinearIssue",
    "LinearSourceFlow",
    "LinearSourceDispatcher",
    "LinearGraphqlToolExecutor",
    "LinearGraphQLToolExecutor",
    "CodexAgentRuntime",
    "GitHubPrEvidence",
    "GitHubPrEvidenceRuntime",
    "GitHubPrBranchCleanupRuntime",
    "GitHubPrDispatcher",
    "GitHubPrEvidenceReceipt",
    "GitHubPrBranchCleanupReceipt"
  ]

  @provider_field_tokens [
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

  @raw_credential_boundary_tokens [
    "credential_material",
    "raw_credential",
    "api_key",
    "access_token",
    "refresh_token",
    "client_secret",
    "github_token",
    "linear_api_key",
    "codex_api_key"
  ]

  @classified_provider_public_tokens [
    "provider_account_ref",
    "provider_account_status",
    "provider_pool_ref",
    "reassign_provider"
  ]

  @provider_name_parts ["linear", "github", "codex", "openai", "symphony"]
  @closed_provider_dispatch_names [
    "amp",
    "claude",
    "codex",
    "gemini",
    "github",
    "linear",
    "notion",
    "openai"
  ]
  @provider_binding_refs ["linear_primary", "github_primary", "codex_primary"]

  @product_lower_owner_module_prefixes [
    "AITrace",
    "Anthropic",
    "Citadel",
    "Codex",
    "ExecutionPlane",
    "GEPA",
    "GEPAFramework",
    "Gepa",
    "GepaFramework",
    "GitHubEx",
    "GroundPlane",
    "Inference",
    "Jido",
    "Jido.Integration",
    "JidoIntegration",
    "Linear",
    "Mezzanine",
    "OpenAI",
    "OuterBrain",
    "ReqLLM",
    "Trinity",
    "TrinityFramework"
  ]

  @ground_plane_higher_layer_tokens [
    "AI",
    "ai",
    "agent",
    "workflow",
    "work_item",
    "product",
    "provider",
    "connector",
    "manifest",
    "model",
    "runtime",
    "lane",
    "source",
    "evidence",
    "review",
    "policy_pack"
  ]

  @generic_operation_names ProofBundleRegistry.required_generic_functions()

  @lane_tokens [
    "mezzanine.agentic",
    "mezzanine.semantic",
    "mezzanine.hazmat",
    "mezzanine.review",
    "operator_terminal",
    "process_lane",
    "node_lane",
    "hazmat"
  ]

  @branch_tokens ["case ", "cond do", "if "]

  @type scan_option ::
          {:target_roots, %{String.t() => String.t()} | [{String.t(), String.t()}]}
          | {:mode, :hard_gate | :baseline}
          | {:allowlist, [map() | keyword() | AllowlistEntry.t()]}
          | {:remote_deployment?, boolean()}

  @spec target_roots() :: %{String.t() => String.t()}
  def target_roots, do: TargetRoots.default()

  @spec all_target_paths() :: [String.t()]
  def all_target_paths, do: TargetRoots.all_paths(target_roots())

  @spec scan([String.t()], [scan_option()]) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(paths, opts \\ []) when is_list(paths) do
    target_roots = opts |> Keyword.get(:target_roots, target_roots()) |> TargetRoots.normalize()
    mode = Keyword.get(opts, :mode, :hard_gate)
    remote_deployment? = Keyword.get(opts, :remote_deployment?, false)

    with :ok <- validate_mode(mode),
         {:ok, allowlist} <- Allowlists.normalize(Keyword.get(opts, :allowlist, [])),
         :ok <- Allowlists.validate(allowlist),
         :ok <- validate_proof_bundle_registry(),
         {:ok, scan_paths} <- TargetRoots.validate_scope(paths, target_roots) do
      {checked_paths, skipped_paths} =
        scan_paths
        |> Enum.flat_map(&Traversal.walk(&1, target_roots))
        |> Enum.split_with(&match?({:checked, _}, &1))

      checked_paths = Enum.map(checked_paths, fn {:checked, checked_path} -> checked_path end)
      skipped_paths = Enum.map(skipped_paths, fn {:skipped, skipped_path} -> skipped_path end)

      {findings, proof_bundles} =
        checked_paths
        |> Enum.map(&scan_checked_path(&1, remote_deployment?))
        |> Enum.reduce({[], []}, fn {path_findings, path_proofs}, {all_findings, all_proofs} ->
          {path_findings ++ all_findings, path_proofs ++ all_proofs}
        end)

      findings =
        findings
        |> Enum.map(&Allowlists.apply(&1, allowlist))
        |> Enum.sort_by(
          &{&1.path, &1.line, Atom.to_string(&1.rule), RuleText.token_sort(&1.token)}
        )

      blocking_findings = Enum.reject(findings, & &1.allowlist_entry)

      {:ok,
       %Receipt{
         scanner: @scanner,
         scanner_version: @scanner_version,
         mode: mode,
         target_roots: target_roots,
         target_scope_status: TargetRoots.scope_status(target_roots),
         checked_paths: checked_paths,
         skipped_paths: skipped_paths,
         zones: count_zones(checked_paths),
         findings: findings,
         proof_bundles: Enum.sort_by(proof_bundles, &{&1.path, &1.line, &1.operation_name}),
         remote_boundary: remote_boundary(remote_deployment?),
         status: status(mode, blocking_findings)
       }}
    end
  end

  @spec summary(Receipt.t()) :: map()
  def summary(%Receipt{} = receipt), do: Reporter.summary(receipt)

  defp validate_mode(mode) when mode in [:hard_gate, :baseline], do: :ok
  defp validate_mode(mode), do: {:error, {:invalid_scan_mode, mode}}

  defp validate_proof_bundle_registry do
    case ProofBundleRegistry.validate_entries() do
      :ok -> :ok
      {:error, errors} -> {:error, {:invalid_proof_bundle_registry, errors}}
    end
  end

  defp scan_checked_path(%CheckedPath{path: path} = checked_path, remote_deployment?) do
    content = File.read!(path)

    token_findings =
      []
      |> Kernel.++(provider_noun_findings(checked_path, content))
      |> Kernel.++(provider_module_findings(checked_path, content))
      |> Kernel.++(provider_field_findings(checked_path, content))
      |> Kernel.++(provider_public_vocabulary_findings(checked_path, content))
      |> Kernel.++(duplicated_provider_family_list_findings(checked_path, content))
      |> Kernel.++(ambiguous_adapter_class_findings(checked_path, content))
      |> Kernel.++(ground_plane_name_findings(checked_path, content))
      |> Kernel.++(app_kit_binding_ref_token_findings(checked_path, content))
      |> Kernel.++(lane_branch_findings(checked_path, content))
      |> Kernel.++(citadel_policy_findings(checked_path, content))

    {ast_findings, proof_bundles} = ast_scan(checked_path, content, remote_deployment?)

    {token_findings ++ ast_findings, proof_bundles}
  end

  defp provider_noun_findings(%CheckedPath{zone: zone} = checked_path, content)
       when zone in [:generic, :generic_policy, :ground_plane] do
    token_findings(checked_path, content, @provider_tokens, :provider_noun_in_generic_code, %{
      reason: :provider_noun_in_generic_zone,
      owner_phase: owner_phase(checked_path),
      ast_role: :string_or_identifier,
      remediation:
        "Move provider vocabulary to product, connector, adapter, fixture, doc, receipt, or trace zones."
    })
  end

  defp provider_noun_findings(_checked_path, _content), do: []

  defp provider_module_findings(%CheckedPath{zone: zone} = checked_path, content)
       when zone in [:generic, :generic_policy] do
    token_findings(
      checked_path,
      content,
      @provider_module_tokens,
      :provider_module_in_generic_code,
      %{
        reason: :provider_module_token_in_generic_zone,
        owner_phase: owner_phase(checked_path),
        ast_role: :module_token,
        remediation:
          "Move provider modules to explicit adapter/connector zones and call them through binding/manifest data."
      }
    )
  end

  defp provider_module_findings(%CheckedPath{repo: "mezzanine"} = checked_path, content) do
    if Zones.integration_bridge_root?(checked_path.path) do
      token_findings(
        checked_path,
        content,
        @provider_module_tokens,
        :provider_module_in_bridge_root,
        %{
          reason: :provider_module_token_in_bridge_root,
          owner_phase: "Phase 6A",
          ast_role: :module_token,
          remediation:
            "Move provider orchestration under a scanner-classified provider adapter zone or Jido connector package."
        }
      )
    else
      []
    end
  end

  defp provider_module_findings(_checked_path, _content), do: []

  defp provider_field_findings(%CheckedPath{zone: zone} = checked_path, content)
       when zone in [:generic, :generic_policy] do
    token_findings(checked_path, content, @provider_field_tokens, :provider_shaped_dto_field, %{
      reason: :provider_shaped_field_in_generic_contract,
      owner_phase: owner_phase(checked_path),
      ast_role: :field_token,
      remediation:
        "Replace provider-shaped fields with generic refs, role refs, envelopes, metadata, or extensions."
    })
  end

  defp provider_field_findings(_checked_path, _content), do: []

  defp provider_public_vocabulary_findings(%CheckedPath{zone: zone} = checked_path, content)
       when zone in [:generic, :generic_policy, :other_project_code] do
    if Zones.provider_public_vocabulary_allowed_path?(checked_path.path) do
      []
    else
      token_findings(
        checked_path,
        content,
        @classified_provider_public_tokens,
        :unclassified_provider_public_vocabulary,
        %{
          reason: :provider_public_vocabulary_without_classified_owner,
          owner_phase: "Phase 4",
          ast_role: :field_token,
          remediation:
            "Move provider-account/provider-pool vocabulary to a classified authority, credential, scheduling, connector, receipt, or projection owner."
        }
      )
    end
  end

  defp provider_public_vocabulary_findings(_checked_path, _content), do: []

  defp duplicated_provider_family_list_findings(%CheckedPath{zone: zone} = checked_path, content) do
    if zone in [:fixtures_tests, :docs, :scanner] or
         Zones.canonical_provider_classification_path?(checked_path.path) do
      []
    else
      token_findings(
        checked_path,
        content,
        ["@provider_families ["],
        :duplicated_provider_family_list,
        %{
          reason: :provider_family_list_not_contract_backed,
          owner_phase: "Phase 4",
          ast_role: :module_attribute,
          remediation:
            "Read provider family and account-status vocabulary from Jido.Integration.V2.ProviderClassification."
        }
      )
    end
  end

  defp ambiguous_adapter_class_findings(%CheckedPath{zone: zone} = checked_path, content) do
    if zone in [:fixtures_tests, :docs, :scanner] do
      []
    else
      token_findings(
        checked_path,
        content,
        [":shimmed", "\"shimmed\"", "'shimmed'"],
        :ambiguous_adapter_class,
        %{
          reason: :ambiguous_adapter_class,
          owner_phase: "Phase 4",
          ast_role: :classification_token,
          remediation:
            "Replace ambiguous shim classifications with the explicit :connector_facade adapter placement."
        }
      )
    end
  end

  defp ground_plane_name_findings(%CheckedPath{zone: :ground_plane} = checked_path, content) do
    attrs = %{
      reason: :higher_layer_name_in_ground_plane_public_surface,
      owner_phase: "Phase 1",
      ast_role: :name_token,
      remediation:
        "Rename GroundPlane packages, modules, functions, resources, and contracts to primitive terminology."
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

  defp app_kit_binding_ref_token_findings(
         %CheckedPath{repo: "app_kit", zone: zone} = checked_path,
         content
       )
       when zone in [:generic, :other_project_code] do
    token_findings(
      checked_path,
      content,
      @provider_binding_refs,
      :provider_shaped_binding_ref_at_appkit_boundary,
      %{
        reason: :provider_shaped_binding_ref_at_product_boundary,
        owner_phase: "Phase 3",
        ast_role: :string_or_atom,
        remediation:
          "Product-facing AppKit APIs must accept product role refs, not concrete provider bindings."
      }
    )
  end

  defp app_kit_binding_ref_token_findings(_checked_path, _content), do: []

  defp lane_branch_findings(%CheckedPath{repo: repo, zone: :generic} = checked_path, content)
       when repo in ["app_kit", "mezzanine"] do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if RuleText.contains_any?(line, @lane_tokens) and
           RuleText.contains_any?(line, @branch_tokens) do
        [
          finding(checked_path, %{
            rule: :lane_branch_in_generic_code,
            reason: :generic_code_branches_on_lane_name,
            line: line_number,
            token: RuleText.first_present(line, @lane_tokens),
            ast_role: :control_flow,
            owner_phase: "Phase 6A",
            remediation:
              "Lane candidates must come from Jido descriptors or Execution Plane mechanics after plan capture."
          })
        ]
      else
        []
      end
    end)
  end

  defp lane_branch_findings(_checked_path, _content), do: []

  defp citadel_policy_findings(
         %CheckedPath{repo: "citadel", zone: :generic_policy} = checked_path,
         content
       ) do
    tokens = @provider_field_tokens ++ @provider_module_tokens ++ ["github.", "linear.", "codex."]

    token_findings(
      checked_path,
      content,
      tokens,
      :provider_operation_in_citadel_generic_policy,
      %{
        reason: :provider_operation_id_in_generic_policy,
        owner_phase: "Phase 6A",
        ast_role: :policy_data,
        remediation:
          "Citadel generic policy authorizes operation classes, manifest refs, and binding refs, not provider operation ids."
      }
    )
  end

  defp citadel_policy_findings(_checked_path, _content), do: []

  defp ast_scan(%CheckedPath{path: path} = checked_path, content, remote_deployment?) do
    if Path.extname(path) in @ast_extensions do
      case Code.string_to_quoted(content, columns: true) do
        {:ok, ast} -> ast_findings_and_proofs(checked_path, content, ast, remote_deployment?)
        {:error, _reason} -> {[], []}
      end
    else
      {[], []}
    end
  end

  defp ast_findings_and_proofs(checked_path, content, ast, remote_deployment?) do
    {_ast, {findings, proof_bundles}} =
      Macro.prewalk(ast, {[], []}, fn node, {findings, proof_bundles} ->
        {node_findings, node_proofs} =
          ast_node_findings(checked_path, content, node, remote_deployment?)

        {node, {node_findings ++ findings, node_proofs ++ proof_bundles}}
      end)

    {findings, proof_bundles}
  end

  defp ast_node_findings(checked_path, content, {:def, meta, [head | _]}, remote_deployment?) do
    public_function_findings(checked_path, content, meta, head, :function, remote_deployment?)
  end

  defp ast_node_findings(
         checked_path,
         content,
         {:defdelegate, meta, [head | _]},
         remote_deployment?
       ) do
    public_function_findings(checked_path, content, meta, head, :delegate, remote_deployment?)
  end

  defp ast_node_findings(
         checked_path,
         _content,
         {:@, meta, [{:callback, _callback_meta, [spec]}]},
         _remote?
       ) do
    {name, args} = callback_name_and_args(spec)

    findings =
      []
      |> Kernel.++(app_kit_provider_public_name_findings(checked_path, meta, name, :callback))
      |> Kernel.++(app_kit_binding_arg_findings(checked_path, meta, args, :callback))

    {findings, []}
  end

  defp ast_node_findings(checked_path, _content, {:defstruct, meta, [fields]}, _remote?) do
    {struct_field_findings(checked_path, meta, fields, :struct_field), []}
  end

  defp ast_node_findings(
         checked_path,
         _content,
         {:@, meta, [{:enforce_keys, _key_meta, [keys]}]},
         _remote?
       ) do
    {struct_field_findings(checked_path, meta, keys, :enforce_key), []}
  end

  defp ast_node_findings(checked_path, _content, {:alias, meta, [alias_ast]}, _remote?) do
    findings =
      provider_remote_reference_findings(checked_path, meta, alias_ast, :alias) ++
        product_lower_owner_reference_findings(checked_path, meta, alias_ast, :alias)

    {findings, []}
  end

  defp ast_node_findings(checked_path, _content, {:import, meta, [alias_ast | _]}, _remote?) do
    findings =
      provider_remote_reference_findings(checked_path, meta, alias_ast, :import) ++
        product_lower_owner_reference_findings(checked_path, meta, alias_ast, :import)

    {findings, []}
  end

  defp ast_node_findings(
         checked_path,
         _content,
         {{:., meta, [alias_ast, function_name]}, _call_meta, _args},
         _remote?
       )
       when is_atom(function_name) do
    findings =
      provider_remote_reference_findings(checked_path, meta, alias_ast, :remote_call) ++
        product_lower_owner_reference_findings(checked_path, meta, alias_ast, :remote_call)

    {findings, []}
  end

  defp ast_node_findings(checked_path, _content, {:%{}, meta, fields}, _remote?) do
    {closed_provider_dispatch_map_findings(checked_path, meta, fields), []}
  end

  defp ast_node_findings(
         checked_path,
         _content,
         {:case, meta, [subject, [do: clauses]]},
         _remote?
       ) do
    {closed_provider_dispatch_case_findings(checked_path, meta, subject, clauses), []}
  end

  defp ast_node_findings(_checked_path, _content, _node, _remote?), do: {[], []}

  defp public_function_findings(checked_path, content, meta, head, role, remote_deployment?) do
    {name, args} = function_name_and_args(head)
    arity = length(args)
    registry_entry = ProofBundleRegistry.find(checked_path.path, name, arity)

    findings =
      []
      |> Kernel.++(app_kit_provider_public_name_findings(checked_path, meta, name, role))
      |> Kernel.++(app_kit_binding_arg_findings(checked_path, meta, args, role))

    proof_bundle =
      cond do
        registry_entry ->
          proof =
            proof_bundle(
              checked_path,
              content,
              meta,
              name,
              arity,
              registry_entry,
              remote_deployment?
            )

          {proof_findings(checked_path, proof), [proof]}

        generic_entrypoint_requires_bundle?(checked_path, name) ->
          {[unregistered_generic_entrypoint_finding(checked_path, meta, name)], []}

        true ->
          {[], []}
      end

    {proof_findings, proof_bundles} = proof_bundle
    {findings ++ proof_findings, proof_bundles}
  end

  defp generic_entrypoint_requires_bundle?(%CheckedPath{zone: :generic} = checked_path, name)
       when name in @generic_operation_names do
    not generic_entrypoint_name_collision?(checked_path, name)
  end

  defp generic_entrypoint_requires_bundle?(_checked_path, _name), do: false

  defp generic_entrypoint_name_collision?(%CheckedPath{path: path}, :publish) do
    String.ends_with?(path, "/mezzanine/config_registry/cluster_invalidation.ex")
  end

  defp generic_entrypoint_name_collision?(_checked_path, _name), do: false

  defp unregistered_generic_entrypoint_finding(checked_path, meta, name) do
    finding(checked_path, %{
      rule: :generic_dispatch_entrypoint_unregistered,
      reason: :missing_structural_proof_bundle,
      line: meta_line(meta),
      token: name,
      ast_role: :generic_operation,
      owner_phase: "Phase 3",
      structural_proof_status: :unregistered,
      remediation:
        "Add a StackLab.StructuralGate.ProofBundleRegistry entry with requirements, paired test path, and negative fixture coverage."
    })
  end

  defp app_kit_provider_public_name_findings(
         %CheckedPath{repo: "app_kit", zone: zone} = checked_path,
         meta,
         name,
         ast_role
       )
       when zone in [:generic, :other_project_code] and is_atom(name) do
    name_text = name |> Atom.to_string() |> String.downcase()

    if RuleText.contains_any?(name_text, @provider_name_parts) do
      [
        finding(checked_path, %{
          rule: :provider_named_app_kit_public_api,
          reason: :provider_named_public_api,
          line: meta_line(meta),
          token: name,
          ast_role: ast_role,
          owner_phase: "Phase 3",
          remediation:
            "Expose product role refs and generic source/runtime/evidence methods from AppKit."
        })
      ]
    else
      []
    end
  end

  defp app_kit_provider_public_name_findings(_checked_path, _meta, _name, _role), do: []

  defp app_kit_binding_arg_findings(
         %CheckedPath{repo: "app_kit", zone: zone} = checked_path,
         meta,
         args,
         ast_role
       )
       when zone in [:generic, :other_project_code] do
    args
    |> Enum.filter(&String.ends_with?(&1, "_binding_ref"))
    |> Enum.map(fn arg ->
      finding(checked_path, %{
        rule: :concrete_binding_ref_at_appkit_boundary,
        reason: :product_facing_api_requires_concrete_binding_ref,
        line: meta_line(meta),
        token: arg,
        ast_role: ast_role,
        owner_phase: "Phase 3",
        remediation:
          "Product-facing AppKit APIs must take a product role ref and resolve concrete bindings inside Mezzanine."
      })
    end)
  end

  defp app_kit_binding_arg_findings(_checked_path, _meta, _args, _role), do: []

  defp struct_field_findings(%CheckedPath{zone: zone} = checked_path, meta, fields, ast_role)
       when zone in [:generic, :generic_policy] do
    field_names = field_names(fields)

    provider_field_findings =
      field_names
      |> Enum.filter(&(&1 in @provider_field_tokens))
      |> Enum.map(fn field ->
        finding(checked_path, %{
          rule: :provider_shaped_dto_field,
          reason: :provider_shaped_field_in_generic_contract,
          line: meta_line(meta),
          token: field,
          ast_role: ast_role,
          owner_phase: owner_phase(checked_path),
          remediation:
            "Replace provider-shaped fields with generic refs, role refs, envelopes, metadata, or extensions."
        })
      end)

    raw_credential_field_findings =
      field_names
      |> Enum.filter(&(&1 in @raw_credential_boundary_tokens))
      |> Enum.map(fn field ->
        finding(checked_path, %{
          rule: :raw_credential_in_generic_boundary,
          reason: :raw_credential_in_generic_boundary,
          line: meta_line(meta),
          token: field,
          ast_role: ast_role,
          owner_phase: "Phase 5",
          remediation:
            "Replace raw credential fields with lease refs, secret provider refs, secret scopes, or brokered call-scope materializers."
        })
      end)

    provider_field_findings ++ raw_credential_field_findings
  end

  defp struct_field_findings(_checked_path, _meta, _fields, _role), do: []

  defp provider_remote_reference_findings(
         %CheckedPath{zone: zone} = checked_path,
         meta,
         alias_ast,
         ast_role
       )
       when zone in [:generic, :generic_policy] do
    alias_text = alias_to_string(alias_ast)

    case RuleText.first_present(alias_text, @provider_module_tokens) do
      nil ->
        []

      token ->
        [
          finding(checked_path, %{
            rule:
              if(Zones.integration_bridge_root?(checked_path.path),
                do: :provider_module_in_bridge_root,
                else: :provider_module_in_generic_code
              ),
            reason: :provider_module_reference_in_generic_code,
            line: meta_line(meta),
            token: token,
            ast_role: ast_role,
            owner_phase: "Phase 6A",
            remediation:
              "Move provider module references to adapter/connector zones and call them through manifest data."
          })
        ]
    end
  end

  defp provider_remote_reference_findings(_checked_path, _meta, _alias_ast, _role), do: []

  defp product_lower_owner_reference_findings(
         %CheckedPath{repo: "extravaganza", zone: :product} = checked_path,
         meta,
         alias_ast,
         ast_role
       ) do
    alias_text = alias_to_string(alias_ast)

    cond do
      alias_text == "" ->
        []

      allowed_product_lower_owner_reference?(alias_text) ->
        []

      product_lower_owner_reference?(alias_text) ->
        [
          finding(checked_path, %{
            rule: :direct_lower_owner_import_in_product,
            reason: :product_direct_lower_owner_reference,
            line: meta_line(meta),
            token: alias_text,
            ast_role: ast_role,
            owner_phase: "Phase 1",
            remediation:
              "Product code must enter governed behavior through AppKit surfaces; pure Mezzanine.Pack authoring is the only lower exception."
          })
        ]

      true ->
        []
    end
  end

  defp product_lower_owner_reference_findings(_checked_path, _meta, _alias_ast, _role), do: []

  defp product_lower_owner_reference?(alias_text) do
    Enum.any?(@product_lower_owner_module_prefixes, fn prefix ->
      alias_text == prefix or String.starts_with?(alias_text, prefix <> ".")
    end)
  end

  defp allowed_product_lower_owner_reference?(alias_text) do
    alias_text == "Mezzanine.Pack" or String.starts_with?(alias_text, "Mezzanine.Pack.")
  end

  defp closed_provider_dispatch_map_findings(checked_path, meta, fields) do
    if Zones.closed_provider_dispatch_scan_path?(checked_path) do
      provider_keys =
        fields
        |> Enum.flat_map(&map_provider_key/1)
        |> Enum.uniq()

      if length(provider_keys) >= 2 do
        [
          finding(checked_path, %{
            rule: :closed_provider_dispatch_map_in_core,
            reason: :provider_keyed_dispatch_map_in_jido_core,
            line: meta_line(meta),
            token: Enum.join(provider_keys, ","),
            ast_role: :map_literal,
            owner_phase: "Phase 37",
            remediation:
              "Move provider-specific dispatch to connector packages or canonical vocabulary data; core dispatch must resolve from manifest and capability data."
          })
        ]
      else
        []
      end
    else
      []
    end
  end

  defp closed_provider_dispatch_case_findings(checked_path, meta, subject, clauses) do
    if Zones.closed_provider_dispatch_scan_path?(checked_path) do
      provider_clauses =
        clauses
        |> Enum.flat_map(&provider_case_clause_tokens/1)
        |> Enum.uniq()

      subject_text = subject |> Macro.to_string() |> String.downcase()

      if length(provider_clauses) >= 2 or
           (provider_clauses != [] and String.contains?(subject_text, "provider")) do
        [
          finding(checked_path, %{
            rule: :closed_provider_dispatch_branch_in_core,
            reason: :provider_branch_dispatch_in_jido_core,
            line: meta_line(meta),
            token: Enum.join(provider_clauses, ","),
            ast_role: :case_branch,
            owner_phase: "Phase 37",
            remediation:
              "Replace provider-name branching with manifest, capability, connector registry, or provider classification data."
          })
        ]
      else
        []
      end
    else
      []
    end
  end

  defp proof_bundle(
         checked_path,
         content,
         meta,
         operation_name,
         operation_arity,
         %ProofBundleRegistry.Entry{} = registry_entry,
         remote_deployment?
       ) do
    checks =
      checked_path
      |> proof_checks(content)
      |> maybe_mark_appkit_generic_facade(checked_path, content)
      |> maybe_mark_appkit_backend_facade(checked_path, content)
      |> Map.put(:paired_test_exists, ProofBundleRegistry.paired_test_exists?(registry_entry))

    requirements = [:paired_test_exists | registry_entry.requirements]
    missing = Enum.reject(requirements, &Map.get(checks, &1))

    %ProofBundle{
      path: checked_path.path,
      line: meta_line(meta),
      entrypoint_id: registry_entry.id,
      entrypoint_kind: registry_entry.entrypoint_kind,
      operation_name: operation_name,
      operation_arity: operation_arity,
      zone: checked_path.zone,
      status: if(missing == [], do: :passed, else: :incomplete),
      checks: checks,
      missing_checks: missing,
      paired_test_path: registry_entry.paired_test_path,
      negative_fixture_id: registry_entry.negative_fixture_id,
      remote_boundary: remote_boundary(remote_deployment?)
    }
  end

  defp proof_checks(_checked_path, content) do
    %{
      product_role_ref: RuleText.contains_any?(content, ["role_ref", "product_role_ref"]),
      binding_resolved:
        RuleText.contains_any?(content, [
          "BindingResolver",
          "binding_resolver",
          "resolve_binding",
          "binding_ref",
          "CompiledBinding",
          "RunBindingSnapshot.by_run_binding",
          "active_operation_plan"
        ]),
      binding_supplied:
        RuleText.contains_any?(content, [
          "source_binding",
          "runtime_binding",
          "tool_binding",
          "evidence_binding",
          "resource_effect_binding",
          "normalize_binding"
        ]),
      operation_plan_captured:
        RuleText.contains_any?(content, [
          "ResolvedOperationPlan",
          "resolved_operation_plan",
          "operation_plan",
          "operation_plan_ref",
          "operation_plans_by_node_ref"
        ]),
      authority_checked: RuleText.contains_any?(content, ["Citadel", "authority", "authorize"]),
      manifest_resolved:
        RuleText.contains_any?(content, [
          "Manifest",
          "manifest",
          "operation_descriptor",
          "manifest_dependencies"
        ]),
      boundary_envelope_sent:
        RuleText.contains_any?(content, [
          "GovernedInvocationEnvelope",
          "ExecutionInstruction",
          "EffectRequest",
          "dispatch_envelope"
        ]),
      receipt_emitted:
        RuleText.contains_any?(content, [
          "EffectReceipt",
          "OperationReceipt",
          "OperationGroupReceipt",
          "effect_receipt",
          "operation_receipt",
          "operation_group_receipt"
        ]),
      lineage_events_emitted:
        RuleText.contains_any?(content, [
          "EffectLog",
          "LineageEventOutbox",
          "OperationLineageEvent",
          "effect_transition",
          "lineage_events",
          "lineage_event"
        ]),
      production_reducer_consumes_receipt:
        RuleText.contains_any?(content, ["ReceiptReducer", "production_reducer", "reduce("]),
      generic_surface_dispatch:
        RuleText.contains_any?(content, ["GenericSurfaceSupport.dispatch"]),
      backend_dispatch:
        RuleText.contains_any?(content, [
          "backend(opts)",
          "BackendConfig.resolve",
          "source_backend"
        ]),
      adapter_resolved:
        RuleText.contains_any?(content, [
          "source_adapter",
          "runtime_adapter",
          "tool_adapter",
          "evidence_adapter",
          "resource_effect_adapter",
          "ProviderAdapters.resolve",
          "adapter("
        ]),
      allowed_operations_scoped: RuleText.contains_any?(content, ["allowed_operations"]),
      snapshot_or_epoch_checked:
        RuleText.contains_any?(content, [
          "expected_binding_epoch",
          "RunBindingSnapshot",
          "binding_epoch",
          "ActiveBindingSet",
          "active_binding_set"
        ]),
      operation_graph_schedules_intents:
        RuleText.contains_any?(content, [
          "ActivityIntent",
          "ready_activity_intents",
          "operation_plan_ref"
        ]),
      operation_graph_records_results:
        RuleText.contains_any?(content, [
          "ActivityResultFact",
          "record_activity_result",
          "terminal?",
          "CancellationIntent",
          "CompensationIntent"
        ]),
      projection_reducer_consumes_receipt:
        RuleText.contains_any?(content, [
          "OperationReceipt",
          "ReceiptReducer",
          "SubjectRuntimeProjection"
        ]),
      bounded_ref_chasing: not RuleText.contains_any?(content, unbounded_ref_chasing_tokens())
    }
  end

  defp maybe_mark_appkit_generic_facade(checks, checked_path, content) do
    if appkit_generic_facade?(checked_path, content) do
      checks
      |> Map.put(:product_role_ref, true)
      |> Map.put(:generic_surface_dispatch, true)
      |> Map.put(:bounded_ref_chasing, checks.bounded_ref_chasing)
    else
      checks
    end
  end

  defp maybe_mark_appkit_backend_facade(checks, checked_path, content) do
    if appkit_backend_facade?(checked_path, content) do
      checks
      |> Map.put(:product_role_ref, true)
      |> Map.put(:backend_dispatch, true)
      |> Map.put(:bounded_ref_chasing, checks.bounded_ref_chasing)
    else
      checks
    end
  end

  defp proof_findings(_checked_path, %ProofBundle{status: :passed}), do: []

  defp proof_findings(checked_path, %ProofBundle{} = proof) do
    [
      finding(checked_path, %{
        rule: :generic_dispatch_proof_incomplete,
        reason: :generic_operation_missing_structural_proof,
        line: proof.line,
        token: proof.operation_name,
        ast_role: :generic_operation,
        owner_phase: "Phase 6A",
        structural_proof_status: :incomplete,
        remediation:
          "Satisfy the registered structural proof bundle requirements and keep the paired contract test executable."
      })
    ]
  end

  defp function_name_and_args({:when, _meta, [head | _guards]}), do: function_name_and_args(head)

  defp function_name_and_args({name, _meta, args}) when is_atom(name) do
    {name, arg_names(args)}
  end

  defp function_name_and_args(_other), do: {nil, []}

  defp callback_name_and_args({:"::", _meta, [left | _right]}), do: callback_name_and_args(left)
  defp callback_name_and_args({name, _meta, args}) when is_atom(name), do: {name, arg_names(args)}
  defp callback_name_and_args(_other), do: {nil, []}

  defp arg_names(nil), do: []

  defp arg_names(args) when is_list(args) do
    Enum.flat_map(args, &arg_name/1)
  end

  defp arg_name({:\\, _meta, [arg, _default]}), do: arg_name(arg)

  defp arg_name({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: [Atom.to_string(name)]

  defp arg_name({_name, _meta, args}) when is_list(args), do: Enum.flat_map(args, &arg_name/1)
  defp arg_name(_other), do: []

  defp field_names(fields) when is_list(fields) do
    Enum.flat_map(fields, &field_name/1)
  end

  defp field_names(_fields), do: []

  defp field_name({key, _value}) when is_atom(key), do: [Atom.to_string(key)]
  defp field_name(key) when is_atom(key), do: [Atom.to_string(key)]
  defp field_name(key) when is_binary(key), do: [key]
  defp field_name(_other), do: []

  defp map_provider_key({:"=>", _meta, [key, _value]}), do: provider_literal_tokens(key)
  defp map_provider_key({key, _value}) when is_atom(key), do: provider_literal_tokens(key)
  defp map_provider_key(_field), do: []

  defp provider_case_clause_tokens({:->, _meta, [patterns, _body]}) when is_list(patterns) do
    Enum.flat_map(patterns, &provider_literal_tokens/1)
  end

  defp provider_case_clause_tokens(_clause), do: []

  defp provider_literal_tokens(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> provider_name_tokens()
  end

  defp provider_literal_tokens(value) when is_binary(value), do: provider_name_tokens(value)

  defp provider_literal_tokens(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.flat_map(&provider_literal_tokens/1)
  end

  defp provider_literal_tokens(list) when is_list(list) do
    Enum.flat_map(list, &provider_literal_tokens/1)
  end

  defp provider_literal_tokens(_value), do: []

  defp provider_name_tokens(value) when is_binary(value) do
    value = String.downcase(value)
    Enum.filter(@closed_provider_dispatch_names, &(&1 == value))
  end

  defp alias_to_string({:__aliases__, _meta, parts}) do
    Enum.map_join(parts, ".", &alias_part_to_string/1)
  end

  defp alias_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp alias_to_string(_other), do: ""

  defp alias_part_to_string(part) when is_atom(part), do: Atom.to_string(part)
  defp alias_part_to_string(_part), do: ""

  defp token_findings(checked_path, content, tokens, rule, attrs) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line_content, line_number} ->
      tokens
      |> Enum.filter(&RuleText.line_contains_token?(line_content, &1))
      |> Enum.reject(&ignored_finding?(checked_path, line_content, &1, rule))
      |> Enum.map(fn token ->
        finding(checked_path, %{
          rule: rule,
          reason: Map.fetch!(attrs, :reason),
          line: line_number,
          token: token,
          ast_role: Map.fetch!(attrs, :ast_role),
          owner_phase: Map.fetch!(attrs, :owner_phase),
          remediation: Map.fetch!(attrs, :remediation)
        })
      end)
    end)
  end

  defp path_token_findings(checked_path, tokens, rule, attrs) do
    tokens
    |> Enum.filter(&RuleText.line_contains_token?(checked_path.path, &1))
    |> Enum.map(fn token ->
      finding(checked_path, %{
        rule: rule,
        reason: Map.fetch!(attrs, :reason),
        line: 0,
        token: token,
        ast_role: Map.fetch!(attrs, :ast_role),
        owner_phase: Map.fetch!(attrs, :owner_phase),
        remediation: Map.fetch!(attrs, :remediation)
      })
    end)
  end

  defp finding(checked_path, attrs) do
    %Finding{
      rule: Map.fetch!(attrs, :rule),
      reason: Map.fetch!(attrs, :reason),
      path: checked_path.path,
      package_path: checked_path.package_path,
      line: Map.fetch!(attrs, :line),
      zone: checked_path.zone,
      owner_phase: Map.fetch!(attrs, :owner_phase),
      severity: Map.get(attrs, :severity, :error),
      token: Map.get(attrs, :token),
      ast_role: Map.fetch!(attrs, :ast_role),
      remediation: Map.fetch!(attrs, :remediation),
      allowlist_entry: nil,
      structural_proof_status: Map.get(attrs, :structural_proof_status)
    }
  end

  defp ignored_finding?(
         %CheckedPath{path: path, zone: :ground_plane},
         line_content,
         "runtime",
         :ground_plane_higher_layer_name
       ) do
    Path.basename(path) == "mix.exs" and String.contains?(line_content, "runtime:")
  end

  defp ignored_finding?(
         %CheckedPath{path: path, zone: :ground_plane},
         line_content,
         "source",
         :ground_plane_higher_layer_name
       ) do
    Path.basename(path) == "mix.exs" and
      (String.contains?(line_content, "source_url:") or
         String.contains?(line_content, "source_ref:"))
  end

  defp ignored_finding?(
         %CheckedPath{path: path},
         line_content,
         token,
         :provider_noun_in_generic_code
       ) do
    mix_metadata_provider_link?(path, line_content, token) or
      non_provider_linear_backoff_term?(line_content, token)
  end

  defp ignored_finding?(_checked_path, _line_content, _token, _rule), do: false

  defp mix_metadata_provider_link?(path, line_content, token) do
    Path.basename(path) == "mix.exs" and token in ["github.", "/github"] and
      (String.contains?(line_content, "source_url:") or
         String.contains?(line_content, "homepage_url:") or
         String.contains?(line_content, "https://github.com/"))
  end

  defp non_provider_linear_backoff_term?(line_content, "linear_") do
    String.contains?(line_content, "linear_step_ms")
  end

  defp non_provider_linear_backoff_term?(_line_content, _token), do: false

  defp appkit_generic_facade?(%CheckedPath{path: path, repo: "app_kit"}, content) do
    (String.ends_with?(path, "/core/runtime_gateway/lib/app_kit/runtime_gateway.ex") or
       String.ends_with?(path, "/core/app_kit_core/lib/app_kit/generic_surfaces.ex")) and
      String.contains?(content, "GenericSurfaceSupport.dispatch") and
      String.contains?(content, "@backend_key")
  end

  defp appkit_generic_facade?(_checked_path, _content), do: false

  defp appkit_backend_facade?(%CheckedPath{path: path, repo: "app_kit"}, content) do
    String.ends_with?(path, "/core/work_surface/lib/app_kit/source_surface.ex") and
      String.contains?(content, "BackendConfig.resolve") and
      String.contains?(content, "backend(opts)")
  end

  defp appkit_backend_facade?(_checked_path, _content), do: false

  defp unbounded_ref_chasing_tokens do
    [
      "fetch_binding(",
      "fetch_manifest(",
      "fetch_credential(",
      "fetch_lane(",
      "load_binding(",
      "load_manifest(",
      "load_credential(",
      "load_lane("
    ]
  end

  defp count_zones(checked_paths) do
    Enum.reduce(checked_paths, %{}, fn checked_path, counts ->
      Map.update(counts, checked_path.zone, 1, &(&1 + 1))
    end)
  end

  defp status(_mode, []), do: :pass
  defp status(:baseline, [_ | _]), do: :baseline_findings
  defp status(:hard_gate, [_ | _]), do: :open_defect

  defp owner_phase(%CheckedPath{repo: "app_kit"}), do: "Phase 3 or Phase 7-10"
  defp owner_phase(%CheckedPath{repo: "mezzanine"}), do: "Phase 7-10"
  defp owner_phase(%CheckedPath{repo: "citadel"}), do: "Phase 4B or Phase 6A"
  defp owner_phase(%CheckedPath{repo: "ground_plane"}), do: "Phase 1"
  defp owner_phase(_checked_path), do: "Phase 6A"

  defp remote_boundary(true) do
    %{
      status: :required,
      requirement:
        "Remote Mezzanine/Jido deployment must prove one governed invocation envelope with bounded call count."
    }
  end

  defp remote_boundary(false) do
    %{
      status: :not_required,
      assumption: :mezzanine_jido_co_located_for_this_pass
    }
  end

  defp meta_line(meta), do: Keyword.get(meta, :line, 0)
end
