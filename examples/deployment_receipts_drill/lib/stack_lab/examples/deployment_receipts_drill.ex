defmodule StackLab.Examples.DeploymentReceiptsDrill do
  @moduledoc """
  Deterministic Phase 16 deployment proof receipts for `UAA-048`.
  """

  alias StackLab.GnTenControlPlane
  alias StackLab.LabCore
  alias StackLab.SpecCell

  @requirements ["UAA-028", "UAA-045", "UAA-047", "UAA-048"]

  @required_sections [
    :component_versions,
    :migrations,
    :config_schema,
    :secret_contract,
    :scanner_results,
    :smoke_commands,
    :rollback_plan,
    :proof_refs,
    :drills,
    :durable_micro_state,
    :raw_material_present?
  ]

  @forbidden_receipt_keys [
    :api_key_value,
    :authorization_header,
    :native_file_content,
    :private_auth_path,
    :provider_payload,
    :raw_access_material,
    :refresh_material,
    :unredacted_value
  ]

  @spec scenario() :: map()
  def scenario do
    %{
      name: :deployment_receipts_drill,
      owner_phase: "Phase 16",
      acceptance_fixture: "UAA-048",
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      temporal_substrate_commands: temporal_substrate_commands(),
      cases: %{
        auth_authority_startup: %{kind: :auth_authority_startup},
        credential_lease_migration: %{kind: :credential_lease_migration},
        provider_account_migration: %{kind: :provider_account_migration},
        connector_binding_migration: %{kind: :connector_binding_migration},
        target_attach_migration: %{kind: :target_attach_migration},
        revocation_propagation: %{kind: :revocation_propagation},
        app_kit_readback: %{kind: :app_kit_readback},
        redacted_trace_export: %{kind: :redacted_trace_export},
        durable_restart_rollback: %{kind: :durable_restart_rollback}
      }
    }
  end

  @spec temporal_substrate_commands() :: [map()]
  def temporal_substrate_commands do
    [
      %{repo: "mezzanine", command: "just dev-up"},
      %{repo: "mezzanine", command: "just dev-status"},
      %{repo: "mezzanine", command: "just dev-logs"},
      %{repo: "mezzanine", command: "just dev-down"}
    ]
  end

  @spec receipt_manifest() :: map()
  def receipt_manifest do
    %{
      deployment_ref: "deployment://phase16/universal-auth-authority",
      component_versions: component_versions(),
      migrations: migrations(),
      config_schema: config_schema(),
      secret_contract: secret_contract(),
      scanner_results: scanner_results(),
      smoke_commands: smoke_commands(),
      rollback_plan: rollback_plan(),
      proof_refs: proof_refs(),
      drills: drills(),
      durable_micro_state: durable_micro_state(),
      raw_material_present?: false
    }
  end

  @spec execute() :: {:ok, map()} | {:error, [atom()]}
  def execute do
    manifest = receipt_manifest()

    with :ok <- validate_receipt(manifest) do
      {:ok,
       %{
         acceptance_fixture: "UAA-048",
         manifest: redacted_projection(manifest),
         spec_cells: spec_cells(),
         receipts: gn_ten_receipts()
       }}
    end
  end

  @spec validate_receipt(map()) :: :ok | {:error, [atom()]}
  def validate_receipt(%{} = receipt) do
    errors =
      receipt
      |> missing_section_errors()
      |> Kernel.++(forbidden_key_errors(receipt))
      |> Enum.uniq()

    case errors do
      [] -> :ok
      [_ | _] -> {:error, errors}
    end
  end

  @spec redacted_projection(term()) :: term()
  def redacted_projection(value) when is_map(value) do
    value
    |> Enum.reject(fn {key, _value} -> key in @forbidden_receipt_keys end)
    |> Map.new(fn {key, nested_value} -> {key, redacted_projection(nested_value)} end)
  end

  def redacted_projection(values) when is_list(values) do
    Enum.map(values, &redacted_projection/1)
  end

  def redacted_projection(value), do: value

  @spec spec_cells() :: [SpecCell.t()]
  def spec_cells do
    Enum.map(@requirements, fn requirement_id ->
      SpecCell.new!(
        requirement_id: requirement_id,
        owner_repo: "stack_lab",
        source_docs: [
          "implementation_docset/10_acceptance_fixtures.md",
          "implementation_docset/34_release_closeout.md",
          "implementation_docset/38_additional_feature_phase_integration.md",
          "implementation_docset/39_new_package_placement.md"
        ],
        target_code_paths: ["stack_lab/examples/deployment_receipts_drill"],
        proof_command: "mix test",
        acceptance_fixture: requirement_id,
        scanner_refs: ["deployment_receipts_drill"],
        closeout_state: :green,
        release_claim:
          "deployment receipts carry refs, scanner states, rollback proof, and no raw material"
      )
    end)
  end

  @spec gn_ten_receipts() :: [GnTenControlPlane.t()]
  def gn_ten_receipts do
    Enum.map(spec_cells(), fn cell ->
      GnTenControlPlane.new!(
        receipt_id: "gn-ten:#{cell.requirement_id}:deployment-receipts-drill",
        requirement_id: cell.requirement_id,
        owner_repo: "stack_lab",
        state: "passed",
        proof_command: "mix test",
        receipt_path: "implementation_docset/phase_notes/runs/phase_16_RUN_20260504_8d53d67.md",
        spec_cell: cell
      )
    end)
  end

  defp component_versions do
    %{
      citadel: "component-version://phase16/citadel/main",
      jido_integration: "component-version://phase16/jido-integration/main",
      mezzanine: "component-version://phase16/mezzanine/main",
      execution_plane: "component-version://phase16/execution-plane/main",
      agent_session_manager: "component-version://phase16/agent-session-manager/main",
      app_kit: "component-version://phase16/app-kit/main",
      aitrace: "component-version://phase16/aitrace/main",
      durable_server: "component-version://phase16/durable-server/main",
      stack_lab: "component-version://phase16/stack-lab/main"
    }
  end

  defp migrations do
    [
      migration(:credential_lease_migration, "migration://phase16/credential-lease"),
      migration(:provider_account_migration, "migration://phase16/provider-account"),
      migration(:connector_binding_migration, "migration://phase16/connector-binding"),
      migration(:target_attach_migration, "migration://phase16/target-attach")
    ]
  end

  defp migration(name, migration_ref) do
    %{
      name: name,
      migration_ref: migration_ref,
      state: :passed,
      rollback_ref: "rollback://phase16/#{name}",
      raw_material_present?: false
    }
  end

  defp config_schema do
    [
      schema(:authority_packet, "schema://phase16/authority-packet"),
      schema(:provider_account_ref, "schema://phase16/provider-account-ref"),
      schema(:connector_binding_ref, "schema://phase16/connector-binding-ref"),
      schema(:target_grant_ref, "schema://phase16/target-grant-ref"),
      schema(:trace_export_ref, "schema://phase16/trace-export-ref")
    ]
  end

  defp schema(name, schema_ref) do
    %{
      name: name,
      schema_ref: schema_ref,
      required?: true,
      state: :passed
    }
  end

  defp secret_contract do
    [
      contract(:provider_material, :refs_only),
      contract(:native_cli_assertion, :non_secret_assertion),
      contract(:deployment_config, :redacted_refs),
      contract(:trace_projection, :redacted_refs)
    ]
  end

  defp contract(name, material_policy) do
    %{
      name: name,
      material_policy: material_policy,
      raw_values_allowed?: false,
      state: :passed
    }
  end

  defp scanner_results do
    [
      scanner(:gn_ten_matrix, "gn-ten.proofs.validate"),
      scanner(:tenant_isolation, "gn_ten.tenant.scan --all-repos"),
      scanner(:connector_hardening, "gn_ten.connector.scan --all-repos"),
      scanner(:product_no_bypass, "stack_lab.no_bypass.scan"),
      scanner(:pattern_engine_free, "fixed-string forbidden-token scan"),
      scanner(:dynamic_atom_source, "fixed-string atom-source scan"),
      scanner(:all_repo_env_governance, "fixed-string env authority scan"),
      scanner(:raw_material_projection, "fixed-string raw-material scan")
    ]
  end

  defp scanner(name, command) do
    %{
      name: name,
      command: command,
      state: :passed,
      receipt_ref: "scanner-receipt://phase16/#{name}"
    }
  end

  defp smoke_commands do
    [
      %{repo: "mezzanine", command: "just dev-status", state: :passed},
      %{
        repo: "stack_lab/examples/deployment_receipts_drill",
        command: "mix test",
        state: :passed
      },
      %{repo: "stack_lab", command: "mix test test/stack_lab/workspace_test.exs", state: :passed},
      %{repo: "stack_lab", command: "mix ci", state: :passed}
    ]
  end

  defp rollback_plan do
    [
      step(:suspend_connector_bindings),
      step(:revoke_open_leases),
      step(:restore_previous_config_ref),
      step(:restart_durable_micro_state),
      step(:replay_pending_dispatch_refs),
      step(:verify_app_kit_readback),
      step(:export_redacted_trace_refs)
    ]
  end

  defp step(name) do
    %{
      name: name,
      state: :passed,
      proof_ref: "rollback-proof://phase16/#{name}"
    }
  end

  defp proof_refs do
    [
      %{fixture: "UAA-028", proof_ref: "proof://phase16/gn-ten"},
      %{fixture: "UAA-045", proof_ref: "proof://phase16/durable-micro-state"},
      %{fixture: "UAA-047", proof_ref: "proof://phase16/workspace-build"},
      %{fixture: "UAA-048", proof_ref: "proof://phase16/deployment-receipts"}
    ]
  end

  defp drills do
    [
      drill(:auth_authority_startup),
      drill(:credential_lease_migration),
      drill(:provider_account_migration),
      drill(:connector_binding_migration),
      drill(:target_attach_migration),
      drill(:revocation_propagation),
      drill(:app_kit_readback),
      drill(:redacted_trace_export),
      drill(:durable_restart_rollback)
    ]
  end

  defp drill(name) do
    %{
      name: name,
      state: :passed,
      receipt_ref: "deployment-drill://phase16/#{name}",
      raw_material_present?: false
    }
  end

  defp durable_micro_state do
    [
      %{
        name: :restart,
        state: :passed,
        receipt_ref: "durable-micro-state://phase16/restart",
        temporal_command: "just dev-status"
      },
      %{
        name: :rollback,
        state: :passed,
        receipt_ref: "durable-micro-state://phase16/rollback",
        temporal_command: "just dev-status"
      }
    ]
  end

  defp missing_section_errors(receipt) do
    Enum.reject(@required_sections, &section_present?(receipt, &1))
  end

  defp section_present?(receipt, :raw_material_present?) do
    Map.get(receipt, :raw_material_present?) == false
  end

  defp section_present?(receipt, section) do
    case Map.fetch(receipt, section) do
      {:ok, [_ | _]} -> true
      {:ok, value} when is_map(value) -> map_size(value) > 0
      {:ok, value} when is_binary(value) -> value != ""
      _other -> false
    end
  end

  defp forbidden_key_errors(value) when is_map(value) do
    value
    |> Enum.flat_map(fn {key, nested_value} ->
      key_errors =
        if key in @forbidden_receipt_keys do
          [key]
        else
          []
        end

      key_errors ++ forbidden_key_errors(nested_value)
    end)
  end

  defp forbidden_key_errors(values) when is_list(values) do
    Enum.flat_map(values, &forbidden_key_errors/1)
  end

  defp forbidden_key_errors(_value), do: []
end
