defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Scenarios.InstallIngestReviewTrace do
  @moduledoc false

  alias AppKit.Core.{
    ExecutionRef,
    InstallTemplate,
    OperatorActionRequest,
    PageRequest,
    RunRequest
  }

  alias AppKit.{InstallationSurface, OperatorSurface, ReviewSurface, WorkControl, WorkSurface}
  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.LowerFactsStub

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.{
    Environment,
    Fixtures,
    RepoSandbox
  }

  alias StackLab.CitadelSpineHarness.MezzanineOperationalStack

  import Environment
  import Fixtures
  import RepoSandbox

  def run do
    MezzanineOperationalStack.with_store(:app_kit_operational_surface, fn _repo_config ->
      tenant_id = "tenant-app-kit-operational"

      activate_fixture_registration!("1.0.0")

      %{program: program, work_class: work_class} = operational_fixture_stack(tenant_id)

      {:ok, page_request} = PageRequest.new(%{limit: 10})

      install_context =
        request_context(
          tenant_id,
          "trace/app-kit/install/#{System.unique_integer([:positive])}",
          %{program_id: program.id, work_class_id: work_class.id}
        )

      {:ok, install_template} =
        InstallTemplate.new(%{
          template_key: "expense-default",
          pack_slug: "expense_approval",
          pack_version: "1.0.0",
          default_bindings: %{
            "execution_bindings" => %{
              "expense_capture" => %{
                "placement_ref" => "local_docker"
              }
            }
          },
          metadata: %{"managed_by" => "stack_lab"}
        })

      surface_opts = surface_opts()

      {:ok, install_result} =
        InstallationSurface.create_installation(install_context, install_template, surface_opts)

      installation_ref = install_result.installation_ref

      with_installation_context =
        request_context(
          tenant_id,
          "trace/app-kit/work/#{System.unique_integer([:positive])}",
          %{program_id: program.id, work_class_id: work_class.id},
          installation_ref
        )

      {:ok, listed_installations} =
        InstallationSurface.list_installations(
          with_installation_context,
          page_request,
          surface_opts
        )

      {:ok, fetched_installation} =
        InstallationSurface.get_installation(
          with_installation_context,
          installation_ref,
          surface_opts
        )

      {:ok, subject_ref} =
        WorkSurface.ingest_subject(
          with_installation_context,
          %{
            external_ref: "linear:ENG-701",
            title: "Operational flow subject",
            payload: %{"issue_id" => "ENG-701"},
            source_kind: "linear"
          },
          surface_opts
        )

      {:ok, pre_run_detail} =
        WorkSurface.get_subject(with_installation_context, subject_ref, surface_opts)

      {:ok, listed_subjects} =
        WorkSurface.list_subjects(with_installation_context, page_request, surface_opts)

      {:ok, run_request} =
        RunRequest.new(%{
          subject_ref: subject_ref,
          recipe_ref: "expense_capture",
          params: %{"priority" => "high"}
        })

      {:ok, run_result} =
        WorkControl.start_run(with_installation_context, run_request, surface_opts)

      {:ok, subject_detail} =
        WorkSurface.get_subject(with_installation_context, subject_ref, surface_opts)

      {:ok, operator_projection} =
        OperatorSurface.subject_status(with_installation_context, subject_ref, surface_opts)

      {:ok, timeline} =
        OperatorSurface.timeline(with_installation_context, subject_ref, surface_opts)

      {:ok, actions} =
        OperatorSurface.available_actions(with_installation_context, subject_ref, surface_opts)

      chosen_action = choose_operator_action(actions)

      {:ok, action_request} =
        OperatorActionRequest.new(%{
          action_ref: chosen_action.action_ref,
          params: %{"reason" => "pause for review"}
        })

      {:ok, action_result} =
        OperatorSurface.apply_action(
          with_installation_context,
          subject_ref,
          action_request,
          surface_opts
        )

      {:ok, pending_reviews_before} =
        ReviewSurface.list_pending(with_installation_context, page_request, surface_opts)

      decision_ref = hd(pending_reviews_before.entries).decision_ref

      {:ok, review_detail_before} =
        ReviewSurface.get_review(with_installation_context, decision_ref, surface_opts)

      {:ok, review_action} =
        ReviewSurface.record_decision(
          with_installation_context,
          decision_ref,
          %{decision: :accept, reason: "approved by operator"},
          surface_opts
        )

      {:ok, pending_reviews_after} =
        ReviewSurface.list_pending(with_installation_context, page_request, surface_opts)

      {:ok, review_detail_after} =
        ReviewSurface.get_review(with_installation_context, decision_ref, surface_opts)

      {:ok, operator_projection_after_review} =
        OperatorSurface.subject_status(with_installation_context, subject_ref, surface_opts)

      trace_id = "trace/app-kit/unified/#{System.unique_integer([:positive])}"

      %{execution_id: execution_id} =
        seed_trace_ledger(installation_ref.id, subject_ref.id, trace_id)

      trace_context =
        request_context(
          tenant_id,
          trace_id,
          %{program_id: program.id, work_class_id: work_class.id},
          installation_ref
        )

      {:ok, execution_ref} =
        ExecutionRef.new(%{
          id: execution_id,
          subject_ref: subject_ref,
          recipe_ref: "expense_capture",
          dispatch_state: :accepted
        })

      {:ok, unified_trace} =
        OperatorSurface.get_unified_trace(
          trace_context,
          execution_ref,
          Keyword.put(surface_opts, :lower_facts, LowerFactsStub)
        )

      {:ok,
       %{
         case: :install_ingest_review_trace,
         tenant_id: tenant_id,
         installation: %{
           created_status: install_result.status,
           installation_id: installation_ref.id,
           pack_slug: installation_ref.pack_slug,
           fetched_status: fetched_installation.status,
           listed_ids: Enum.map(listed_installations.entries, & &1.id)
         },
         work: %{
           subject_id: subject_ref.id,
           listed_ids: Enum.map(listed_subjects.entries, & &1.subject_ref.id),
           pre_run_pending_obligation_ids:
             Enum.map(pre_run_detail.pending_obligations, & &1.obligation_id),
           pre_run_pending_decision_ref_ids:
             pre_run_detail.pending_obligations
             |> Enum.map(& &1.decision_ref_id)
             |> Enum.reject(&is_nil/1),
           pre_run_blocker_kinds: Enum.map(pre_run_detail.blocking_conditions, & &1.blocker_kind),
           pre_run_next_step_kind:
             pre_run_detail.next_step_preview && pre_run_detail.next_step_preview.step_kind,
           detail_active_run_id: payload_value(subject_detail, :active_run_id),
           detail_pending_reviews: Enum.map(subject_detail.pending_decision_refs, & &1.id),
           detail_pending_obligation_ids:
             Enum.map(subject_detail.pending_obligations, & &1.obligation_id),
           detail_pending_decision_ref_ids:
             subject_detail.pending_obligations
             |> Enum.map(& &1.decision_ref_id)
             |> Enum.reject(&is_nil/1),
           detail_blocker_kinds: Enum.map(subject_detail.blocking_conditions, & &1.blocker_kind),
           detail_next_step_kind:
             subject_detail.next_step_preview && subject_detail.next_step_preview.step_kind
         },
         control: %{
           state: run_result.state,
           run_id: run_result.payload.run_ref.run_id,
           review_unit_id: run_result.payload.review_unit_id
         },
         operator: %{
           lifecycle_state: operator_projection.lifecycle_state,
           current_run_id: payload_value(subject_detail, :active_run_id),
           current_execution_ref:
             operator_projection.current_execution_ref &&
               operator_projection.current_execution_ref.id,
           chosen_action: chosen_action.action_ref.action_kind,
           applied_action: action_result.action_ref.action_kind,
           timeline_kinds: Enum.map(timeline, & &1.event_kind),
           pending_obligation_ids:
             Enum.map(operator_projection.pending_obligations, & &1.obligation_id),
           pending_decision_ref_ids:
             operator_projection.pending_obligations
             |> Enum.map(& &1.decision_ref_id)
             |> Enum.reject(&is_nil/1),
           blocker_kinds: Enum.map(operator_projection.blocking_conditions, & &1.blocker_kind),
           next_step_kind:
             operator_projection.next_step_preview &&
               operator_projection.next_step_preview.step_kind
         },
         review: %{
           pending_ids_before: Enum.map(pending_reviews_before.entries, & &1.decision_ref.id),
           pending_ids_after: Enum.map(pending_reviews_after.entries, & &1.decision_ref.id),
           status_before: review_detail_before.status,
           status_after: review_detail_after.status,
           action_kind: review_action.action_ref.action_kind,
           blocker_kinds_after:
             Enum.map(operator_projection_after_review.blocking_conditions, & &1.blocker_kind),
           next_step_kind_after:
             operator_projection_after_review.next_step_preview &&
               operator_projection_after_review.next_step_preview.step_kind
         },
         trace: %{
           execution_id: execution_id,
           trace_id: unified_trace.trace_id,
           step_sources: Enum.map(unified_trace.steps, & &1.source)
         }
       }}
    end)
  end
end
