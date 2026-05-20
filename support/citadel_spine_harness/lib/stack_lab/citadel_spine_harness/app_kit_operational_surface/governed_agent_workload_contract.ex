defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Scenarios.GovernedAgentWorkloadContract do
  @moduledoc false

  alias AppKit.Core.{PageRequest, RunRequest}
  alias AppKit.{InstallationSurface, OperatorSurface, ReviewSurface, WorkControl, WorkSurface}
  alias AppKit.RunGovernance

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.{
    Environment,
    Fixtures
  }

  alias StackLab.CitadelSpineHarness.MezzanineOperationalStack

  import Environment
  import Fixtures

  def run do
    MezzanineOperationalStack.with_store(:app_kit_governed_agent_workload, fn _repo_config ->
      tenant_id = "tenant-app-kit-governed-workload"

      activate_governed_workload_registration!()

      %{program: program, work_class: work_class} = governed_workload_fixture_stack(tenant_id)

      {:ok, page_request} = PageRequest.new(%{limit: 10})
      {:ok, workload} = RunGovernance.governed_agent_workload(governed_workload_attrs())

      install_context =
        request_context(
          tenant_id,
          "trace/app-kit/governed/install/#{System.unique_integer([:positive])}",
          %{program_id: program.id, work_class_id: work_class.id}
        )

      surface_opts = surface_opts()

      {:ok, install_result} =
        InstallationSurface.create_installation(
          install_context,
          governed_workload_install_template!(),
          surface_opts
        )

      installation_ref = install_result.installation_ref

      context =
        request_context(
          tenant_id,
          "trace/app-kit/governed/work/#{System.unique_integer([:positive])}",
          %{program_id: program.id, work_class_id: work_class.id},
          installation_ref
        )

      {:ok, subject_ref} =
        WorkSurface.ingest_subject(
          context,
          %{
            external_ref: "linear:ENG-901",
            title: "Governed coding operation",
            payload: %{"issue_id" => "ENG-901"},
            source_kind: "linear"
          },
          surface_opts
        )

      {:ok, run_request} =
        RunRequest.new(%{
          subject_ref: subject_ref,
          recipe_ref: "service_operations",
          params: %{"priority" => "high"}
        })

      {:ok, run_result} = WorkControl.start_run(context, run_request, surface_opts)
      {:ok, subject_detail} = WorkSurface.get_subject(context, subject_ref, surface_opts)

      {:ok, operator_projection} =
        OperatorSurface.subject_status(context, subject_ref, surface_opts)

      {:ok, pending_reviews_before} =
        ReviewSurface.list_pending(context, page_request, surface_opts)

      decision_ref = hd(pending_reviews_before.entries).decision_ref

      {:ok, review_detail_before} =
        ReviewSurface.get_review(context, decision_ref, surface_opts)

      {:ok, review_action} =
        ReviewSurface.record_decision(
          context,
          decision_ref,
          %{decision: :accept, reason: "approved by operator"},
          surface_opts
        )

      {:ok, pending_reviews_after} =
        ReviewSurface.list_pending(context, page_request, surface_opts)

      {:ok, review_detail_after} = ReviewSurface.get_review(context, decision_ref, surface_opts)

      {:error, bare_asm_substitute_rejection} =
        RunGovernance.governed_agent_workload(bare_asm_substitute_attrs())

      {:ok,
       %{
         case: :governed_agent_workload_contract,
         tenant_id: tenant_id,
         governed_workload: governed_workload_summary(workload),
         installation: %{
           created_status: install_result.status,
           installation_id: installation_ref.id,
           pack_slug: installation_ref.pack_slug
         },
         work: %{
           subject_id: subject_ref.id,
           detail_active_run_id: payload_value(subject_detail, :active_run_id),
           detail_pending_reviews: Enum.map(subject_detail.pending_decision_refs, & &1.id),
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
           blocker_kinds: Enum.map(operator_projection.blocking_conditions, & &1.blocker_kind),
           pending_decision_ref_ids:
             operator_projection.pending_obligations
             |> Enum.map(& &1.decision_ref_id)
             |> Enum.reject(&is_nil/1)
         },
         review: %{
           pending_ids_before: Enum.map(pending_reviews_before.entries, & &1.decision_ref.id),
           pending_ids_after: Enum.map(pending_reviews_after.entries, & &1.decision_ref.id),
           status_before: review_detail_before.status,
           status_after: review_detail_after.status,
           action_kind: review_action.action_ref.action_kind
         },
         lifecycle: %{
           states: workload.lifecycle_states,
           transition_paths: RunGovernance.lifecycle_transition_paths(workload)
         },
         scale_pressure_seed: RunGovernance.scale_pressure_seed(workload),
         bare_asm_substitute_rejection: bare_asm_substitute_rejection,
         task_async_stream_substitute?: false
       }}
    end)
  end
end
