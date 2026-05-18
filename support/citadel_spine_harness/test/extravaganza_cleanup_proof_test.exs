defmodule StackLab.CitadelSpineHarness.ExtravaganzaCleanupProofTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness.ExtravaganzaCleanupProof

  test "spec requires approved write repo and rejects static provider selectors" do
    assert {:error, {:missing, ["--approved-write-repo"]}} =
             ExtravaganzaCleanupProof.parse_args([])

    assert {:ok, spec} =
             ExtravaganzaCleanupProof.parse_args([
               "--approved-write-repo",
               "nshkrdotcom/test",
               "--run-label",
               "phase1-test"
             ])

    assert spec.approved_write_repo == "nshkrdotcom/test"
    assert spec.run_label == "phase1-test"
    assert spec.timeout_ms == 60_000

    for flag <- [
          "--repo",
          "--branch",
          "--pull-number",
          "--github-pr-number",
          "--github-issue-number"
        ] do
      assert {:error, {:static_provider_selector, ^flag}} =
               ExtravaganzaCleanupProof.parse_args([
                 "--approved-write-repo",
                 "nshkrdotcom/test",
                 flag,
                 "static"
               ])
    end

    assert {:error, {:invalid_github_write_target, "nshkrdotcom/prod", "nshkrdotcom/test"}} =
             ExtravaganzaCleanupProof.parse_args([
               "--approved-write-repo",
               "nshkrdotcom/prod"
             ])
  end

  test "plan identifies product entrypoint and generated provider identity lifecycle" do
    assert {:ok, spec} =
             ExtravaganzaCleanupProof.parse_args([
               "--approved-write-repo",
               "nshkrdotcom/test"
             ])

    plan = ExtravaganzaCleanupProof.plan(spec)

    assert plan.steps == [
             :prepare_disposable_github_pr,
             :extravaganza_product_cleanup,
             :idempotent_product_cleanup_rerun,
             :delete_disposable_branch,
             :receipt_write
           ]

    assert plan.provider_identity_source == :generated_by_jido_github_connector
    assert plan.product_entrypoint == "mix extravaganza.headless.live.github_pr_cleanup"
    assert plan.product_role_ref == "proposed_change_cleanup"
    assert plan.execution_route_ref == "generic_substrate:v1"
    assert plan.static_provider_selector_acceptance? == false
  end

  test "run composes jido preparation, product cleanup, idempotence, branch cleanup, and receipt" do
    prepared = prepared_pr()

    command_runner = fn command, args, opts ->
      assert Keyword.has_key?(opts, :cd)

      cond do
        command =~ "live_acceptance.sh" and List.first(args) == "prepare-pr" ->
          assert args_include?(args, ["--write-repo", "nshkrdotcom/test"])
          {:ok, json_marker(prepared)}

        command == "mix" and List.first(args) == "extravaganza.headless.live.github_pr_cleanup" ->
          assert args_include?(args, ["--repo", prepared["repo"]])
          assert args_include?(args, ["--branch", prepared["branch"]])

          assert args_include?(args, ["--pull-number", Integer.to_string(prepared["pull_number"])])

          assert "--confirm-close" in args
          assert Keyword.fetch!(opts, :env) == [{"MIX_ENV", "test"}]

          if args_include?(args, [
               "--trace-id",
               "trace:stack-lab/phase1-test/github-cleanup/first"
             ]) do
            {:ok,
             "compile logs\n" <>
               Jason.encode!(
                 cleanup_envelope(prepared, [57], ["github.comment.create", "github.pr.update"])
               )}
          else
            {:ok, Jason.encode!(cleanup_envelope(prepared, [], []), pretty: true)}
          end

        command =~ "live_acceptance.sh" and List.first(args) == "delete-ref" ->
          assert args_include?(args, ["--write-repo", prepared["repo"]])
          assert args_include?(args, ["--branch", prepared["branch"]])
          {:ok, json_marker(branch_cleanup(prepared))}
      end
    end

    receipt_writer = fn path, receipt ->
      send(self(), {:receipt_written, path, receipt})
      {:ok, path}
    end

    progress = fn subject, event ->
      send(self(), {:progress, progress_subject(subject), event})
      :ok
    end

    assert {:ok, receipt} =
             ExtravaganzaCleanupProof.run(
               [
                 "--approved-write-repo",
                 "nshkrdotcom/test",
                 "--run-label",
                 "phase1-test",
                 "--receipt-file",
                 "/tmp/phase1-cleanup-proof.json"
               ],
               command_runner: command_runner,
               receipt_writer: receipt_writer,
               progress: progress
             )

    assert receipt.schema_name == "extravaganza_cleanup_proof_receipt_v1.json"
    assert receipt.proof_class == "extravaganza_destructive_cleanup_product_path"
    assert receipt.status == :passed
    assert receipt.approved_write_repo == "nshkrdotcom/test"
    assert receipt.assertions.product_governed_path? == true
    assert receipt.assertions.execution_route_ref == "generic_substrate:v1"
    assert receipt.assertions.resource_effect_role_ref == "proposed_change_cleanup"
    assert receipt.assertions.closed_pull_numbers == [57]
    assert receipt.assertions.idempotent_closed_pull_numbers == []
    assert receipt.assertions.idempotent_write_operations == []
    assert receipt.assertions.operation_receipt_emitted?
    assert receipt.assertions.operation_group_receipt_emitted?
    assert receipt.assertions.reduced_through_receipt_reducer?
    assert receipt.assertions.lineage_outbox_emitted?
    assert receipt.assertions.projection_readback_emitted?
    assert receipt.assertions.replay_exported?
    assert receipt.assertions.product_readback_wraps_generic_receipts?
    assert receipt.assertions.required_lineage_event_kinds_present?
    assert receipt.cleanup_leftover_status == "deleted"

    assert [
             %{operation: "jido.github.prepare_disposable_pr"},
             %{operation: "extravaganza.live.github_pr_cleanup.first"},
             %{operation: "extravaganza.live.github_pr_cleanup.idempotent"},
             %{operation: "jido.github.delete_disposable_ref"}
           ] = receipt.live_operation_inventory

    assert receipt.generic_receipt_projection.schema_name ==
             "extravaganza_cleanup_generic_receipt_projection_v1"

    assert receipt.generic_receipt_projection.reducer_module ==
             "Mezzanine.Projections.ReceiptReducer"

    assert receipt.generic_receipt_projection.product_cleanup.operation_receipt_refs == [
             "lower-receipt://github/pr-cleanup/list/succeeded",
             "lower-receipt://github/pr-cleanup/comment/succeeded",
             "lower-receipt://github/pr-cleanup/update/succeeded"
           ]

    assert receipt.generic_receipt_projection.product_cleanup.operation_group_status == :succeeded

    assert :receipt_reduced in receipt.generic_receipt_projection.product_cleanup.lineage_event_kinds

    assert :replay_exported in receipt.generic_receipt_projection.product_cleanup.lineage_event_kinds

    assert receipt.generic_receipt_projection.product_cleanup.product_readback.provider_effect_operation_receipts_present?

    assert receipt.generic_receipt_projection.idempotent_rerun.operation_receipt_refs == [
             "lower-receipt://github/pr-cleanup/list/succeeded"
           ]

    assert_receive {:receipt_written, "/tmp/phase1-cleanup-proof.json", ^receipt}
    assert_receive {:progress, :run, :started}
    assert_receive {:progress, :prepare_disposable_github_pr, :passed}
    assert_receive {:progress, :extravaganza_product_cleanup, :passed}
    assert_receive {:progress, :idempotent_product_cleanup_rerun, :passed}
    assert_receive {:progress, :delete_disposable_branch, :passed}
    assert_receive {:progress, :run, :receipt_written}
  end

  test "run reports lower preparation failures without accepting static provider identities" do
    command_runner = fn command, args, opts ->
      assert Keyword.has_key?(opts, :cd)
      assert command =~ "live_acceptance.sh"
      assert List.first(args) == "prepare-pr"
      {:error, %{exit_status: 1, output: "missing GitHub token"}}
    end

    assert {:error,
            %{
              step: :prepare_disposable_github_pr,
              reason: %{exit_status: 1, output: "missing GitHub token"}
            }} =
             ExtravaganzaCleanupProof.run(
               [
                 "--approved-write-repo",
                 "nshkrdotcom/test",
                 "--run-label",
                 "phase1-failure-test"
               ],
               command_runner: command_runner,
               progress: fn _subject, _event -> :ok end
             )
  end

  test "run rejects product cleanup output without generic lower operation receipts" do
    prepared = prepared_pr()

    command_runner = fn command, args, _opts ->
      cond do
        command =~ "live_acceptance.sh" and List.first(args) == "prepare-pr" ->
          {:ok, json_marker(prepared)}

        command == "mix" and List.first(args) == "extravaganza.headless.live.github_pr_cleanup" ->
          first_run? =
            args_include?(args, [
              "--trace-id",
              "trace:stack-lab/phase9-missing-generic-receipts/github-cleanup/first"
            ])

          closed_numbers =
            if first_run? do
              [57]
            else
              []
            end

          write_operations =
            if first_run? do
              ["github.pr.update"]
            else
              []
            end

          {:ok,
           prepared
           |> cleanup_envelope(closed_numbers, write_operations)
           |> put_in(["data", "provider_effect", "operation_receipts"], [])
           |> Jason.encode!()}

        command =~ "live_acceptance.sh" and List.first(args) == "delete-ref" ->
          {:ok, json_marker(branch_cleanup(prepared))}
      end
    end

    assert {:error, {:missing_generic_operation_receipts, []}} =
             ExtravaganzaCleanupProof.run(
               [
                 "--approved-write-repo",
                 "nshkrdotcom/test",
                 "--run-label",
                 "phase9-missing-generic-receipts"
               ],
               command_runner: command_runner,
               progress: fn _subject, _event -> :ok end
             )
  end

  test "run rejects product cleanup denial envelopes before leftover cleanup" do
    prepared = prepared_pr()

    command_runner = fn command, args, _opts ->
      cond do
        command =~ "live_acceptance.sh" and List.first(args) == "prepare-pr" ->
          {:ok, json_marker(prepared)}

        command == "mix" and List.first(args) == "extravaganza.headless.live.github_pr_cleanup" ->
          {:ok,
           Jason.encode!(%{
             "ok" => false,
             "operation" => "live.github-pr-cleanup",
             "execution_route_ref" => "generic_substrate:v1",
             "error" => %{"reason" => "github_pr_branch_cleanup_requires_confirmation"}
           })}
      end
    end

    assert {:error,
            {:product_cleanup_not_ok,
             %{"reason" => "github_pr_branch_cleanup_requires_confirmation"}}} =
             ExtravaganzaCleanupProof.run(
               [
                 "--approved-write-repo",
                 "nshkrdotcom/test",
                 "--run-label",
                 "phase1-denial-test"
               ],
               command_runner: command_runner,
               progress: fn _subject, _event -> :ok end
             )
  end

  defp args_include?(args, [flag, value]) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn pair -> pair == [flag, value] end)
  end

  defp json_marker(payload), do: "JSON_RESULT:" <> Jason.encode!(payload)

  defp prepared_pr do
    %{
      "proof_class" => "github_disposable_pr_preparation",
      "status" => "prepared",
      "repo" => "nshkrdotcom/test",
      "default_branch" => "main",
      "base_sha" => "abc123",
      "branch" => "jido-live-e2e-57",
      "delete_ref" => "heads/jido-live-e2e-57",
      "scratch_path" => "generated/live-e2e/jido-live-e2e-57.txt",
      "scratch_commit_sha" => "def456",
      "pull_number" => 57,
      "pull_state" => "open",
      "cleanup_required?" => true,
      "run_ids" => ["run-prep"]
    }
  end

  defp cleanup_envelope(prepared, closed_pull_numbers, write_operations) do
    %{
      "ok" => true,
      "schema" => "extravaganza.headless.response.v1",
      "operation" => "live.github-pr-cleanup",
      "execution_route_ref" => "generic_substrate:v1",
      "trace_id" => "trace:cleanup",
      "data" => %{
        "status" => if(closed_pull_numbers == [], do: "skipped", else: "completed"),
        "operation" => "live.github-pr-cleanup",
        "product_path_exercised?" => true,
        "provider_effect" => %{
          "resource_effect_role_ref" => "proposed_change_cleanup",
          "status" => if(closed_pull_numbers == [], do: "skipped", else: "receipt_recorded"),
          "operation" => "github.pr.branch_cleanup",
          "repo" => prepared["repo"],
          "branch" => prepared["branch"],
          "pull_numbers" => closed_pull_numbers,
          "closed_pull_numbers" => closed_pull_numbers,
          "provider_request_sent?" => true,
          "provider_response_received?" => true,
          "receipt_recorded?" => true,
          "product_readback_confirmed?" => true,
          "write_operations" => write_operations,
          "receipt_refs" => %{
            "lower_request_refs" =>
              cleanup_operation_receipts(write_operations)
              |> Enum.map(&Map.fetch!(&1, "lower_request_ref")),
            "lower_receipt_refs" =>
              cleanup_operation_receipts(write_operations)
              |> Enum.map(&Map.fetch!(&1, "lower_receipt_ref"))
          },
          "operation_receipts" => cleanup_operation_receipts(write_operations),
          "lower_request_ref" => "lower-request://github/pr-cleanup",
          "lower_receipt_ref" => "lower-receipt://github/pr-cleanup/succeeded"
        }
      }
    }
  end

  defp cleanup_operation_receipts(write_operations) do
    [
      operation_receipt("github.pr.list", "list")
      | write_operation_receipts(write_operations)
    ]
  end

  defp write_operation_receipts(write_operations) do
    write_operations
    |> Enum.flat_map(fn
      "github.comment.create" -> [operation_receipt("github.comment.create", "comment")]
      "github.pr.update" -> [operation_receipt("github.pr.update", "update")]
      _other -> []
    end)
  end

  defp operation_receipt(capability_id, suffix) do
    %{
      "capability_id" => capability_id,
      "capability_negotiation_ref" => "cap-neg://github/pr-cleanup/#{suffix}",
      "connector_manifest_ref" => "manifest://jido/connectors/github@test",
      "credential_lease_ref" => "credential-lease://github/primary/#{suffix}",
      "effect_request_ref" => "lower-request://github/pr-cleanup/#{suffix}",
      "lower_request_ref" => "lower-request://github/pr-cleanup/#{suffix}",
      "lower_receipt_ref" => "lower-receipt://github/pr-cleanup/#{suffix}/succeeded",
      "status" => "succeeded"
    }
  end

  defp branch_cleanup(prepared) do
    %{
      "proof_class" => "github_disposable_ref_cleanup",
      "status" => "deleted",
      "repo" => prepared["repo"],
      "branch" => prepared["branch"],
      "deleted_ref" => prepared["delete_ref"],
      "run_ids" => ["run-delete"]
    }
  end

  defp progress_subject(%{run_label: _run_label}), do: :run
  defp progress_subject(subject), do: subject
end
