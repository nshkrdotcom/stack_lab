defmodule StackLab.CitadelSpineHarness.AtomCleanupBoundaryTest do
  use ExUnit.Case, async: true

  @runtime_patterns [
    {"String." <> "to_" <> "atom", :string_to_atom},
    {"String." <> "to_existing_" <> "atom", :string_to_existing_atom},
    {"binary_to_" <> "atom", :binary_atom_creation},
    {"binary_to_existing_" <> "atom", :binary_existing_atom_creation},
    {"list_to_" <> "atom", :list_atom_creation},
    {"list_to_existing_" <> "atom", :list_existing_atom_creation},
    {":\"" <> "#" <> "{", :interpolated_atom}
  ]

  test "runtime harness source does not create atoms from runtime text" do
    harness_root = Path.expand("..", __DIR__)

    findings =
      harness_root
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard(match_dot: true)
      |> Enum.flat_map(&source_findings/1)

    assert findings == []
  end

  defp source_findings(path) do
    contents = File.read!(path)

    @runtime_patterns
    |> Enum.filter(fn {pattern, _kind} -> String.contains?(contents, pattern) end)
    |> Enum.map(fn {_pattern, kind} -> {Path.relative_to_cwd(path), kind} end)
    |> Kernel.++(atom_interpolation_findings(path, contents))
  end

  defp atom_interpolation_findings(path, contents) do
    if quoted_atom_interpolation?(contents) do
      [{Path.relative_to_cwd(path), :interpolated_atom}]
    else
      []
    end
  end

  defp quoted_atom_interpolation?(contents) do
    contents
    |> String.split(":\"", trim: true)
    |> Enum.any?(&quoted_atom_segment_has_interpolation?/1)
  end

  defp quoted_atom_segment_has_interpolation?(segment) do
    case String.split(segment, "\"", parts: 2) do
      [quoted_atom, _rest] -> String.contains?(quoted_atom, "#" <> "{")
      [_unterminated] -> false
    end
  end
end
