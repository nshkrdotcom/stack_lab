defmodule StackLab.CitadelSpineHarness.OuterBrainDurability do
  @moduledoc false

  alias OuterBrain.Contracts.SemanticFailure

  alias OuterBrain.Journal.Tables.{
    RecoveryTaskRecord,
    SemanticJournalEntryRecord
  }

  alias OuterBrain.Persistence.{Repo, Store}
  alias OuterBrain.Prompting.SemanticTurnArtifacts
  alias OuterBrain.RestartAuthority.RestartScan
  alias OuterBrain.Runtime.{LeaseRegistry, SessionOwner}
  alias StackLab.CitadelSpineHarness.CompiledMigrations
  alias StackLab.CitadelSpineHarness.PostgresContainer
  alias StackLab.CitadelSpineHarness.RuntimeResourceOwner

  @case_names [
    :pending_recovery_after_restart,
    :final_reply_after_restart,
    :semantic_failure_carrier_after_restart,
    :duplicate_publication_suppressed_after_restart
  ]
  @tenant_id "tenant-outer-brain-durability"

  @spec run_case(
          :pending_recovery_after_restart
          | :final_reply_after_restart
          | :semantic_failure_carrier_after_restart
          | :duplicate_publication_suppressed_after_restart
        ) ::
          {:ok, map()}
  def run_case(case_name) when case_name in @case_names do
    with_store(case_name, fn repo_config ->
      session_id = "outer-brain-session-#{case_name}"
      causal_unit_id = "outer-brain-causal-#{case_name}"
      now = DateTime.from_unix!(1_800_002_000)

      {:ok, registry} = LeaseRegistry.start_link([])

      try do
        {:ok, :acquired, lease} =
          SessionOwner.acquire(
            registry,
            session_id,
            "stack_lab_outer_brain",
            1,
            now,
            tenant_id: @tenant_id,
            ttl_seconds: 30,
            lease_store: Store,
            lease_store_opts: [repo: Repo]
          )

        {:ok, journal_entry} =
          Store.append_semantic_journal_entry(
            journal_entry_record(case_name, session_id, causal_unit_id),
            repo: Repo,
            tenant_id: @tenant_id
          )

        case_record = persist_case_record!(case_name, session_id, causal_unit_id)
        mirrored_fence = LeaseRegistry.current_fence(registry, session_id)

        stop_registry(registry)
        restart_repo!(repo_config)

        {:ok, restarted_registry} = LeaseRegistry.start_link([])

        try do
          persisted_lease = fetch_current_lease!(session_id)
          replay_record = replay_after_restart!(case_name, session_id, causal_unit_id)
          persisted_entries = Store.journal_entries(@tenant_id, session_id, repo: Repo)
          persisted_failures = Store.semantic_failure_entries(@tenant_id, session_id, repo: Repo)

          persisted_publications =
            Store.reply_publications(@tenant_id, causal_unit_id, repo: Repo)

          analysis =
            RestartScan.reconstruct(
              session_id,
              causal_unit_id,
              tenant_id: @tenant_id,
              store: Store,
              store_opts: [repo: Repo]
            )

          {:ok,
           %{
             case: case_name,
             before_restart: %{
               mirrored_holder: mirrored_fence && mirrored_fence.holder,
               lease_holder: lease.holder,
               journal_entry_id: journal_entry.entry_id
             },
             after_restart: %{
               mirrored_fence: LeaseRegistry.current_fence(restarted_registry, session_id),
               persisted_lease_holder: persisted_lease.holder,
               persisted_lease_epoch: persisted_lease.epoch,
               journal_entry_ids: Enum.map(persisted_entries, & &1.entry_id),
               journal_entry_types: Enum.map(persisted_entries, & &1.entry_type),
               publication_phase: analysis.publication_phase,
               publication_ids: Enum.map(persisted_publications, & &1.publication_id),
               publication_bodies: Enum.map(persisted_publications, & &1.body),
               semantic_failure_kinds: Enum.map(persisted_failures, & &1.kind),
               semantic_failure_retry_classes: Enum.map(persisted_failures, & &1.retry_class),
               semantic_failure_trace_ids: Enum.map(persisted_failures, & &1.request_trace_id),
               pending_recovery_tasks: analysis.pending_recovery_tasks,
               next_action: analysis.next_action
             },
             durable: Map.merge(case_record, replay_record)
           }}
        after
          stop_registry(restarted_registry)
        end
      after
        stop_registry(registry)
      end
    end)
  end

  defp persist_case_record!(:pending_recovery_after_restart, session_id, _causal_unit_id) do
    {:ok, recovery_task} =
      Store.record_recovery_task(
        recovery_task_record(session_id, :ambiguous_submission),
        repo: Repo,
        tenant_id: @tenant_id
      )

    %{
      recovery_task_id: recovery_task.task_id,
      publication_id: nil,
      publication_phase: nil
    }
  end

  defp persist_case_record!(:final_reply_after_restart, session_id, causal_unit_id) do
    publication = publish_reply!(session_id, causal_unit_id, "Done")

    %{
      recovery_task_id: nil,
      publication_id: publication.publication_id,
      publication_phase: publication.phase
    }
  end

  defp persist_case_record!(
         :semantic_failure_carrier_after_restart,
         session_id,
         causal_unit_id
       ) do
    {:ok, failure} =
      Store.record_semantic_failure(
        semantic_failure(session_id, causal_unit_id),
        repo: Repo,
        recorded_at: DateTime.from_unix!(1_800_002_006)
      )

    %{
      semantic_failure_kind: failure.kind,
      semantic_failure_retry_class: failure.retry_class,
      semantic_failure_trace_id: failure.request_trace_id
    }
  end

  defp persist_case_record!(
         :duplicate_publication_suppressed_after_restart,
         session_id,
         causal_unit_id
       ) do
    publication = publish_reply!(session_id, causal_unit_id, "Done")

    %{
      initial_publication_id: publication.publication_id,
      publication_phase: publication.phase
    }
  end

  defp replay_after_restart!(
         :duplicate_publication_suppressed_after_restart,
         session_id,
         causal_unit_id
       ) do
    publication = publish_reply!(session_id, causal_unit_id, "Done")

    %{replayed_publication_id: publication.publication_id}
  end

  defp replay_after_restart!(_case_name, _session_id, _causal_unit_id), do: %{}

  defp with_store(case_name, fun) when is_function(fun, 1) do
    RuntimeResourceOwner.transaction(fn ->
      container = PostgresContainer.start!("outer_brain_restart_durability_#{case_name}")
      repo_config = PostgresContainer.repo_config(container.port)
      _repo_pid = start_repo!(repo_config)

      try do
        ensure_schema!()
        fun.(repo_config)
      after
        stop_repo(Process.whereis(Repo))
        PostgresContainer.stop!(container)
      end
    end)
  end

  defp start_repo!(repo_config) do
    case Repo.start_link(repo_config) do
      {:ok, repo_pid} ->
        Process.unlink(repo_pid)
        repo_pid

      {:error, {:already_started, repo_pid}} ->
        stop_repo(repo_pid)
        {:ok, restarted_pid} = Repo.start_link(repo_config)
        Process.unlink(restarted_pid)
        restarted_pid
    end
  end

  defp restart_repo!(repo_config) do
    stop_repo(Process.whereis(Repo))
    start_repo!(repo_config)
    :ok
  end

  defp stop_repo(nil), do: :ok

  defp stop_repo(repo_pid) when is_pid(repo_pid) do
    if Process.alive?(repo_pid) do
      try do
        GenServer.stop(Repo)
      catch
        :exit, _reason -> :ok
      end
    else
      :ok
    end
  end

  defp stop_registry(registry) when is_pid(registry) do
    if Process.alive?(registry) do
      Agent.stop(registry)
    else
      :ok
    end
  end

  defp fetch_current_lease!(session_id) do
    case Store.fetch_current_lease(@tenant_id, session_id, repo: Repo) do
      {:ok, lease} -> lease
      :error -> raise "expected durable lease for #{inspect(session_id)}"
    end
  end

  defp ensure_schema! do
    migrations_path = Application.app_dir(:outer_brain_persistence, "priv/repo/migrations")
    Ecto.Migrator.run(Repo, CompiledMigrations.for_path(migrations_path), :up, all: true)
  end

  defp journal_entry_record(case_name, session_id, causal_unit_id) do
    {:ok, entry} =
      SemanticJournalEntryRecord.new(%{
        entry_id: "semantic-entry-#{case_name}",
        session_id: session_id,
        causal_unit_id: causal_unit_id,
        entry_type: "wake_input",
        recorded_at: DateTime.from_unix!(1_800_002_005),
        payload: %{"case" => Atom.to_string(case_name)}
      })

    entry
  end

  defp recovery_task_record(session_id, reason) do
    {:ok, task} =
      RecoveryTaskRecord.new(%{
        task_id: "recovery-task-#{session_id}",
        session_id: session_id,
        reason: reason,
        status: :pending
      })

    task
  end

  defp publish_reply!(session_id, causal_unit_id, body) do
    prompt = prompt_context!(session_id, causal_unit_id)

    {:ok, ^prompt} = Store.record_prompt_context(prompt, repo: Repo, tenant_id: @tenant_id)

    {:ok, continuation} =
      SemanticTurnArtifacts.prepare_reply(prompt, %{
        attempt_ref: "attempt://stack-lab/#{causal_unit_id}",
        assistant_reply: body,
        dedupe_key: "#{causal_unit_id}:final",
        published_at: DateTime.from_unix!(1_800_002_006),
        allowed_reader_refs: ["reader://stack-lab"],
        allowed_operation_refs: ["operation://stack-lab/read"]
      })

    {:ok, persisted} =
      Store.publish_reply_continuation(continuation, repo: Repo, tenant_id: @tenant_id)

    persisted.publication
  end

  defp prompt_context!(session_id, causal_unit_id) do
    {:ok, prompt} =
      SemanticTurnArtifacts.prepare_prompt(%{
        tenant_ref: @tenant_id,
        installation_ref: "installation://stack-lab/outer-brain-durability",
        workspace_ref: "workspace://stack-lab/outer-brain-durability",
        project_ref: "project://stack-lab/outer-brain-durability",
        environment_ref: "environment://stack-lab/test",
        authority_packet_ref: "authority-packet://stack-lab/#{causal_unit_id}",
        permission_decision_ref: "decision://stack-lab/#{causal_unit_id}",
        idempotency_key: "idempotency://stack-lab/#{causal_unit_id}",
        trace_id: "trace://stack-lab/#{causal_unit_id}",
        correlation_id: "correlation://stack-lab/#{causal_unit_id}",
        release_manifest_ref: "release://stack-lab/outer-brain-durability-v1",
        input_claim_check_ref: "claim-check://stack-lab/#{causal_unit_id}/input",
        output_claim_check_ref: "claim-check://stack-lab/#{causal_unit_id}/output",
        redaction_policy_ref: "redaction-policy://stack-lab/outer-brain-durability-v1",
        normalizer_version: "outer-brain-normalizer-v1",
        run_ref: session_id,
        turn_ref: causal_unit_id,
        model_profile_ref: "model-profile://stack-lab/durability",
        provider_ref: "provider://stack-lab/simulation",
        model_ref: "model://stack-lab/simulation",
        producing_operation_ref: "operation://stack-lab/#{causal_unit_id}",
        system_actor_ref: "actor://stack-lab/outer-brain-durability",
        source_artifacts: [
          %{
            artifact_ref: "artifact://stack-lab/#{causal_unit_id}/system",
            content_digest: "sha256:" <> String.duplicate("0", 64),
            role: "system_instruction"
          },
          %{
            artifact_ref: "artifact://stack-lab/#{causal_unit_id}/input",
            content_digest: "sha256:" <> String.duplicate("1", 64),
            role: "user_input"
          }
        ],
        memory_snapshot_refs: [],
        allowed_reader_refs: ["reader://stack-lab"],
        allowed_operation_refs: ["operation://stack-lab/read"]
      })

    prompt
  end

  defp semantic_failure(session_id, causal_unit_id) do
    {:ok, failure} =
      SemanticFailure.new(%{
        kind: :semantic_insufficient_context,
        tenant_id: @tenant_id,
        semantic_session_id: session_id,
        causal_unit_id: causal_unit_id,
        request_trace_id: "trace-semantic-failure",
        provenance: [%{"surface" => "stack_lab.outer_brain_durability"}],
        operator_message: "The semantic runtime needs more context before dispatch."
      })

    failure
  end
end
