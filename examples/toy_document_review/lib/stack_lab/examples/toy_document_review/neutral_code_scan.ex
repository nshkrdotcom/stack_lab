defmodule StackLab.Examples.ToyDocumentReview.NeutralCodeScan do
  @moduledoc false

  def run(root_file, forbidden_terms) do
    files =
      root_file
      |> Path.dirname()
      |> Path.join("**/*.{ex,exs}")
      |> Path.wildcard()
      |> Enum.reject(&generated_path?/1)

    findings =
      files
      |> Enum.flat_map(fn path ->
        body = File.read!(path)

        forbidden_terms
        |> Enum.filter(&String.contains?(body, &1))
        |> Enum.map(&%{path: path, term: &1})
      end)

    %{
      accepted?: findings == [],
      scanned_file_count: length(files),
      forbidden_terms: forbidden_terms,
      findings: findings
    }
  end

  defp generated_path?(path) do
    parts = Path.split(path)
    "_build" in parts or "deps" in parts or "doc" in parts
  end
end
