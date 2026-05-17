defmodule StackLab.CitadelSpineHarness.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: StackLab.CitadelSpineHarness.TaskSupervisor},
      {DynamicSupervisor,
       strategy: :one_for_one, name: StackLab.CitadelSpineHarness.RuntimeSupportSupervisor},
      StackLab.CitadelSpineHarness.RuntimeResourceOwner
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: StackLab.CitadelSpineHarness.Supervisor
    )
  end
end
