ExUnit.start()

defmodule StackLab.ChassisBridgeTest do
  use ExUnit.Case, async: true

  test "runs chassis proof catalog" do
    assert {:ok, %{passed: 12, failed: 0}} = StackLab.ChassisBridge.run(:chassis)
  end
end
