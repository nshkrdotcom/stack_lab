defmodule StackLab.GnTen.RefactoringDeletionBacklog do
  @moduledoc """
  Deterministic refactoring deletion backlog proof.

  The proof closes the deletion-backlog row by naming the current deletion
  campaigns and explicit retention/no-op records. It does not delete product
  compatibility surfaces that are outside the generic-stack platform claim.
  """

  @schema_version "gn_ten_refactoring_deletion_backlog_v1"
  @proof_id "refactoring_deletion_backlog"
  @profile "local_quick"
  @batch_id "20260518-refactoring-deletion-backlog"
  @batch_receipt "docs/receipts/gn_ten_batches/20260518_refactoring-deletion-backlog.json"
  @receipt_ref "receipt://stack_lab/refactoring_deletion_backlog/latest"
  @review_date "2026-06-18"
  @target_repos ~w(
    app_kit
    extravaganza
    mezzanine
    outer_brain
    citadel
    jido_integration
    execution_plane
    ground_plane
    stack_lab
    AITrace
  )
  @allowed_statuses ~w(deleted_before_current_phase retained_by_policy no_active_candidate)

  @spec report() :: map()
  def report do
    %{
      schema_version: @schema_version,
      proof_id: @proof_id,
      profile: @profile,
      receipt_ref: @receipt_ref,
      batch_id: @batch_id,
      batch_receipts: [@batch_receipt],
      target_repos: @target_repos,
      inventory: inventory(),
      deletion_campaigns: deletion_campaigns(),
      retention_receipts: retention_receipts(),
      scanner_posture: scanner_posture(),
      does_not_prove: [
        "semantic duplicate detection beyond the named inventory classes",
        "deletion of product compatibility routes or flags that are still public behavior",
        "future duplicate introductions outside scanner coverage"
      ]
    }
  end

  @spec validate_report(map()) :: :ok | {:error, [map()]}
  def validate_report(report) when is_map(report) do
    failures =
      []
      |> require_equal("refactor_bad_schema", report[:schema_version], @schema_version)
      |> require_equal("refactor_bad_id", report[:proof_id], @proof_id)
      |> require_equal("refactor_bad_profile", report[:profile], @profile)
      |> require_equal(
        "refactor_missing_repos",
        Enum.sort(report[:target_repos] || []),
        Enum.sort(@target_repos)
      )
      |> require_nonempty_list("refactor_missing_batch_receipts", report[:batch_receipts])
      |> validate_inventory(report[:inventory])
      |> validate_deletion_campaigns(report[:deletion_campaigns])
      |> validate_retention_receipts(report[:retention_receipts])
      |> validate_scanner_posture(report[:scanner_posture])

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  def validate_report(_report), do: {:error, [%{code: "refactor_invalid_report"}]}

  defp inventory do
    %{
      inventory_ref: "inventory://stack-lab/refactoring-deletion-backlog/20260518",
      method: "targeted_marker_inventory",
      searched_marker_classes: [
        "deprecated package references",
        "legacy provider dispatch",
        "compatibility shims",
        "duplicate owner declarations",
        "retained product compatibility routes"
      ],
      repo_file_counts: [
        %{repo: "app_kit", elixir_files: 172},
        %{repo: "extravaganza", elixir_files: 64},
        %{repo: "mezzanine", elixir_files: 729},
        %{repo: "outer_brain", elixir_files: 139},
        %{repo: "citadel", elixir_files: 409},
        %{repo: "jido_integration", elixir_files: 743},
        %{repo: "execution_plane", elixir_files: 96},
        %{repo: "ground_plane", elixir_files: 68},
        %{repo: "stack_lab", elixir_files: 174},
        %{repo: "AITrace", elixir_files: 21}
      ],
      active_delete_candidates: [],
      no_active_candidate_reason:
        "Current marker inventory found policy-retained compatibility surfaces and guard tests, not an unowned duplicate DTO/helper that can be deleted safely in this phase."
    }
  end

  defp deletion_campaigns do
    [
      %{
        id: "deprecated_mezzanine_bridge_package_refs",
        owner_repo: "app_kit",
        status: "deleted_before_current_phase",
        replacement_ref: "app-kit://bridges/mezzanine_bridge/service-layer",
        batch_receipt: @batch_receipt,
        evidence_refs: [
          "app_kit/bridges/mezzanine_bridge/test/app_kit/bridges/mezzanine_bridge_test.exs"
        ]
      },
      %{
        id: "extravaganza_runtime_direct_legacy_refs",
        owner_repo: "extravaganza",
        status: "deleted_before_current_phase",
        replacement_ref: "app-kit://runtime-gateway/generic-operation-receipts",
        batch_receipt: @batch_receipt,
        evidence_refs: [
          "extravaganza/apps/extravaganza_core/test/extravaganza_runtime_decoupling_test.exs"
        ]
      },
      %{
        id: "provider_family_dispatch_in_generic_scanners",
        owner_repo: "stack_lab",
        status: "deleted_before_current_phase",
        replacement_ref: "stack-lab://structural-gate/proof-bundle-registry",
        batch_receipt: @batch_receipt,
        evidence_refs: [
          "stack_lab/support/no_bypass_scanner/lib/stack_lab/structural_gate_scanner.ex",
          "stack_lab/proof_matrix.yml"
        ]
      },
      %{
        id: "current_inventory_active_delete_candidates",
        owner_repo: "stack_lab",
        status: "no_active_candidate",
        replacement_ref: "inventory://stack-lab/refactoring-deletion-backlog/20260518",
        batch_receipt: @batch_receipt,
        evidence_refs: [
          "stack_lab/docs/receipts/gn_ten_refactoring/deletion_backlog.md"
        ]
      }
    ]
  end

  defp retention_receipts do
    [
      %{
        id: "repo_agent_claude_compatibility_shims",
        owner_repo: "stack_lab",
        retained_surface: "CLAUDE.md -> AGENTS.md repo-agent compatibility shim",
        reason: "Required by repo agent instruction contract; not generic-stack runtime code.",
        review_date: @review_date,
        scanner_posture: "repo_agents_validate_enforced"
      },
      %{
        id: "extravaganza_public_product_compatibility",
        owner_repo: "extravaganza",
        retained_surface:
          "legacy headless flags, Symphony compatibility route, and legacy presenter assign keys",
        reason:
          "Public Extravaganza behavior that must remain untouched while lower calls use generic substrate paths.",
        review_date: @review_date,
        scanner_posture: "product_surface_allowed_generic_no_bypass_required"
      },
      %{
        id: "execution_plane_contract_rejection_fixtures",
        owner_repo: "execution_plane",
        retained_surface: "legacy attach-grant and compatibility-shim rejection docs/tests",
        reason:
          "Negative fixtures prove old shapes are rejected; they are not production compatibility paths.",
        review_date: @review_date,
        scanner_posture: "test_and_docs_only_retention"
      },
      %{
        id: "stack_lab_deprecated_artifact_history",
        owner_repo: "stack_lab",
        retained_surface: "deprecated artifact ledger history without active consumers",
        reason: "Release-history evidence retained so artifact drift is reviewable.",
        review_date: @review_date,
        scanner_posture: "contract_artifacts_validate_enforced"
      }
    ]
  end

  defp scanner_posture do
    %{
      proof_ref: "scanner-posture://stack-lab/refactoring-deletion-backlog/20260518",
      required_commands: [
        "mix gn_ten.repo_agents.validate",
        "mix gn_ten.connector.scan --all-repos",
        "mix gn_ten.tenant.scan --all-repos",
        "mix gn_ten.proofs.validate --json"
      ],
      retained_product_surfaces_are_allowed?: true,
      retained_generic_duplicate_dispatch_allowed?: false
    }
  end

  defp validate_inventory(failures, %{} = inventory) do
    failures
    |> require_present("refactor_missing_inventory_ref", inventory.inventory_ref)
    |> require_equal(
      "refactor_active_candidates_not_empty",
      inventory.active_delete_candidates,
      []
    )
    |> require_nonempty_list("refactor_missing_repo_counts", inventory.repo_file_counts)
  end

  defp validate_inventory(failures, _inventory),
    do: [failure("refactor_missing_inventory") | failures]

  defp validate_deletion_campaigns(failures, campaigns) when is_list(campaigns) do
    Enum.reduce(campaigns, failures, fn campaign, acc ->
      acc
      |> require_present("refactor_campaign_missing_id", campaign[:id])
      |> require_present("refactor_campaign_missing_owner", campaign[:owner_repo])
      |> require_allowed_status("refactor_campaign_bad_status", campaign[:status])
      |> require_present("refactor_campaign_missing_batch", campaign[:batch_receipt])
      |> require_nonempty_list("refactor_campaign_missing_evidence", campaign[:evidence_refs])
    end)
  end

  defp validate_deletion_campaigns(failures, _campaigns) do
    [failure("refactor_missing_deletion_campaigns") | failures]
  end

  defp validate_retention_receipts(failures, receipts) when is_list(receipts) do
    Enum.reduce(receipts, failures, fn receipt, acc ->
      acc
      |> require_present("refactor_retention_missing_id", receipt[:id])
      |> require_present("refactor_retention_missing_owner", receipt[:owner_repo])
      |> require_present("refactor_retention_missing_reason", receipt[:reason])
      |> require_present("refactor_retention_missing_review_date", receipt[:review_date])
      |> require_present("refactor_retention_missing_scanner_posture", receipt[:scanner_posture])
    end)
  end

  defp validate_retention_receipts(failures, _receipts) do
    [failure("refactor_missing_retention_receipts") | failures]
  end

  defp validate_scanner_posture(failures, %{} = posture) do
    failures
    |> require_present("refactor_missing_scanner_posture_ref", posture.proof_ref)
    |> require_nonempty_list("refactor_missing_scanner_commands", posture.required_commands)
    |> require_equal(
      "refactor_generic_duplicates_allowed",
      posture.retained_generic_duplicate_dispatch_allowed?,
      false
    )
  end

  defp validate_scanner_posture(failures, _posture) do
    [failure("refactor_missing_scanner_posture") | failures]
  end

  defp require_allowed_status(failures, _code, status) when status in @allowed_statuses,
    do: failures

  defp require_allowed_status(failures, code, status),
    do: [failure(code, status: inspect(status)) | failures]

  defp require_present(failures, _code, value) when is_binary(value) and value != "", do: failures

  defp require_present(failures, code, value),
    do: [failure(code, actual: inspect(value)) | failures]

  defp require_nonempty_list(failures, _code, [_ | _]), do: failures

  defp require_nonempty_list(failures, code, value),
    do: [failure(code, actual: inspect(value)) | failures]

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected),
    do: [failure(code, expected: inspect(expected), actual: inspect(actual)) | failures]

  defp failure(code, attrs \\ []), do: Map.new([{:code, code} | attrs])
end
