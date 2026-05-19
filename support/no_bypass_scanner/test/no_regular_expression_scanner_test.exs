defmodule StackLab.NoRegularExpressionScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.NoRegularExpressionScanner

  setup do
    root = Path.join(System.tmp_dir!(), "stack_lab_no_regular_expression_scanner_test")
    File.rm_rf!(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf!(root) end)

    roots =
      NoRegularExpressionScanner.target_roots()
      |> Map.keys()
      |> Enum.map(fn repo -> {repo, Path.join(root, repo)} end)
      |> Map.new()

    Enum.each(roots, fn {_repo, path} -> File.mkdir_p!(path) end)

    %{roots: roots}
  end

  test "passes clean project-owned code and reports target repos", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("app_kit")
      |> Path.join("core/app_kit_core/lib/app_kit/sources.ex")

    write_file(path, """
    defmodule AppKit.Sources do
      def clean(value), do: String.contains?(value, "needle")
    end
    """)

    assert {:ok, receipt} = NoRegularExpressionScanner.scan([path], target_roots: roots)
    assert receipt.status == :pass
    assert receipt.checked_paths == [path]
    assert receipt.target_roots |> Map.keys() |> Enum.sort() == roots |> Map.keys() |> Enum.sort()
  end

  test "fails exact regular-expression tokens in source and tests", %{roots: roots} do
    path =
      roots
      |> Map.fetch!("stack_lab")
      |> Path.join("support/no_bypass_scanner/test/bad_test.exs")

    module_token = "Re" <> "gex"
    literal_token = "~" <> "r"

    write_file(path, """
    defmodule BadTest do
      def compile(value), do: #{module_token}.compile!(value)
      def literal, do: #{literal_token}/bad/
    end
    """)

    assert {:ok, receipt} = NoRegularExpressionScanner.scan([path], target_roots: roots)
    assert receipt.status == :open_defect
    assert Enum.map(receipt.findings, & &1.token) == [module_token, literal_token]
  end

  test "skips dependency and doc paths", %{roots: roots} do
    repo_root = Map.fetch!(roots, "stack_lab")
    deps_path = Path.join(repo_root, "deps/example/lib/example.ex")
    doc_path = Path.join(repo_root, "docs/example.md")
    dist_path = Path.join(repo_root, "dist/hex/stack_lab/components/core/example.ex")
    clean_path = Path.join(repo_root, "lib/stack_lab/example.ex")
    literal_token = "~" <> "r"

    write_file(deps_path, "defmodule DependencyExample, do: nil\n")
    write_file(doc_path, "Documentation may mention regular expression APIs.\n")

    write_file(
      dist_path,
      "defmodule GeneratedDistributionExample, do: #{literal_token}/generated/\n"
    )

    write_file(clean_path, "defmodule StackLab.Example, do: nil\n")

    assert {:ok, receipt} = NoRegularExpressionScanner.scan([repo_root], target_roots: roots)
    assert receipt.status == :pass
    assert receipt.checked_paths == [clean_path]
    assert Enum.any?(receipt.skipped_paths, &(&1.path == Path.join(repo_root, "deps")))
    assert Enum.any?(receipt.skipped_paths, &(&1.path == Path.join(repo_root, "dist")))
    assert Enum.any?(receipt.skipped_paths, &(&1.path == Path.join(repo_root, "docs")))
  end

  defp write_file(path, content) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
  end
end
