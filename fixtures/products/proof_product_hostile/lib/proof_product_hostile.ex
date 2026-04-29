defmodule ProofProductHostile do
  @moduledoc false

  alias AppKit.Bridges.MezzanineBridge
  alias Mezzanine.Execution.RuntimeStack

  def bypasses do
    [MezzanineBridge, RuntimeStack]
  end
end
