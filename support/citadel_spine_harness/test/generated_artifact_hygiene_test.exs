defmodule StackLab.CitadelSpineHarness.GeneratedArtifactHygieneTest do
  use ExUnit.Case, async: true

  test "archival cold-store output is outside the harness package worktree" do
    cold_store = Application.fetch_env!(:mezzanine_archival_engine, :cold_store)
    root = Keyword.fetch!(cold_store, :root)
    harness_root = Path.expand("..", __DIR__)

    refute path_inside?(root, harness_root)
    assert path_inside?(root, System.tmp_dir!())
  end

  defp path_inside?(path, root) do
    expanded_path = path |> Path.expand() |> String.trim_trailing("/")
    expanded_root = root |> Path.expand() |> String.trim_trailing("/")

    expanded_path == expanded_root or String.starts_with?(expanded_path, expanded_root <> "/")
  end
end
