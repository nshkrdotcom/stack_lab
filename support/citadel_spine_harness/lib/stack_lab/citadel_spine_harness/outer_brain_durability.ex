defmodule StackLab.CitadelSpineHarness.OuterBrainDurability do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias OuterBrain.Contracts.{ReplyBodyBoundary, SemanticFailure}

  alias OuterBrain.Journal.Tables.{
    RecoveryTaskRecord,
    ReplyPublicationRecord,
    SemanticJournalEntryRecord
  }

  alias OuterBrain.Persistence.{Repo, Store}
  alias OuterBrain.RestartAuthority.RestartScan
  alias OuterBrain.Runtime.{LeaseRegistry, SessionOwner}
  alias StackLab.CitadelSpineHarness.PostgresContainer

  @case_names [
    :pending_recovery_after_restart,
    :final_reply_after_restart,
    :semantic_failure_carrier_after_restart,
    :duplicate_publication_suppressed_after_restart
  ]

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
            ttl_seconds: 30,
            lease_store: Store,
            lease_store_opts: [repo: Repo]
          )

        {:ok, journal_entry} =
          Store.append_semantic_journal_entry(
            journal_entry_record(case_name, session_id, causal_unit_id),
            repo: Repo
          )

        case_record = persist_case_record!(case_name, session_id, causal_unit_id)
        mirrored_fence = LeaseRegistry.current_fence(registry, session_id)

        stop_registry(registry)
        restart_repo!(repo_config)

        {:ok, restarted_registry} = LeaseRegistry.start_link([])

        try do
          persisted_lease = fetch_current_lease!(session_id)
          replay_record = replay_after_restart!(case_name, causal_unit_id)
          persisted_entries = Store.journal_entries(session_id, repo: Repo)
          persisted_failures = Store.semantic_failure_entries(session_id, repo: Repo)
          persisted_publications = Store.reply_publications(causal_unit_id, repo: Repo)

          analysis =
            RestartScan.reconstruct(
              session_id,
              causal_unit_id,
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

  defp persist_case_record!(:pending_recovery_after_restart, session_id, causal_unit_id) do
    {:ok, recovery_task} =
      Store.record_recovery_task(
        recovery_task_record(session_id, :ambiguous_submission),
        repo: Repo
      )

    {:ok, publication} =
      Store.record_reply_publication(
        reply_publication_record(causal_unit_id, :provisional, "Working"),
        repo: Repo
      )

    %{
      recovery_task_id: recovery_task.task_id,
      publication_id: publication.publication_id,
      publication_phase: publication.phase
    }
  end

  defp persist_case_record!(:final_reply_after_restart, _session_id, causal_unit_id) do
    {:ok, publication} =
      Store.record_reply_publication(
        reply_publication_record(causal_unit_id, :final, "Done"),
        repo: Repo
      )

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
         _session_id,
         causal_unit_id
       ) do
    {:ok, publication} =
      Store.record_reply_publication(
        reply_publication_record(causal_unit_id, :final, "Done"),
        repo: Repo
      )

    %{
      initial_publication_id: publication.publication_id,
      publication_phase: publication.phase
    }
  end

  defp replay_after_restart!(:duplicate_publication_suppressed_after_restart, causal_unit_id) do
    {:ok, publication} =
      Store.record_reply_publication(
        reply_publication_record(
          causal_unit_id,
          :final,
          "Done",
          publication_id: "publication-replayed-#{causal_unit_id}-final"
        ),
        repo: Repo
      )

    %{replayed_publication_id: publication.publication_id}
  end

  defp replay_after_restart!(_case_name, _causal_unit_id), do: %{}

  defp with_store(case_name, fun) when is_function(fun, 1) do
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
  end

  defp start_repo!(repo_config) do
    {:ok, repo_pid} = Repo.start_link(repo_config)
    Process.unlink(repo_pid)
    repo_pid
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
    case Store.fetch_current_lease(session_id, repo: Repo) do
      {:ok, lease} -> lease
      :error -> raise "expected durable lease for #{inspect(session_id)}"
    end
  end

  defp ensure_schema! do
    Enum.each(schema_statements(), fn statement ->
      SQL.query!(Repo, statement, [])
    end)
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

  defp reply_publication_record(causal_unit_id, phase, body, opts \\ []) do
    dedupe_key = "#{causal_unit_id}:#{phase}"
    {:ok, reply_body} = ReplyBodyBoundary.build(causal_unit_id, phase, dedupe_key, body)

    {:ok, publication} =
      ReplyPublicationRecord.new(%{
        publication_id:
          Keyword.get(opts, :publication_id, "publication-#{causal_unit_id}-#{phase}"),
        causal_unit_id: causal_unit_id,
        phase: phase,
        state: :published,
        dedupe_key: dedupe_key,
        body: reply_body.preview,
        body_ref: reply_body.ref
      })

    publication
  end

  defp semantic_failure(session_id, causal_unit_id) do
    {:ok, failure} =
      SemanticFailure.new(%{
        kind: :semantic_insufficient_context,
        tenant_id: "tenant-outer-brain-durability",
        semantic_session_id: session_id,
        causal_unit_id: causal_unit_id,
        request_trace_id: "trace-semantic-failure",
        provenance: [%{"surface" => "stack_lab.outer_brain_durability"}],
        operator_message: "The semantic runtime needs more context before dispatch."
      })

    failure
  end

  defp schema_statements do
    [
      """
      CREATE TABLE IF NOT EXISTS semantic_session_leases (
        row_id text PRIMARY KEY,
        session_id text NOT NULL,
        holder text NOT NULL,
        lease_id text NOT NULL,
        epoch bigint NOT NULL,
        expires_at timestamptz NOT NULL,
        inserted_at timestamptz NOT NULL,
        updated_at timestamptz NOT NULL
      )
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS semantic_session_leases_session_id_index
      ON semantic_session_leases (session_id)
      """,
      """
      CREATE TABLE IF NOT EXISTS semantic_journal_entries (
        entry_id text PRIMARY KEY,
        session_id text NOT NULL,
        causal_unit_id text NOT NULL,
        entry_type text NOT NULL,
        payload jsonb NOT NULL DEFAULT '{}'::jsonb,
        recorded_at timestamptz NOT NULL,
        inserted_at timestamptz NOT NULL
      )
      """,
      """
      CREATE INDEX IF NOT EXISTS semantic_journal_entries_session_id_recorded_at_index
      ON semantic_journal_entries (session_id, recorded_at)
      """,
      """
      CREATE INDEX IF NOT EXISTS semantic_journal_entries_causal_unit_id_recorded_at_index
      ON semantic_journal_entries (causal_unit_id, recorded_at)
      """,
      """
      CREATE TABLE IF NOT EXISTS recovery_tasks (
        task_id text PRIMARY KEY,
        session_id text NOT NULL,
        reason text NOT NULL,
        status text NOT NULL,
        inserted_at timestamptz NOT NULL,
        updated_at timestamptz NOT NULL
      )
      """,
      """
      CREATE INDEX IF NOT EXISTS recovery_tasks_session_id_status_index
      ON recovery_tasks (session_id, status)
      """,
      """
      CREATE TABLE IF NOT EXISTS reply_publications (
        publication_id text PRIMARY KEY,
        causal_unit_id text NOT NULL,
        phase text NOT NULL,
        state text NOT NULL,
        dedupe_key text NOT NULL,
        body text NOT NULL,
        body_ref jsonb NOT NULL DEFAULT '{}'::jsonb,
        inserted_at timestamptz NOT NULL,
        updated_at timestamptz NOT NULL
      )
      """,
      """
      ALTER TABLE reply_publications
      ADD COLUMN IF NOT EXISTS body_ref jsonb NOT NULL DEFAULT '{}'::jsonb
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS reply_publications_dedupe_key_index
      ON reply_publications (dedupe_key)
      """,
      """
      CREATE INDEX IF NOT EXISTS reply_publications_causal_unit_id_phase_index
      ON reply_publications (causal_unit_id, phase)
      """
    ]
  end
end
