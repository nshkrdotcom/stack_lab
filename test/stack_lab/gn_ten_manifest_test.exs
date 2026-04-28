defmodule StackLab.GnTen.ManifestTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.Manifest

  test "validates the checked-in gn-ten manifest and proof matrix" do
    assert {:ok, result} = Manifest.validate_file()
    assert result.schema_version == "gn_ten_manifest_v1"
    assert result.workspace_ref == "workspace://nshkrdotcom/gn-ten"
    assert result.repos == Manifest.expected_repos()
    assert result.proof_matrix == "docs/gn_ten_proof_matrix.md"
  end

  test "rejects missing repos" do
    manifest_path = temp_manifest!("ground_plane", "ground_plain")

    assert {:error, failures} = Manifest.validate_file(manifest_path)
    assert Enum.any?(failures, &match?({:mismatch, :repos, _expected, _actual}, &1))
  end

  test "rejects proof matrices that do not cover every repo" do
    root = temp_root!()
    manifest = File.read!(Manifest.default_path())
    File.write!(Path.join(root, "gn-ten.yml"), manifest)
    File.mkdir_p!(Path.join(root, "docs"))
    File.write!(Path.join(root, "docs/gn_ten_proof_matrix.md"), "`ground_plane`")

    assert {:error, failures} = Manifest.validate_file(Path.join(root, "gn-ten.yml"))

    assert {:proof_matrix_missing_repos, missing} =
             Enum.find(failures, &match?({:proof_matrix_missing_repos, _}, &1))

    assert "AITrace" in missing
    assert "app_kit" in missing
  end

  defp temp_manifest!(from, to) do
    root = temp_root!()
    manifest = File.read!(Manifest.default_path()) |> String.replace(from, to)
    File.write!(Path.join(root, "gn-ten.yml"), manifest)
    File.mkdir_p!(Path.join(root, "docs"))

    File.cp!(
      Path.expand("../../docs/gn_ten_proof_matrix.md", __DIR__),
      Path.join(root, "docs/gn_ten_proof_matrix.md")
    )

    Path.join(root, "gn-ten.yml")
  end

  defp temp_root! do
    root = Path.join(System.tmp_dir!(), "stack_lab_gn_ten_#{System.unique_integer([:positive])}")
    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
