defmodule StackLab.GnTen.RestartFencingScenarios do
  @moduledoc """
  Provider-free restart and fencing scenarios for the gn-ten proof matrix.

  These scenarios are deterministic local fixtures. They prove the shape of
  restart-sensitive duplicate-dispatch, stale-revision, and revoked-lease
  fences without claiming production deployment or live provider behavior.
  """

  alias GroundPlane.Contracts.{Fence, Lease}

  @schema_version "gn_ten_restart_fencing_v1"
  @scenario_ids ~w(
    active_delayed_retry_duplicate_dispatch
    stale_installation_revision
    revoked_lease_restart_fence
  )

  @spec report() :: map()
  def report do
    now = DateTime.from_unix!(1_700_000_000)

    %{
      schema_version: @schema_version,
      profile: "assembled_offline",
      provider_free?: true,
      proof_posture: proof_posture(),
      scenarios: [
        retry_scenario(now),
        stale_revision_scenario(),
        revoked_lease_scenario(now)
      ]
    }
  end

  @spec validate_report(map()) :: :ok | {:error, [map()]}
  def validate_report(report) when is_map(report) do
    failures =
      []
      |> require_equal("restart_bad_schema", report[:schema_version], @schema_version)
      |> require_equal("restart_bad_profile", report[:profile], "assembled_offline")
      |> require_equal("restart_not_provider_free", report[:provider_free?], true)
      |> validate_posture(report[:proof_posture])
      |> validate_scenarios(report[:scenarios])

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  def validate_report(_report), do: {:error, [%{code: "restart_invalid_report"}]}

  defp retry_scenario(now) do
    subject_id = "subject-phase14-retry"

    active_execution = %{
      "execution_id" => "execution-phase14-retry",
      "subject_id" => subject_id,
      "dispatch_state" => "in_flight",
      "next_dispatch_at" => DateTime.add(now, 60, :second),
      "last_dispatch_error_kind" => "worker_crash"
    }

    duplicate_attempt = duplicate_dispatch_attempt([active_execution], subject_id)

    %{
      id: "active_delayed_retry_duplicate_dispatch",
      owner_repo: "stack_lab",
      outcome: "passed",
      evidence: %{
        active_execution_id: active_execution["execution_id"],
        active_dispatch_state: active_execution["dispatch_state"],
        delayed_retry_due_at: DateTime.to_iso8601(active_execution["next_dispatch_at"]),
        duplicate_dispatch_attempt: duplicate_attempt,
        queued_execution_count: 0
      },
      does_not_prove: common_non_claims()
    }
  end

  defp stale_revision_scenario do
    attempted_revision = 2
    current_revision = 3

    %{
      id: "stale_installation_revision",
      owner_repo: "stack_lab",
      outcome: "passed",
      evidence: %{
        attempted_revision: attempted_revision,
        current_revision: current_revision,
        dispatch_gate: revision_gate(attempted_revision, current_revision)
      },
      does_not_prove: common_non_claims()
    }
  end

  defp revoked_lease_scenario(now) do
    later = DateTime.add(now, 120, :second)

    {:ok, revoked_lease} =
      Lease.new(%{
        resource: "execution:subject:phase14",
        holder: "scheduler-node-a",
        lease_id: "lease-phase14-revoked",
        epoch: 7,
        expires_at: later,
        revoked_at: DateTime.add(now, 10, :second),
        revocation_ref: "revocation://phase14/lease-phase14-revoked"
      })

    denied_reuse =
      revoked_lease
      |> Fence.from_lease()
      |> then(&Fence.authorize_restart_reuse(revoked_lease, &1, DateTime.add(now, 20, :second)))
      |> normalize_restart_reuse()

    %{
      id: "revoked_lease_restart_fence",
      owner_repo: "stack_lab",
      outcome: "passed",
      evidence: %{
        lease_id: revoked_lease.lease_id,
        lease_epoch: revoked_lease.epoch,
        revocation_ref: revoked_lease.revocation_ref,
        after_restart_reuse: denied_reuse
      },
      does_not_prove: common_non_claims()
    }
  end

  defp duplicate_dispatch_attempt(active_executions, subject_id) do
    active? =
      Enum.any?(active_executions, fn execution ->
        execution["subject_id"] == subject_id and active_execution?(execution)
      end)

    if active? do
      %{
        "status" => "denied",
        "reason" => "active_execution_present",
        "safe_action" => "resume_existing_execution"
      }
    else
      %{"status" => "allowed"}
    end
  end

  defp active_execution?(%{"dispatch_state" => state}) do
    state in ["queued", "in_flight", "accepted_active"]
  end

  defp revision_gate(attempted_revision, current_revision)
       when attempted_revision == current_revision do
    %{"status" => "allowed", "current_revision" => current_revision}
  end

  defp revision_gate(attempted_revision, current_revision) do
    %{
      "status" => "denied",
      "reason" => "stale_installation_revision",
      "attempted_revision" => attempted_revision,
      "current_revision" => current_revision,
      "safe_action" => "reload_installation_revision"
    }
  end

  defp normalize_restart_reuse({:ok, details}) do
    details
    |> Map.take([:lease_id, :lease_epoch, :fence_epoch])
    |> Map.put(:status, "allowed")
  end

  defp normalize_restart_reuse({:error, {reason, details}}) do
    details
    |> Map.take([:lease_id, :lease_epoch, :fence_epoch, :revocation_ref])
    |> Map.put(:status, "denied")
    |> Map.put(:reason, Atom.to_string(reason))
    |> Map.put(:safe_action, "require_new_non_revoked_lease")
  end

  defp proof_posture do
    %{
      authoritative_audit?: false,
      production_deployment_proven?: false,
      provider_free_restart_fixture?: true,
      safe_action: "use_as_provider_free_restart_fencing_fixture"
    }
  end

  defp common_non_claims do
    [
      "production restart orchestration",
      "live provider credential handling",
      "audit-grade lease revocation"
    ]
  end

  defp validate_posture(failures, %{} = posture) do
    if posture.authoritative_audit? == false and
         posture.production_deployment_proven? == false and
         posture.provider_free_restart_fixture? == true do
      failures
    else
      [failure("restart_bad_posture", posture: posture) | failures]
    end
  end

  defp validate_posture(failures, posture),
    do: [failure("restart_bad_posture", posture: posture) | failures]

  defp validate_scenarios(failures, scenarios) when is_list(scenarios) do
    present = scenarios |> Enum.map(& &1[:id]) |> Enum.sort()

    failures
    |> require_equal("restart_missing_scenarios", present, Enum.sort(@scenario_ids))
    |> validate_scenario_outcomes(scenarios)
  end

  defp validate_scenarios(failures, _scenarios) do
    [failure("restart_missing_scenarios", scenarios: @scenario_ids) | failures]
  end

  defp validate_scenario_outcomes(failures, scenarios) do
    Enum.reduce(scenarios, failures, fn scenario, acc ->
      if scenario[:outcome] == "passed" and scenario_passed?(scenario) do
        acc
      else
        [failure("restart_scenario_failed", scenario: scenario[:id]) | acc]
      end
    end)
  end

  defp scenario_passed?(%{
         id: "active_delayed_retry_duplicate_dispatch",
         evidence: evidence
       }) do
    evidence.queued_execution_count == 0 and
      evidence.duplicate_dispatch_attempt["status"] == "denied" and
      evidence.duplicate_dispatch_attempt["reason"] == "active_execution_present"
  end

  defp scenario_passed?(%{id: "stale_installation_revision", evidence: evidence}) do
    evidence.dispatch_gate["status"] == "denied" and
      evidence.dispatch_gate["reason"] == "stale_installation_revision"
  end

  defp scenario_passed?(%{id: "revoked_lease_restart_fence", evidence: evidence}) do
    evidence.after_restart_reuse.status == "denied" and
      evidence.after_restart_reuse.reason == "lease_revoked_after_restart"
  end

  defp scenario_passed?(_scenario), do: false

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected),
    do: [failure(code, expected: expected, actual: actual) | failures]

  defp failure(code, attrs), do: Map.new([{:code, code} | attrs])
end
