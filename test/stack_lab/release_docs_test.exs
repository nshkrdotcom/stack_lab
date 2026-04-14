defmodule StackLab.ReleaseDocsTest do
  use ExUnit.Case, async: true

  @docs_paths [
    "README.md",
    "docs/development.md"
  ]

  test "release docs describe the projection tracking workflow" do
    Enum.each(@docs_paths, fn path ->
      doc = File.read!(path)

      assert doc =~ "mix release.prepare",
             "#{path} must describe bundle preparation explicitly"

      assert doc =~ "mix release.track",
             "#{path} must describe projection tracking explicitly"

      assert doc =~ "mix release.archive",
             "#{path} must describe bundle archival explicitly"

      assert doc =~ "projection/stack_lab_lab_core",
             "#{path} must describe the projection branch explicitly"
    end)
  end
end
