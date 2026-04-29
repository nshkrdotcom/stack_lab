defmodule ProofProductMinimal do
  @moduledoc false

  alias AppKit.DomainSurface
  alias AppKit.OperatorSurface
  alias AppKit.ReviewSurface
  alias AppKit.RuntimeGateway
  alias AppKit.WorkControl
  alias AppKit.WorkSurface

  def surfaces do
    [
      DomainSurface,
      OperatorSurface,
      ReviewSurface,
      RuntimeGateway,
      WorkControl,
      WorkSurface
    ]
  end
end
