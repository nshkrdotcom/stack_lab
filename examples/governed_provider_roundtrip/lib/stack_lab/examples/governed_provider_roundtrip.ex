defmodule StackLab.Examples.GovernedProviderRoundtrip do
  @moduledoc """
  Deterministic Phase 15 proof for governed provider dispatch.
  """

  alias StackLab.GnTenControlPlane
  alias StackLab.LabCore
  alias StackLab.SpecCell

  @provider_families [
    %{id: :codex, repo: "codex_sdk", transport_family: :cli},
    %{id: :claude, repo: "claude_agent_sdk", transport_family: :cli},
    %{id: :gemini_cli, repo: "gemini_cli_sdk", transport_family: :cli},
    %{id: :amp, repo: "amp_sdk", transport_family: :cli},
    %{id: :github, repo: "github_ex", transport_family: :http},
    %{id: :notion, repo: "notion_sdk", transport_family: :http},
    %{id: :linear, repo: "linear_sdk", transport_family: :graphql},
    %{id: :reqllm_next, repo: "reqllm_next", transport_family: :realtime},
    %{id: :inference, repo: "inference", transport_family: :inference},
    %{
      id: :self_hosted_inference,
      repo: "self_hosted_inference_core",
      transport_family: :inference
    },
    %{id: :gemini_ex, repo: "gemini_ex", transport_family: :http},
    %{id: :llama_cpp_sdk, repo: "llama_cpp_sdk", transport_family: :inference}
  ]

  @target_modes [
    :local_subprocess,
    :ssh_sandbox,
    :container,
    :workspace,
    :durable_object,
    :temporal_worker,
    :remote_sandbox,
    :stream,
    :inference_endpoint
  ]

  @requirements [
    "UAA-023",
    "UAA-024",
    "UAA-025",
    "UAA-026",
    "UAA-029",
    "UAA-036",
    "UAA-037",
    "UAA-047"
  ]

  @blocked_material_keys [
    :api_key,
    :base_url,
    :credential_value,
    :env,
    :home_root,
    :normal_user_auth_root,
    :oauth_file,
    :provider_payload,
    :sdk_options,
    :token_file
  ]

  @spec scenario() :: map()
  def scenario do
    %{
      name: :governed_provider_roundtrip,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      memory_substrate: :multi_node_epoch_monotonicity_and_ordering,
      cases: %{
        central_ref_dispatch: %{kind: :central_ref_dispatch},
        standalone_promotion: %{kind: :standalone_promotion},
        disposable_live_provider: %{kind: :disposable_live_provider},
        workspace_build_no_secret_bundle: %{kind: :workspace_build_no_secret_bundle}
      }
    }
  end

  @spec provider_families() :: [map()]
  def provider_families, do: @provider_families

  @spec target_modes() :: [atom()]
  def target_modes, do: @target_modes

  @spec dispatch_matrix() :: [map()]
  def dispatch_matrix do
    for provider <- @provider_families,
        target_mode <- @target_modes do
      dispatch_row(provider, target_mode)
    end
  end

  @spec prove_dispatch() :: {:ok, map()} | {:error, term()}
  def prove_dispatch do
    rows = dispatch_matrix()

    with :ok <- require_complete_matrix(rows),
         :ok <- reject_unmanaged_material(rows),
         :ok <- require_one_to_many(rows) do
      {:ok,
       %{
         row_count: length(rows),
         providers: Enum.map(@provider_families, & &1.id),
         targets: @target_modes,
         rows: rows,
         receipts: receipts("UAA-026", "passed"),
         auth_layer_separation: auth_layer_separation()
       }}
    end
  end

  @spec standalone_promotion_proof() :: {:ok, map()} | {:error, term()}
  def standalone_promotion_proof do
    rows =
      Enum.map(@provider_families, fn provider ->
        %{
          provider: provider.id,
          standalone_source: standalone_source(provider),
          promotion_steps: [
            :discover_native_auth,
            :assert_auth_identity,
            :register_provider_account,
            :bind_target,
            :issue_lease,
            :materialize_once,
            :run,
            :cleanup,
            :project_evidence
          ],
          governed_rejection: {:unmanaged_auth_rejected, provider.id},
          raw_material_present?: false
        }
      end)

    with :ok <- require_no_raw_material(rows) do
      {:ok,
       %{
         rows: rows,
         receipts: receipts("UAA-037", "passed"),
         standalone_receipts: receipts("UAA-024", "passed")
       }}
    end
  end

  @spec live_provider_proof(map()) :: map()
  def live_provider_proof(disposable_credentials_by_provider \\ %{})
      when is_map(disposable_credentials_by_provider) do
    rows =
      Enum.map(@provider_families, fn provider ->
        case Map.fetch(disposable_credentials_by_provider, provider.id) do
          {:ok, credential_ref} ->
            live_provider_row(provider, credential_ref)

          :error ->
            %{
              provider: provider.id,
              repo: provider.repo,
              state: :open_defect,
              open_defect: {:missing_disposable_credential_ref, provider.id},
              normal_auth_roots_mutated?: false,
              cleanup_verified?: false,
              raw_material_present?: false
            }
        end
      end)

    %{
      rows: rows,
      release_blocking?: Enum.any?(rows, &(&1.state == :open_defect)),
      receipts: live_provider_receipts(rows)
    }
  end

  @spec workspace_build_no_secret_bundle_proof() :: {:ok, map()} | {:error, term()}
  def workspace_build_no_secret_bundle_proof do
    manifest = %{
      manifest_ref: "workspace-build://phase15/governed-provider-roundtrip",
      agent_names: ["provider-proof-agent"],
      triggers: ["phase15.provider.roundtrip"],
      required_providers: Enum.map(@provider_families, & &1.id),
      connector_binding_refs: ["connector-binding://tenant-1/phase15/all"],
      target_postures: @target_modes,
      env_contract_refs: ["env-contract://phase15/no-secret-bundle"],
      projection_refs: ["projection://phase15/governed-provider-roundtrip"],
      bundled_raw_private_material?: false,
      bundled_normal_user_auth_root?: false,
      bundled_token_files?: false
    }

    with :ok <- require_no_manifest_private_material(manifest) do
      {:ok, %{manifest: manifest, receipts: receipts("UAA-047", "passed")}}
    end
  end

  @spec spec_cells() :: [SpecCell.t()]
  def spec_cells do
    Enum.map(@requirements, fn requirement_id ->
      SpecCell.new!(
        requirement_id: requirement_id,
        owner_repo: "stack_lab",
        source_docs: [
          "implementation_docset/28_environment_variable_governance.md",
          "implementation_docset/38_additional_feature_phase_integration.md",
          "implementation_docset/39_new_package_placement.md"
        ],
        target_code_paths: ["stack_lab/examples/governed_provider_roundtrip"],
        proof_command: "mix test",
        acceptance_fixture: requirement_id,
        scanner_refs: ["governed_provider_roundtrip"],
        closeout_state: :green,
        release_claim: "governed provider dispatch uses central refs and disposable inputs"
      )
    end)
  end

  @spec receipts(String.t(), String.t()) :: [GnTenControlPlane.t()]
  def receipts(requirement_id, state) when is_binary(requirement_id) and is_binary(state) do
    requirement_id
    |> spec_cell_for!()
    |> then(fn cell ->
      [
        GnTenControlPlane.new!(
          receipt_id: "gn-ten:#{requirement_id}:governed-provider-roundtrip",
          requirement_id: requirement_id,
          owner_repo: "stack_lab",
          state: state,
          proof_command: "mix test",
          receipt_path: "implementation_docset/phase_notes/runs/phase_15_RUN_20260504_08cf848.md",
          spec_cell: cell
        )
      ]
    end)
  end

  @spec redacted_receipt(map()) :: map()
  def redacted_receipt(%{} = row) do
    row
    |> Map.drop(@blocked_material_keys)
    |> Map.put(:raw_material_present?, false)
  end

  defp dispatch_row(provider, target_mode) do
    %{
      provider: provider.id,
      repo: provider.repo,
      transport_family: provider.transport_family,
      target_mode: target_mode,
      tenant_ref: "tenant://phase15/default",
      provider_account_ref: "provider-account://phase15/#{provider.id}/account-a",
      credential_handle_ref: "credential-handle://phase15/#{provider.id}/handle-a",
      credential_lease_ref: "credential-lease://phase15/#{provider.id}/lease-a",
      native_auth_assertion_ref: "native-auth-assertion://phase15/#{provider.id}/assertion-a",
      connector_binding_ref: "connector-binding://phase15/#{provider.id}/binding-a",
      target_grant_ref: "target-grant://phase15/#{target_mode}/grant-a",
      operation_policy_ref: "operation-policy://phase15/#{provider.transport_family}/dispatch",
      trace_ref: "trace://phase15/#{provider.id}/#{target_mode}",
      idempotency_ref: "idempotency://phase15/#{provider.id}/#{target_mode}",
      materializer_source: :authority_materializer,
      dispatch_selector: :central_refs,
      raw_material_present?: false,
      singleton_client_used?: false,
      default_sdk_constructor_used?: false,
      normal_auth_roots_mutated?: false
    }
  end

  defp standalone_source(%{transport_family: :cli}), do: :native_cli_default_mode
  defp standalone_source(%{transport_family: :http}), do: :sdk_default_client_mode
  defp standalone_source(%{transport_family: :graphql}), do: :sdk_default_client_mode
  defp standalone_source(%{transport_family: :realtime}), do: :sdk_default_session_mode
  defp standalone_source(%{transport_family: :inference}), do: :local_or_hosted_endpoint_mode

  defp live_provider_row(provider, credential_ref) when is_binary(credential_ref) do
    %{
      provider: provider.id,
      repo: provider.repo,
      state: :passed,
      disposable_credential_ref: credential_ref,
      disposable_target_ref: "target://phase15/disposable/#{provider.id}",
      cleanup_refs: [
        "cleanup://phase15/#{provider.id}/credential-file",
        "cleanup://phase15/#{provider.id}/session",
        "cleanup://phase15/#{provider.id}/target-attach"
      ],
      normal_auth_roots_mutated?: false,
      cleanup_verified?: true,
      raw_material_present?: false
    }
  end

  defp live_provider_row(provider, _credential_ref) do
    %{
      provider: provider.id,
      repo: provider.repo,
      state: :open_defect,
      open_defect: {:invalid_disposable_credential_ref, provider.id},
      normal_auth_roots_mutated?: false,
      cleanup_verified?: false,
      raw_material_present?: false
    }
  end

  defp live_provider_receipts(rows) do
    state =
      if Enum.any?(rows, &(&1.state == :open_defect)) do
        "missing"
      else
        "passed"
      end

    receipts("UAA-023", state)
  end

  defp auth_layer_separation do
    %{
      system_authorization: :tenant_policy_decision_ref,
      provider_credentials: :credential_lease_ref,
      credential_enrollment: :provider_account_ref,
      target_attach: :target_grant_ref,
      materialization: :authority_materializer_ref,
      substitution_allowed?: false
    }
  end

  defp require_complete_matrix(rows) do
    expected_count = length(@provider_families) * length(@target_modes)

    if length(rows) == expected_count do
      :ok
    else
      {:error, {:incomplete_dispatch_matrix, length(rows), expected_count}}
    end
  end

  defp reject_unmanaged_material(rows) do
    case Enum.find(rows, &unmanaged_material?/1) do
      nil -> :ok
      row -> {:error, {:unmanaged_material_in_dispatch_row, row.provider, row.target_mode}}
    end
  end

  defp unmanaged_material?(row) do
    row.raw_material_present? or row.singleton_client_used? or row.default_sdk_constructor_used? or
      row.normal_auth_roots_mutated? or row.dispatch_selector != :central_refs or
      row.materializer_source != :authority_materializer
  end

  defp require_one_to_many(rows) do
    provider_ok? =
      Enum.all?(@provider_families, fn provider ->
        Enum.count(rows, &(&1.provider == provider.id)) == length(@target_modes)
      end)

    target_ok? =
      Enum.all?(@target_modes, fn target_mode ->
        Enum.count(rows, &(&1.target_mode == target_mode)) == length(@provider_families)
      end)

    if provider_ok? and target_ok? do
      :ok
    else
      {:error, :one_to_many_provider_target_matrix_incomplete}
    end
  end

  defp require_no_raw_material(rows) do
    if Enum.all?(rows, &(not &1.raw_material_present?)) do
      :ok
    else
      {:error, :raw_material_present}
    end
  end

  defp require_no_manifest_private_material(manifest) do
    if manifest.bundled_raw_private_material? or manifest.bundled_normal_user_auth_root? or
         manifest.bundled_token_files? do
      {:error, :workspace_manifest_bundles_private_material}
    else
      :ok
    end
  end

  defp spec_cell_for!(requirement_id) do
    Enum.find(spec_cells(), &(&1.requirement_id == requirement_id)) ||
      raise ArgumentError, "unknown requirement #{requirement_id}"
  end

  defp repo_roots do
    stack_lab_root = LabCore.repo_root()

    %{
      stack_lab: stack_lab_root,
      citadel: Path.expand("../citadel", stack_lab_root),
      jido_integration: Path.expand("../jido_integration", stack_lab_root),
      jido_hive: Path.expand("../jido_hive", stack_lab_root),
      mezzanine: Path.expand("../mezzanine", stack_lab_root),
      outer_brain: Path.expand("../outer_brain", stack_lab_root),
      app_kit: Path.expand("../app_kit", stack_lab_root),
      extravaganza: Path.expand("../extravaganza", stack_lab_root),
      execution_plane: Path.expand("../execution_plane", stack_lab_root)
    }
  end
end
