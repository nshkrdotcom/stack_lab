defmodule StackLab.CitadelSpineHarness do
  @moduledoc """
  Harness-owned configuration and repo resolution for assembled Citadel plus
  Jido Integration proofs.
  """

  alias StackLab.CitadelSpineHarness.{
    GovernedRun,
    LowerFacts,
    MezzanineRestartRecovery,
    MultiNode,
    OuterBrainDurability,
    PressureFailover,
    RestartAuthority,
    SameNode,
    SemanticHost,
    TypedHost
  }

  alias StackLab.LabCore

  @stack_lab_root Path.expand("../../../..", __DIR__)

  @type repo_roots :: %{
          required(:stack_lab) => String.t(),
          required(:citadel) => String.t(),
          required(:jido_integration) => String.t(),
          required(:mezzanine) => String.t(),
          required(:outer_brain) => String.t()
        }

  @spec repo_roots() :: repo_roots()
  def repo_roots do
    %{
      stack_lab: @stack_lab_root,
      citadel: Path.expand("../citadel", @stack_lab_root),
      jido_integration: Path.expand("../jido_integration", @stack_lab_root),
      mezzanine: Path.expand("../mezzanine", @stack_lab_root),
      outer_brain: Path.expand("../outer_brain", @stack_lab_root)
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

  @spec lower_facts_scenario() :: map()
  def lower_facts_scenario do
    %{
      name: :lower_facts_roundtrip,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        generic_readback: %{kind: :generic_readback},
        authorized_mezzanine_readback: %{kind: :authorized_mezzanine_readback},
        unauthorized_mezzanine_readback: %{kind: :unauthorized_mezzanine_readback}
      }
    }
  end

  @spec exercise_lower_facts(
          :generic_readback
          | :authorized_mezzanine_readback
          | :unauthorized_mezzanine_readback
        ) :: {:ok, map()} | {:error, term()}
  def exercise_lower_facts(case_name)
      when case_name in [
             :generic_readback,
             :authorized_mezzanine_readback,
             :unauthorized_mezzanine_readback
           ] do
    LowerFacts.run_case(case_name)
  end

  @spec outer_brain_durability_scenario() :: map()
  def outer_brain_durability_scenario do
    %{
      name: :outer_brain_restart_durability,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        pending_recovery_after_restart: %{kind: :pending_recovery_after_restart},
        final_reply_after_restart: %{kind: :final_reply_after_restart}
      }
    }
  end

  @spec exercise_outer_brain_durability(
          :pending_recovery_after_restart
          | :final_reply_after_restart
        ) :: {:ok, map()} | {:error, term()}
  def exercise_outer_brain_durability(case_name)
      when case_name in [:pending_recovery_after_restart, :final_reply_after_restart] do
    OuterBrainDurability.run_case(case_name)
  end

  @spec mezzanine_restart_recovery_scenario() :: map()
  def mezzanine_restart_recovery_scenario do
    %{
      name: :mezzanine_restart_recovery,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        dispatching_retry_after_restart: %{kind: :dispatching_retry_after_restart}
      }
    }
  end

  @spec exercise_mezzanine_restart_recovery(:dispatching_retry_after_restart) ::
          {:ok, map()} | {:error, term()}
  def exercise_mezzanine_restart_recovery(:dispatching_retry_after_restart) do
    MezzanineRestartRecovery.run_case(:dispatching_retry_after_restart)
  end

  @spec governed_run_scenario() :: map()
  def governed_run_scenario do
    %{
      name: :governed_run_roundtrip,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        expense_capture_acceptance: %{kind: :expense_capture_acceptance}
      }
    }
  end

  @spec exercise_governed_run(:expense_capture_acceptance) :: {:ok, map()} | {:error, term()}
  def exercise_governed_run(:expense_capture_acceptance) do
    GovernedRun.run_case(:expense_capture_acceptance)
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

  @spec typed_host_scenario() :: map()
  def typed_host_scenario do
    %{
      name: :typed_host_roundtrip,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        command_acceptance: %{kind: :command_acceptance},
        command_duplicate: %{kind: :command_duplicate},
        command_scope_rejection: %{kind: :command_scope_rejection}
      }
    }
  end

  @spec exercise_typed_host(:command_acceptance | :command_duplicate | :command_scope_rejection) ::
          {:ok, map()} | {:error, term()}
  def exercise_typed_host(case_name)
      when case_name in [:command_acceptance, :command_duplicate, :command_scope_rejection] do
    TypedHost.run_case(case_name)
  end

  @spec semantic_host_scenario() :: map()
  def semantic_host_scenario do
    %{
      name: :semantic_host_roundtrip,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        turn_acceptance: %{kind: :turn_acceptance},
        turn_replay: %{kind: :turn_replay},
        turn_scope_rejection: %{kind: :turn_scope_rejection}
      }
    }
  end

  @spec exercise_semantic_host(:turn_acceptance | :turn_replay | :turn_scope_rejection) ::
          {:ok, map()} | {:error, term()}
  def exercise_semantic_host(case_name)
      when case_name in [:turn_acceptance, :turn_replay, :turn_scope_rejection] do
    SemanticHost.run_case(case_name)
  end
end
