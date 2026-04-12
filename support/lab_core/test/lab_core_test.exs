defmodule StackLab.LabCoreTest do
  use ExUnit.Case, async: true

  test "required harness files exist" do
    assert Enum.all?(StackLab.LabCore.required_paths(), &File.exists?/1)
  end
end
