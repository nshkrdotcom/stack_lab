defmodule StackLab.GapClosureNegativeFixtures do
  @moduledoc """
  Negative-control fixture registry for the generic stack gap-closure pass.

  These fixtures are data. Later scanner phases consume them as hostile inputs
  and prove that the corresponding bypasses fail closed.
  """

  @type fixture :: %{
          required(:id) => atom(),
          required(:owner_phase) => String.t(),
          required(:claim) => String.t(),
          required(:expected_failure) => atom(),
          required(:path_hint) => String.t(),
          required(:source) => String.t()
        }

  @fixtures [
    %{
      id: :unsafe_dynamic_atom_construction,
      owner_phase: "Phase 2",
      claim: "Runtime product/provider/config input must not create atoms.",
      expected_failure: :unsafe_dynamic_atom_constructor,
      path_hint: "extravaganza/apps/extravaganza_core/lib/extravaganza/headless_json.ex",
      source: """
      defmodule Fixture.UnsafeDynamicAtom do
        def fetch(map, key), do: Map.get(map, String.to_atom(key))
      end
      """
    },
    %{
      id: :generic_raw_credential_ingress,
      owner_phase: "Phase 5",
      claim: "Generic public DTOs must reject raw provider credentials.",
      expected_failure: :raw_credential_in_generic_boundary,
      path_hint: "app_kit/core/app_kit_core/lib/app_kit/runtime_gateway/request.ex",
      source: """
      defmodule AppKit.RuntimeGateway.Request do
        defstruct [:operation_role_ref, :linear_api_key, :api_key]
      end
      """
    },
    %{
      id: :nested_concrete_binding_injection,
      owner_phase: "Phase 4",
      claim: "Product callers must not inject concrete provider binding maps above Mezzanine.",
      expected_failure: :nested_concrete_binding_above_resolution,
      path_hint:
        "app_kit/bridges/mezzanine_bridge/lib/mezzanine/app_kit_bridge/source_service.ex",
      source: """
      defmodule Mezzanine.AppKitBridge.SourceService do
        def request(role_ref) do
          %{role_ref: role_ref, binding: %{provider: "linear", operation_id: "linear.issues.list"}}
        end
      end
      """
    },
    %{
      id: :provider_fallback_default_in_bridge_root,
      owner_phase: "Phase 4",
      claim: "Generic bridge roots must not select provider adapters by default.",
      expected_failure: :provider_fallback_default,
      path_hint:
        "mezzanine/bridges/integration_bridge/lib/mezzanine/integration_bridge/source_dispatcher.ex",
      source: """
      defmodule Mezzanine.IntegrationBridge.SourceDispatcher do
        def adapter(nil), do: Mezzanine.IntegrationBridge.ProviderAdapters.Linear.SourceDispatcher
      end
      """
    },
    %{
      id: :unclassified_provider_public_vocabulary,
      owner_phase: "Phase 4",
      claim: "Provider-account vocabulary in public DTOs must be classified or renamed.",
      expected_failure: :unclassified_provider_public_vocabulary,
      path_hint: "app_kit/core/headless_surface/lib/app_kit/headless_surface/contract.ex",
      source: """
      defmodule AppKit.HeadlessSurface.Contract do
        defstruct [:provider_account_ref, :provider_pool_ref, :reassign_provider]
      end
      """
    },
    %{
      id: :duplicated_provider_family_list,
      owner_phase: "Phase 4",
      claim: "Jido must own canonical provider-adapter classification.",
      expected_failure: :duplicated_provider_family_list,
      path_hint: "citadel/core/connector_binding/lib/citadel/connector_binding.ex",
      source: """
      defmodule Citadel.ConnectorBinding do
        @provider_families ["codex", "github", "linear"]
        def provider_families, do: @provider_families
      end
      """
    },
    %{
      id: :ambiguous_adapter_class,
      owner_phase: "Phase 4",
      claim: "Ambiguous adapter classes must be formalized or removed.",
      expected_failure: :ambiguous_adapter_class,
      path_hint:
        "jido_integration/core/provider_feature_matrix/lib/jido/integration/v2/provider_feature_matrix.ex",
      source: """
      defmodule Jido.Integration.V2.ProviderFeatureMatrix do
        def row, do: %{adapter_class: :shimmed}
      end
      """
    },
    %{
      id: :unbundled_generic_dispatch_entrypoint,
      owner_phase: "Phase 3",
      claim: "Every generic dispatch entrypoint needs a structural proof bundle.",
      expected_failure: :missing_structural_proof_bundle,
      path_hint:
        "mezzanine/core/workflow_runtime/lib/mezzanine/workflow_runtime/generic_runtime.ex",
      source: """
      defmodule Mezzanine.WorkflowRuntime.GenericRuntime do
        def invoke_runtime(role_ref, attrs), do: {:ok, {role_ref, attrs}}
      end
      """
    },
    %{
      id: :nonserializable_boundary_payload,
      owner_phase: "Phase 6",
      claim: "Cross-plane boundary payloads cannot carry local process state.",
      expected_failure: :nonserializable_boundary_payload,
      path_hint: "ground_plane/core/ground_plane_contracts/lib/ground_plane/boundary/envelope.ex",
      source: """
      defmodule GroundPlane.Boundary.Envelope do
        def payload, do: %{pid: self(), local_ref: make_ref()}
      end
      """
    },
    %{
      id: :noncanonical_boundary_hash,
      owner_phase: "Phase 6",
      claim: "Boundary-significant hashes must use the shared canonical codec.",
      expected_failure: :noncanonical_boundary_hash,
      path_hint:
        "execution_plane/runtimes/execution_plane_process/lib/execution_plane/process/tre_rhai.ex",
      source: """
      defmodule ExecutionPlane.Process.TreRhai do
        def digest(input), do: :crypto.hash(:sha256, inspect(input))
      end
      """
    },
    %{
      id: :cross_tenant_store_lookup,
      owner_phase: "Phase 7",
      claim: "Production store lookups must include tenant scope.",
      expected_failure: :missing_tenant_scope,
      path_hint: "outer_brain/core/outer_brain_persistence/lib/outer_brain/persistence/store.ex",
      source: """
      defmodule OuterBrain.Persistence.Store do
        def fetch_current_lease(session_id), do: repo().get_by(SemanticSessionLease, session_id: session_id)
      end
      """
    },
    %{
      id: :governed_aitrace_replay_without_tenant,
      owner_phase: "Phase 7",
      claim: "Governed replay/export must fail closed when tenant metadata is absent.",
      expected_failure: :missing_governed_tenant_ref,
      path_hint: "AITrace/core/replay_engine/lib/ai_trace/replay_engine.ex",
      source: """
      defmodule AITrace.ReplayEngine do
        def source_trace, do: %{trace_id: "trace://missing-tenant", tenant_ref: nil}
      end
      """
    },
    %{
      id: :production_secret_envelope_dev_key,
      owner_phase: "Phase 5",
      claim: "Production secret envelopes cannot use dev-local default keys.",
      expected_failure: :dev_secret_key_in_production_path,
      path_hint: "jido_integration/core/auth/lib/jido/integration/v2/auth/secret_envelope.ex",
      source: """
      defmodule Jido.Integration.V2.Auth.SecretEnvelope do
        def production_key_id, do: "dev-local-default"
      end
      """
    }
  ]

  @spec all() :: [fixture()]
  def all, do: @fixtures

  @spec fetch!(atom()) :: fixture()
  def fetch!(id) when is_atom(id) do
    Enum.find(@fixtures, &(&1.id == id)) ||
      raise ArgumentError, "unknown gap-closure negative fixture #{id}"
  end
end
