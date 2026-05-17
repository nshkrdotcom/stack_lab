defmodule StackLab.StructuralGateScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.StructuralGateScanner

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

  test "passes complete generic dispatch proof bundle", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("mezzanine")
      |> Path.join("core/source_engine/lib/mezzanine/source_engine/generic_dispatch.ex")

    write_file(path, """
    defmodule Mezzanine.SourceEngine.GenericDispatch do
      def publish_source(role_ref, attrs) do
        BindingResolver.resolve_binding(role_ref)
        resolved_operation_plan = %ResolvedOperationPlan{operation_plan: attrs}
        Citadel.authorize(resolved_operation_plan)
        operation_descriptor = Manifest.operation_descriptor(resolved_operation_plan)
        envelope = %GovernedInvocationEnvelope{operation_descriptor: operation_descriptor}
        receipt = %OperationReceipt{dispatch_envelope: envelope}
        LineageEventOutbox.events_for_projection([receipt], attrs, lineage_event: true)
        ReceiptReducer.reduce([receipt], production_reducer: true)
      end
    end
    """)

    assert {:ok, receipt} = StructuralGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :pass
    assert [%{operation_name: :publish_source, status: :passed}] = receipt.proof_bundles
  end

  test "fails incomplete generic dispatch proof bundle", %{roots: roots} do
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
    assert [%{operation_name: :invoke_runtime, status: :incomplete}] = receipt.proof_bundles
    assert Enum.any?(receipt.findings, &(&1.rule == :generic_dispatch_proof_incomplete))
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
