defmodule StackLabTest do
  use ExUnit.Case
  doctest StackLab

  test "hello/0 returns the starter marker" do
    assert StackLab.hello() == :world
  end
end
