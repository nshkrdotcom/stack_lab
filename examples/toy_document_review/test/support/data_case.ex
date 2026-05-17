defmodule StackLab.Examples.ToyDocumentReview.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Mezzanine.ConfigRegistry.Repo
  alias Mezzanine.Execution.Repo, as: ExecutionRepo

  using do
    quote do
      import StackLab.Examples.ToyDocumentReview.DataCase
    end
  end

  setup tags do
    shared? = not tags[:async]
    execution_owner = Sandbox.start_owner!(ExecutionRepo, shared: shared?)
    registry_owner = Sandbox.start_owner!(Repo, shared: shared?)

    on_exit(fn ->
      Sandbox.stop_owner(registry_owner)
      Sandbox.stop_owner(execution_owner)
    end)

    :ok
  end
end
