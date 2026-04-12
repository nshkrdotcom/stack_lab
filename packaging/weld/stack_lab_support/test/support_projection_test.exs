defmodule StackLabSupportProjectionTest do
  use ExUnit.Case, async: true

  test "projected support package exposes the core helper module" do
    assert Code.ensure_loaded?(StackLab.LabCore)
  end
end
