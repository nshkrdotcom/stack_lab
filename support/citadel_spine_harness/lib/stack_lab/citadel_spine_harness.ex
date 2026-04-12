defmodule StackLab.CitadelSpineHarness do
  @moduledoc """
  Harness-owned configuration and repo resolution for assembled Citadel plus
  Jido Integration proofs.
  """

  alias StackLab.CitadelSpineHarness.{MultiNode, PressureFailover, RestartAuthority, SameNode}
  alias StackLab.LabCore

  @stack_lab_root Path.expand("../../../..", __DIR__)

  @type repo_roots :: %{
          required(:stack_lab) => String.t(),
          required(:citadel) => String.t(),
          required(:jido_integration) => String.t()
        }

  @spec repo_roots() :: repo_roots()
  def repo_roots do
    %{
      stack_lab: @stack_lab_root,
      citadel: Path.expand("../citadel", @stack_lab_root),
      jido_integration: Path.expand("../jido_integration", @stack_lab_root)
    }
  end

  @spec same_node_scenario() :: map()
  def same_node_scenario do
    %{
      name: :single_node_roundtrip,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        acceptance: %{kind: :acceptance},
        duplicate: %{kind: :duplicate},
        scope_rejection: %{kind: :scope_rejection}
      }
    }
  end

  @spec exercise_same_node(:acceptance | :duplicate | :scope_rejection) ::
          {:ok, map()} | {:error, term()}
  def exercise_same_node(case_name)
      when case_name in [:acceptance, :duplicate, :scope_rejection] do
    SameNode.run_case(case_name)
  end

  @spec multi_node_scenario() :: map()
  def multi_node_scenario do
    %{
      name: :multi_node_roundtrip,
      compose: LabCore.compose_file(:multi),
      runbook: LabCore.runbook(:up_multi),
      repo_roots: repo_roots(),
      cases: %{
        acceptance: %{kind: :acceptance},
        scope_rejection: %{kind: :scope_rejection}
      }
    }
  end

  @spec exercise_multi_node(:acceptance | :scope_rejection) :: {:ok, map()} | {:error, term()}
  def exercise_multi_node(case_name) when case_name in [:acceptance, :scope_rejection] do
    MultiNode.run_case(case_name)
  end

  @spec restart_authority_scenario() :: map()
  def restart_authority_scenario do
    %{
      name: :restart_authority_drill,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:faults),
      repo_roots: repo_roots(),
      cases: %{
        delayed_acceptance: %{kind: :delayed_acceptance},
        node_restart_recovery: %{kind: :node_restart_recovery}
      }
    }
  end

  @spec exercise_restart_authority(:delayed_acceptance | :node_restart_recovery) ::
          {:ok, map()} | {:error, term()}
  def exercise_restart_authority(case_name)
      when case_name in [:delayed_acceptance, :node_restart_recovery] do
    RestartAuthority.run_case(case_name)
  end

  @spec pressure_failover_scenario() :: map()
  def pressure_failover_scenario do
    %{
      name: :pressure_failover_drill,
      compose: LabCore.compose_file(:multi),
      runbook: LabCore.runbook(:faults),
      repo_roots: repo_roots(),
      cases: %{
        transport_interruption: %{kind: :transport_interruption},
        duplicate_delivery: %{kind: :duplicate_delivery}
      }
    }
  end

  @spec exercise_pressure_failover(:transport_interruption | :duplicate_delivery) ::
          {:ok, map()} | {:error, term()}
  def exercise_pressure_failover(case_name)
      when case_name in [:transport_interruption, :duplicate_delivery] do
    PressureFailover.run_case(case_name)
  end
end
