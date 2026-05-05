defmodule StackLab.Examples.RestartAuthorityDrill do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.restart_authority_scenario()
  end

  def exercise(case_name)
      when case_name in [
             :delayed_acceptance,
             :node_restart_recovery,
             :revoked_credentials_after_restart,
             :expired_lease_after_restart,
             :rotated_handle_epoch_after_restart,
             :stale_installation_revision_after_restart,
             :stale_target_grant_after_restart,
             :duplicate_old_lease_materialization,
             :delayed_retry_revalidates_authority,
             :restart_event_revalidation
           ] do
    CitadelSpineHarness.exercise_restart_authority(case_name)
  end
end
