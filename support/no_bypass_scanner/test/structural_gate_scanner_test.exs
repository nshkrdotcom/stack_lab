defmodule StackLab.StructuralGateScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.StructuralGateScanner
  alias StackLab.GapClosureNegativeFixtures
  alias StackLab.StructuralGate.ProofBundleRegistry
  alias StackLab.StructuralGate.TargetRoots

  setup do
    root = Path.join(System.tmp_dir!(), "stack_lab_structural_gate_scanner_test")
    File.rm_rf!(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf!(root) end)

    roots =
      StructuralGateScanner.target_roots()
      |> Map.keys()
      |> Enum.map(fn repo -> {repo, Path.join(root, repo)} end)
      |> Map.new()

    Enum.each(roots, fn {_repo, path} -> File.mkdir_p!(path) end)

    %{root: root, roots: roots}
  end

  test "reports exact target scope and classifies allowed zones", %{roots: roots} do
    app_path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/app_kit_core/lib/app_kit/sources.ex")

    product_path =
      roots
      |> Map.fetch!("extravaganza")
      |> Path.join("apps/extravaganza_core/lib/extravaganza/live_linear.ex")

    connector_path =
      roots
      |> Map.fetch!("jido_integration")
      |> Path.join("connectors/github/lib/jido/connectors/github.ex")

    write_file(app_path, """
    defmodule AppKit.Sources do
      def list_sources(context), do: {:ok, context}
    end
    """)

    write_file(product_path, """
    defmodule Extravaganza.LiveLinear do
      def title, do: "Linear product command"
    end
    """)

    write_file(connector_path, """
    defmodule Jido.Connectors.GitHub do
      def provider, do: :github
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan(Map.values(roots), target_roots: roots)

    assert receipt.status == :pass
    assert receipt.target_scope_status == :exact_target_roots
    assert receipt.zones.generic == 1
    assert receipt.zones.product == 1
    assert receipt.zones.connector == 1
  end

  test "loads target roots from manifest data", %{root: root} do
    manifest_path = Path.join(root, "gn-ten.yml")

    File.write!(manifest_path, """
    repos:
      - name: app_kit
        path: #{Path.join(root, "app_kit")}
      - name: mezzanine
        path: #{Path.join(root, "mezzanine")}
    """)

    assert {:ok, roots} = TargetRoots.from_manifest(manifest_path)
    assert roots["app_kit"] == Path.join(root, "app_kit")
    assert roots["mezzanine"] == Path.join(root, "mezzanine")
  end

  test "reports custom target root scope and missing path diagnostics", %{root: root} do
    repo_root = Path.join(root, "custom_app")
    File.mkdir_p!(repo_root)
    missing_path = Path.join(repo_root, "missing.ex")

    assert {:ok, receipt} =
             StructuralGateScanner.scan([missing_path],
               target_roots: %{"custom_app" => repo_root}
             )

    assert receipt.target_scope_status == :custom_target_roots
    assert [%{path: ^missing_path, reason: :missing_path}] = receipt.skipped_paths
  end

  test "fails provider noun leakage in generic source", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("mezzanine")
      |> Path.join("core/source_engine/lib/mezzanine/source_engine/generic_source.ex")

    write_file(path, """
    defmodule Mezzanine.SourceEngine.GenericSource do
      def vendor, do: "Linear"
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect

    assert Enum.any?(receipt.findings, &(&1.rule == :provider_noun_in_generic_code))
  end

  test "fails AppKit provider public names, concrete binding args, and DTO fields", %{
    roots: roots
  } do
    path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/app_kit_core/lib/app_kit/runtime_surface.ex")

    write_file(path, """
    defmodule AppKit.RuntimeSurface do
      @enforce_keys [:github_pr_number]
      defstruct [:github_pr_number]

      def fetch_github_pr_evidence(context, github_binding_ref) do
        {context, github_binding_ref}
      end
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect
    assert Enum.any?(receipt.findings, &(&1.rule == :provider_named_app_kit_public_api))
    assert Enum.any?(receipt.findings, &(&1.rule == :concrete_binding_ref_at_appkit_boundary))
    assert Enum.any?(receipt.findings, &(&1.rule == :provider_shaped_dto_field))
  end

  test "fails product direct imports and calls into lower owner modules", %{roots: roots} do
    product_path =
      roots
      |> Map.fetch!("extravaganza")
      |> Path.join("apps/extravaganza_core/lib/extravaganza/product_bypass.ex")

    allowed_pack_path =
      roots
      |> Map.fetch!("extravaganza")
      |> Path.join("apps/extravaganza_core/lib/extravaganza/pack_authoring.ex")

    write_file(product_path, """
    defmodule Extravaganza.ProductBypass do
      alias Citadel.AuthorityContract
      import Jido.Integration.V2

      def run(attrs) do
        Mezzanine.WorkflowRuntime.start(attrs)
        AITrace.Event.new("bypass")
        AuthorityContract
      end
    end
    """)

    write_file(allowed_pack_path, """
    defmodule Extravaganza.PackAuthoring do
      alias Mezzanine.Pack

      def pack(attrs), do: Pack.new(attrs)
    end
    """)

    assert {:ok, receipt} =
             StructuralGateScanner.scan([product_path, allowed_pack_path], target_roots: roots)

    assert receipt.status == :open_defect

    product_findings = Enum.filter(receipt.findings, &(&1.path == product_path))

    assert Enum.count(product_findings, &(&1.rule == :direct_lower_owner_import_in_product)) >= 2
    assert Enum.any?(product_findings, &(&1.token == "Mezzanine.WorkflowRuntime"))
    assert Enum.any?(product_findings, &(&1.token == "AITrace.Event"))

    refute Enum.any?(receipt.findings, &(&1.path == allowed_pack_path))
  end

  test "passes registered generic dispatch proof bundle", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/runtime_gateway/lib/app_kit/runtime_gateway.ex")

    write_file(path, """
    defmodule AppKit.RuntimeGateway do
      @backend_key :generic_backend

      def invoke_runtime_operation(context, runtime_role_ref, operation_role_ref, request, opts \\\\ []) do
        GenericSurfaceSupport.dispatch(opts, @backend_key, :invoke_runtime_operation, [
          context,
          runtime_role_ref,
          operation_role_ref,
          request
        ])
      end
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :pass

    assert [
             %{
               entrypoint_id: :appkit_runtime_gateway_invoke_runtime_operation,
               entrypoint_kind: :runtime,
               operation_name: :invoke_runtime_operation,
               operation_arity: 5,
               status: :passed
             }
           ] = receipt.proof_bundles
  end

  test "fails generic dispatch entrypoint without registered bundle", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("mezzanine")
      |> Path.join("core/workflow_runtime/lib/mezzanine/workflow_runtime/generic_runtime.ex")

    write_file(path, """
    defmodule Mezzanine.WorkflowRuntime.GenericRuntime do
      def invoke_runtime(role_ref, attrs), do: {:ok, {role_ref, attrs}}
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect
    assert receipt.proof_bundles == []
    assert Enum.any?(receipt.findings, &(&1.rule == :generic_dispatch_entrypoint_unregistered))
  end

  test "fails registered proof bundle with missing dispatch proof", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/runtime_gateway/lib/app_kit/runtime_gateway.ex")

    write_file(path, """
    defmodule AppKit.RuntimeGateway do
      def invoke_runtime_operation(context, runtime_role_ref, operation_role_ref, request, opts \\\\ []) do
        {context, runtime_role_ref, operation_role_ref, request, opts}
      end
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect

    assert [
             %{
               entrypoint_id: :appkit_runtime_gateway_invoke_runtime_operation,
               operation_name: :invoke_runtime_operation,
               status: :incomplete,
               missing_checks: missing_checks
             }
           ] = receipt.proof_bundles

    assert :generic_surface_dispatch in missing_checks
    assert Enum.any?(receipt.findings, &(&1.rule == :generic_dispatch_proof_incomplete))
  end

  test "proof-bundle registry rejects missing paired tests" do
    root = Path.join(System.tmp_dir!(), "stack_lab_missing_pair_test")
    File.rm_rf!(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf!(root) end)

    assert {:error, errors} = ProofBundleRegistry.validate_entries(repo_root: root)
    assert Enum.any?(errors, &(&1.error == :missing_paired_test))
  end

  test "phase 3 negative fixtures are registered" do
    expected = [
      :unbundled_generic_dispatch_entrypoint,
      :proof_bundle_without_paired_test,
      :provider_branch_under_generic_dispatch,
      :generic_dispatch_missing_authority,
      :generic_dispatch_missing_manifest_lookup,
      :generic_dispatch_receipt_not_emitted
    ]

    registered = GapClosureNegativeFixtures.all() |> Enum.map(& &1.id)

    assert Enum.all?(expected, &(&1 in registered))
  end

  test "fails provider module reference in Mezzanine bridge root but allows adapter zone", %{
    roots: roots
  } do
    bridge_path =
      roots
      |> Map.fetch!("mezzanine")
      |> Path.join("bridges/integration_bridge/lib/mezzanine/integration_bridge.ex")

    adapter_path =
      roots
      |> Map.fetch!("mezzanine")
      |> Path.join("bridges/integration_bridge/provider_adapters/linear/lib/adapter.ex")

    write_file(bridge_path, """
    defmodule Mezzanine.IntegrationBridge do
      alias Mezzanine.IntegrationBridge.LinearSourceDispatcher
    end
    """)

    write_file(adapter_path, """
    defmodule Mezzanine.IntegrationBridge.ProviderAdapters.Linear.Adapter do
      alias Mezzanine.IntegrationBridge.LinearSourceDispatcher
    end
    """)

    assert {:ok, receipt} =
             StructuralGateScanner.scan([bridge_path, adapter_path], target_roots: roots)

    assert receipt.status == :open_defect
    assert Enum.any?(receipt.findings, &(&1.rule == :provider_module_in_bridge_root))
    refute Enum.any?(receipt.findings, &(&1.path == adapter_path))
  end

  test "fails provider operation ids in Citadel generic policy", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("citadel")
      |> Path.join("core/policy_packs/lib/citadel/policy_packs.ex")

    write_file(path, """
    defmodule Citadel.PolicyPacks do
      def pack, do: %{operation_id: "github.pull_request.read"}
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect

    assert Enum.any?(
             receipt.findings,
             &(&1.rule == :provider_operation_in_citadel_generic_policy)
           )
  end

  test "fails phase 4 provider classification bypasses", %{roots: roots} do
    unclassified_path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/app_kit_core/lib/app_kit/unclassified_provider_dto.ex")

    duplicated_family_path =
      roots
      |> Map.fetch!("citadel")
      |> Path.join("core/connector_binding/lib/citadel/connector_binding.ex")

    ambiguous_adapter_path =
      roots
      |> Map.fetch!("jido_integration")
      |> Path.join(
        "core/provider_feature_matrix/lib/jido/integration/v2/provider_feature_matrix.ex"
      )

    write_file(unclassified_path, """
    defmodule AppKit.UnclassifiedProviderDto do
      defstruct [:provider_account_ref, :provider_pool_ref, :reassign_provider]
    end
    """)

    write_file(duplicated_family_path, """
    defmodule Citadel.ConnectorBinding do
      @provider_families ["codex", "github", "linear"]
      def provider_families, do: @provider_families
    end
    """)

    write_file(ambiguous_adapter_path, """
    defmodule Jido.Integration.V2.ProviderFeatureMatrix do
      def placements, do: [:common, :shimmed]
    end
    """)

    assert {:ok, receipt} =
             StructuralGateScanner.scan(
               [unclassified_path, duplicated_family_path, ambiguous_adapter_path],
               target_roots: roots
             )

    assert receipt.status == :open_defect
    assert Enum.any?(receipt.findings, &(&1.rule == :unclassified_provider_public_vocabulary))
    assert Enum.any?(receipt.findings, &(&1.rule == :duplicated_provider_family_list))
    assert Enum.any?(receipt.findings, &(&1.rule == :ambiguous_adapter_class))
  end

  test "fails raw credential fields in generic boundary DTOs", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/runtime_gateway/lib/app_kit/runtime_gateway/request.ex")

    write_file(path, """
    defmodule AppKit.RuntimeGateway.Request do
      defstruct [:operation_role_ref, :credential_material, :api_key]
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect

    assert Enum.any?(receipt.findings, &(&1.rule == :raw_credential_in_generic_boundary))
  end

  test "allows classified provider public vocabulary in authority and scheduling owners", %{
    roots: roots
  } do
    authority_path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/authority_projections/lib/app_kit/authority_projections.ex")

    scheduling_path =
      roots
      |> Map.fetch!("mezzanine")
      |> Path.join("core/coordination_engine/lib/mezzanine/coordination_engine/run.ex")

    write_file(authority_path, """
    defmodule AppKit.AuthorityProjections do
      defstruct [:provider_account_ref, :provider_account_status]
    end
    """)

    write_file(scheduling_path, """
    defmodule Mezzanine.CoordinationEngine.Run do
      defstruct [:provider_pool_ref]
    end
    """)

    assert {:ok, receipt} =
             StructuralGateScanner.scan([authority_path, scheduling_path], target_roots: roots)

    refute Enum.any?(
             receipt.findings,
             &(&1.rule == :unclassified_provider_public_vocabulary)
           )
  end

  test "fails lane branching in AppKit or Mezzanine generic code", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/runtime_gateway/lib/app_kit/runtime_gateway/router.ex")

    write_file(path, """
    defmodule AppKit.RuntimeGateway.Router do
      def route(lane) do
        case "mezzanine.hazmat" do
          ^lane -> :hazmat
          _ -> :default
        end
      end
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect
    assert Enum.any?(receipt.findings, &(&1.rule == :lane_branch_in_generic_code))
  end

  test "allows provider vocabulary in Jido connector zones", %{roots: roots} do
    connector_path =
      roots
      |> Map.fetch!("jido_integration")
      |> Path.join("connectors/github/lib/jido/integration/v2/connectors/git_hub.ex")

    write_file(connector_path, """
    defmodule Jido.Integration.V2.Connectors.GitHub do
      @provider_dispatch %{github: GitHubRuntime, linear: LinearRuntime}
      def provider, do: :github
      def dispatch(provider), do: Map.fetch!(@provider_dispatch, provider)
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([connector_path], target_roots: roots)

    refute Enum.any?(
             receipt.findings,
             &(&1.rule == :closed_provider_dispatch_map_in_core)
           )

    refute Enum.any?(
             receipt.findings,
             &(&1.rule == :provider_noun_in_generic_code)
           )
  end

  test "fails provider-keyed dispatch maps in Jido core", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("jido_integration")
      |> Path.join(
        "core/runtime_router/lib/jido/integration/v2/runtime_router/provider_dispatch.ex"
      )

    write_file(path, """
    defmodule Jido.Integration.V2.RuntimeRouter.ProviderDispatch do
      @provider_dispatch %{github: GitHubRuntime, linear: LinearRuntime}
      def dispatch(provider), do: Map.fetch!(@provider_dispatch, provider)
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect
    assert Enum.any?(receipt.findings, &(&1.rule == :closed_provider_dispatch_map_in_core))
  end

  test "fails provider branch dispatch in Jido core", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("jido_integration")
      |> Path.join(
        "core/runtime_router/lib/jido/integration/v2/runtime_router/provider_branch.ex"
      )

    write_file(path, """
    defmodule Jido.Integration.V2.RuntimeRouter.ProviderBranch do
      def dispatch(provider) do
        case provider do
          :github -> GitHubRuntime
          :linear -> LinearRuntime
          _ -> GenericRuntime
        end
      end
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect
    assert Enum.any?(receipt.findings, &(&1.rule == :closed_provider_dispatch_branch_in_core))
  end

  test "allows canonical Jido provider vocabulary data owners", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("jido_integration")
      |> Path.join(
        "core/provider_feature_matrix/lib/jido/integration/v2/provider_feature_matrix.ex"
      )

    write_file(path, """
    defmodule Jido.Integration.V2.ProviderFeatureMatrix do
      @provider_rows %{github: %{family: "http"}, linear: %{family: "graphql"}}
      def rows, do: @provider_rows
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)

    refute Enum.any?(
             receipt.findings,
             &(&1.rule == :closed_provider_dispatch_map_in_core)
           )
  end

  test "rejects blanket allowlists for protected generic paths", %{roots: roots} do
    protected_path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/**")

    assert {:error, {:blanket_allowlist_rejected, ^protected_path}} =
             StructuralGateScanner.scan([],
               target_roots: roots,
               allowlist: [
                 %{
                   token: :any,
                   path: protected_path,
                   reason: "too broad",
                   owner: "phase-6a",
                   expires: "never",
                   permanent_zone: false
                 }
               ]
             )
  end

  defp write_file(path, content) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
  end
end
