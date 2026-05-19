defmodule StackLab.FoundationGateScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.FoundationGateScanner

  setup do
    root = Path.join(System.tmp_dir!(), "stack_lab_foundation_gate_scanner_test")
    File.rm_rf!(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf!(root) end)

    roots = %{
      "app_kit" => Path.join(root, "app_kit"),
      "ground_plane" => Path.join(root, "ground_plane"),
      "mezzanine" => Path.join(root, "mezzanine"),
      "stack_lab" => Path.join(root, "stack_lab")
    }

    Enum.each(roots, fn {_repo, path} -> File.mkdir_p!(path) end)

    %{root: root, roots: roots}
  end

  test "passes clean foundation source and reports checked zones", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/app_kit_core/lib/app_kit/sources.ex")

    write_file(path, """
    defmodule AppKit.Sources do
      def publish_source(role_ref, attrs), do: {:ok, {role_ref, attrs}}
    end
    """)

    assert {:ok, receipt} = FoundationGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :pass
    assert [%{zone: :foundation_app_kit}] = receipt.checked_paths

    assert receipt.phase_6a_deferred_proofs == [
             :ast_public_api_scan,
             :manifest_dependency_scan,
             :bridge_root_import_call_scan,
             :generic_dispatch_dataflow_proof
           ]
  end

  test "fails provider noun leakage in a foundation zone", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("mezzanine")
      |> Path.join("core/substrate_model/lib/mezzanine/substrate_model/source_binding.ex")

    write_file(path, """
    defmodule Mezzanine.SubstrateModel.SourceBinding do
      def provider, do: "Linear"
    end
    """)

    assert {:ok, receipt} = FoundationGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect

    assert [
             %{
               rule: :provider_noun_in_foundation,
               token: "Linear",
               owner_phase: "Phase 2 or Phase 4"
             }
           ] = receipt.findings
  end

  test "fails provider-shaped AppKit public APIs and fields", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/app_kit_core/lib/app_kit/runtime_surface.ex")

    field = "github" <> "_pr_number"

    write_file(path, """
    defmodule AppKit.RuntimeSurface do
      @enforce_keys [#{inspect(field)}]
      def fetch_github_pr_evidence(context, #{field}, opts), do: {context, #{field}, opts}
    end
    """)

    assert {:ok, receipt} = FoundationGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect
    assert Enum.any?(receipt.findings, &(&1.rule == :provider_named_app_kit_public_api))
    assert Enum.any?(receipt.findings, &(&1.rule == :provider_shaped_field))
  end

  test "fails provider-shaped product implementation APIs while allowing product command names",
       %{
         root: root
       } do
    roots = %{"extravaganza" => Path.join(root, "extravaganza")}

    path =
      Path.join(
        roots["extravaganza"],
        "apps/extravaganza_core/lib/extravaganza/headless_surface.ex"
      )

    write_file(path, """
    defmodule Extravaganza.HeadlessSurface do
      @operation :live_linear_source

      def live_linear_source_command(attrs), do: {:ok, attrs}
      def publish_linear_source(attrs, opts), do: {attrs, opts}
    end
    """)

    assert {:ok, receipt} = FoundationGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect

    assert [
             %{
               rule: :provider_named_product_implementation_api,
               token: "publish_linear_source",
               owner_phase: "Extravaganza Cutover Phase 2"
             }
           ] = receipt.findings
  end

  test "fails regular-expression tokens in project code", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("stack_lab")
      |> Path.join("support/no_bypass_scanner/lib/stack_lab/example.ex")

    module_token = "Re" <> "gex"

    write_file(path, """
    defmodule StackLab.Example do
      def compile(value), do: #{module_token}.compile!(value)
    end
    """)

    assert {:ok, receipt} = FoundationGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect

    assert [%{rule: :regular_expression_usage, token: ^module_token, owner_phase: "Phase 6B"}] =
             receipt.findings
  end

  test "fails higher-layer GroundPlane names in foundation paths and modules", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("ground_plane")
      |> Path.join("core/ai_run_fencing/lib/ground_plane/ai_run_fencing.ex")

    write_file(path, """
    defmodule GroundPlane.AIRunFencing do
      def authorize(attrs), do: attrs
    end
    """)

    assert {:ok, receipt} = FoundationGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect
    assert Enum.any?(receipt.findings, &(&1.rule == :ground_plane_higher_layer_name))
    assert Enum.any?(receipt.findings, &(&1.line == 0))
    assert Enum.all?(receipt.findings, &(&1.owner_phase == "Phase 1"))
  end

  test "does not treat higher-layer terms as substrings inside lower primitive words", %{
    roots: roots
  } do
    path =
      roots
      |> Map.fetch!("ground_plane")
      |> Path.join("core/ground_plane_contracts/lib/ground_plane/contracts/resource_ref.ex")

    write_file(path, """
    defmodule GroundPlane.Contracts.ResourceRef do
      def new(resource_ref), do: {:ok, resource_ref}
    end
    """)

    assert {:ok, receipt} = FoundationGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :pass
  end

  test "does not treat Mix dependency metadata as GroundPlane runtime/source ownership", %{
    roots: roots
  } do
    path =
      roots
      |> Map.fetch!("ground_plane")
      |> Path.join("core/ground_plane_contracts/mix.exs")

    write_file(path, """
    defmodule GroundPlane.Contracts.MixProject do
      use Mix.Project

      def project do
        [
          deps: deps(),
          docs: [source_ref: "main", source_url: "https://example.test"]
        ]
      end

      defp deps do
        [
          {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
        ]
      end
    end
    """)

    assert {:ok, receipt} = FoundationGateScanner.scan([path], target_roots: roots)
    assert receipt.status == :pass
  end

  test "rejects target scope drift", %{root: root, roots: roots} do
    outside_path = Path.join(root, "outside_repo/lib/example.ex")
    write_file(outside_path, "defmodule OutsideRepo.Example, do: nil\n")

    assert {:error, {:outside_target_scope, [^outside_path]}} =
             FoundationGateScanner.scan([outside_path], target_roots: roots)
  end

  test "reports excluded dependency and build paths without scanning them", %{roots: roots} do
    repo_root = Map.fetch!(roots, "app_kit")
    deps_file = Path.join(repo_root, "deps/provider_dep/lib/github_client.ex")
    build_file = Path.join(repo_root, "_build/test/lib/generated.ex")
    dist_file = Path.join(repo_root, "dist/hex/app_kit/components/core/generated.ex")
    good_file = Path.join(repo_root, "core/app_kit_core/lib/app_kit/sources.ex")

    write_file(deps_file, "defmodule GithubClient, do: nil\n")
    write_file(build_file, "defmodule Generated, do: nil\n")
    write_file(dist_file, "defmodule GeneratedDist, do: nil\n")
    write_file(good_file, "defmodule AppKit.Sources, do: nil\n")

    assert {:ok, receipt} = FoundationGateScanner.scan([repo_root], target_roots: roots)
    assert receipt.status == :pass
    assert Enum.any?(receipt.skipped_paths, &(&1.path == Path.join(repo_root, "deps")))
    assert Enum.any?(receipt.skipped_paths, &(&1.path == Path.join(repo_root, "_build")))
    assert Enum.any?(receipt.skipped_paths, &(&1.path == Path.join(repo_root, "dist")))
    assert Enum.map(receipt.checked_paths, & &1.path) == [good_file]
  end

  test "baseline mode records findings without hard-gate failure status", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/app_kit_core/lib/app_kit/runtime_surface.ex")

    write_file(path, """
    defmodule AppKit.RuntimeSurface do
      def cleanup_github_pr_branch(context, ref, opts), do: {context, ref, opts}
    end
    """)

    assert {:ok, receipt} =
             FoundationGateScanner.scan([path], target_roots: roots, mode: :baseline)

    assert receipt.status == :baseline_findings
    assert Enum.any?(receipt.findings, &(&1.rule == :provider_named_app_kit_public_api))
    assert Enum.any?(receipt.findings, &(&1.rule == :provider_noun_in_foundation))
  end

  defp write_file(path, content) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
  end
end
