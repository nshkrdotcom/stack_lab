defmodule StackLab.Examples.RestartAuthorityDrillTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness.RemoteSupport
  alias StackLab.Examples.RestartAuthorityDrill

  @distribution_skip (case RemoteSupport.ensure_distribution_started() do
                        :ok ->
                          false

                        {:error, reason} ->
                          RemoteSupport.distribution_start_error_message(reason)
                      end)

  test "restart-authority drill points at the fault runbook" do
    scenario = RestartAuthorityDrill.scenario()

    assert scenario.name == :restart_authority_drill
    assert :revoked_credentials_after_restart in Map.keys(scenario.cases)
    assert :duplicate_old_lease_materialization in Map.keys(scenario.cases)
    assert :delayed_retry_revalidates_authority in Map.keys(scenario.cases)
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "Phase 14 restart revocation and stale-ref cases fail closed" do
    cases = %{
      revoked_credentials_after_restart: :lease_revoked_after_restart,
      expired_lease_after_restart: :lease_expired_after_restart,
      rotated_handle_epoch_after_restart: :rotation_epoch_mismatch,
      stale_installation_revision_after_restart: :stale_installation_revision,
      stale_target_grant_after_restart: :stale_target_grant,
      duplicate_old_lease_materialization: :duplicate_dispatch_old_lease_reuse
    }

    Enum.each(cases, fn {case_name, reason} ->
      assert {:ok, result} = RestartAuthorityDrill.exercise(case_name)

      assert result.case == case_name
      assert result.status == :rejected
      assert result.reason == reason
      assert result.redacted?
      refute inspect(result) =~ "raw_token"
    end)
  end

  test "delayed retry remains a single active execution and revalidates authority" do
    assert {:ok, result} = RestartAuthorityDrill.exercise(:delayed_retry_revalidates_authority)

    assert result.status == :authorized
    assert result.retry_dispatch_status == :authorized_revalidated
    assert result.active_execution_ref == "execution://tenant-1/codex/active-1"
    assert result.idempotency_key == "idem://tenant-1/codex/retry-1"
    assert result.credential_lease_ref == "credential-lease://tenant-1/codex/a/1"
    assert result.target_ref == "target://tenant-1/sandbox/a"
    assert result.restart_event == :workflow_resume
    assert result.redacted?
  end

  test "target detach sandbox restart process crash stream reconnect and workflow resume revalidate" do
    assert {:ok, result} = RestartAuthorityDrill.exercise(:restart_event_revalidation)

    assert result.status == :authorized

    assert result.events == %{
             target_detach: :authorized_revalidated,
             sandbox_restart: :authorized_revalidated,
             process_crash: :authorized_revalidated,
             stream_reconnect: :authorized_revalidated,
             workflow_resume: :authorized_revalidated
           }

    assert result.redacted?
  end

  @tag skip: @distribution_skip
  test "delayed acceptance still converges to durable submission truth" do
    assert {:ok, result} = RestartAuthorityDrill.exercise(:delayed_acceptance)

    assert result.case == :delayed_acceptance
    assert result.delay_ms >= 100
    assert result.transport.status == :accepted
    assert result.citadel.replay_status == :submission_accepted
    assert result.transport.submission_key == result.spine.submission_key
  end

  @tag skip: @distribution_skip
  @tag timeout: 120_000
  test "node restart recovery replays pending work into a replacement Spine node" do
    assert {:ok, result} = RestartAuthorityDrill.exercise(:node_restart_recovery)

    assert result.case == :node_restart_recovery
    assert result.before_restart.replay_status == :pending
    assert result.before_restart.last_error_code == "transport_unreachable"
    assert result.after_restart.replay_status == :submission_accepted
    assert result.transport.status == :accepted
    assert result.transport.submission_key == result.spine.submission_key
    refute result.remote.initial_node == result.remote.replacement_node
  end
end
