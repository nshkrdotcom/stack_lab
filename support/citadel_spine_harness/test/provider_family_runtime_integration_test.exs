defmodule StackLab.CitadelSpineHarness.ProviderFamilyRuntimeIntegrationTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness
  alias StackLab.CitadelSpineHarness.ProviderFamilyRuntimeIntegration

  test "describes the Phase 6 provider-family runtime integration release gate" do
    scenario = CitadelSpineHarness.provider_family_runtime_integration_scenario()

    assert scenario.name == :phase6_provider_family_runtime_integration
    assert scenario.runbook == "provider_family_runtime_validation.md"
    assert scenario.scenario == 606
    assert scenario.consumer_repo == :stack_lab

    assert scenario.owner_repos == [
             :agent_session_manager,
             :cli_subprocess_core,
             :pristine,
             :prismatic,
             :self_hosted_inference_core
           ]

    assert scenario.provider_sdk_repos == [
             :codex_sdk,
             :gemini_cli_sdk,
             :claude_agent_sdk,
             :amp_sdk,
             :notion_sdk,
             :github_ex,
             :linear_sdk,
             :llama_cpp_sdk
           ]

    assert scenario.cases == %{
             provider_family_runtime_integration: %{
               kind: :provider_family_runtime_integration,
               scenario: 606
             }
           }
  end

  test "composes provider-family owner evidence without provider-local mock dependence" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_provider_family_runtime_integration(
               :provider_family_runtime_integration
             )

    assert result.case == :provider_family_runtime_integration
    assert result.scenario == 606
    assert result.stack_lab_role == :release_gate_evidence_composer_not_owner

    assert result.service_mode_gate.cli_common_path_consumed?
    assert result.service_mode_gate.scenario_606_forbidden_selectors_rejected?
    assert result.service_mode_gate.rest_graphql_owner_paths_consumed?
    assert result.service_mode_gate.self_hosted_owner_path_consumed?
    assert result.service_mode_gate.no_egress_negative_evidence_present?
    assert result.service_mode_gate.provider_sdk_runtime_switch_reintroduction_rejected?
    assert result.service_mode_gate.bounded_evidence_schema_conformant?

    assert result.cli_family.adapter_policy.owner_repo == "cli_subprocess_core"

    assert result.cli_family.adapter_policy.config_key ==
             "cli_subprocess_core.provider_runtime_profiles"

    assert result.cli_family.asm_policy.owner_repo == "agent_session_manager"
    assert result.cli_family.asm_policy.selection_surface == "provider_registry"

    assert Enum.map(result.cli_family.providers, & &1.provider) ==
             [:claude, :codex, :gemini, :amp]

    assert Enum.all?(result.cli_family.providers, fn provider_evidence ->
             provider_evidence.public_call == "ASM.query/3" and
               provider_evidence.backend == "ASM.ProviderBackend.Core" and
               provider_evidence.lane == :core and
               provider_evidence.profile_mode == :lower_simulation and
               provider_evidence.profile_source == :cli_subprocess_core_config and
               provider_evidence.lower_scenario.owner_repo == "cli_subprocess_core" and
               provider_evidence.lower_scenario.protocol_surface == "process" and
               provider_evidence.lower_scenario.no_egress_assertion["external_egress"] ==
                 "deny" and
               provider_evidence.lower_scenario.no_egress_assertion["process_spawn"] == "deny"
           end)

    assert result.cli_family.negative_failures.required_profile ==
             {:provider_runtime_profile_required_before_spawn, :claude}

    assert result.cli_family.negative_failures.explicit_sdk_lane ==
             :provider_runtime_profile_blocks_sdk_lane

    assert result.cli_family.negative_failures.backend_override ==
             :provider_runtime_profile_blocks_backend_override

    assert result.scenario_606_boundary.forbidden_selectors == [
             "ClaudeAgentSDK.Mock",
             "ClaudeAgentSDK.Mock.Process",
             "GEMINI_CLI_PATH",
             "AMP_CLI_PATH",
             "Codex fixture scripts"
           ]

    assert result.scenario_606_boundary.negative_failures["ClaudeAgentSDK.Mock"] ==
             {:provider_local_mock_selector_forbidden, "ClaudeAgentSDK.Mock"}

    assert result.scenario_606_boundary.negative_failures["GEMINI_CLI_PATH"] ==
             {:provider_local_mock_selector_forbidden, "GEMINI_CLI_PATH"}

    assert result.rest_graphql.rest.owner_repo == "pristine"
    assert result.rest_graphql.rest.consumer_sdks == [:notion_sdk, :github_ex]

    assert result.rest_graphql.rest.adapter_policy.config_key ==
             "pristine.transport_simulation_profiles"

    assert result.rest_graphql.rest.lower_scenario.protocol_surface == "http"

    assert result.rest_graphql.rest.negative_failures.missing_profile ==
             {:pristine_simulation_profile_required, ["notion.databases.query", :default]}

    assert result.rest_graphql.rest.negative_failures.public_selector ==
             {:public_simulation_selector_forbidden, :pristine}

    assert result.rest_graphql.graphql.owner_repo == "prismatic"
    assert result.rest_graphql.graphql.consumer_sdks == [:linear_sdk]

    assert result.rest_graphql.graphql.adapter_policy.config_key ==
             "prismatic.graphql_simulation_profiles"

    assert result.rest_graphql.graphql.lower_scenario.protocol_surface == "graphql"

    assert result.rest_graphql.graphql.negative_failures.missing_profile ==
             {:prismatic_simulation_profile_required,
              ["LinearIssue", "operation:LinearIssue", "anonymous", :default]}

    assert result.rest_graphql.graphql.negative_failures.public_selector ==
             {:public_simulation_selector_forbidden, :prismatic}

    assert result.self_hosted.owner_repo == "self_hosted_inference_core"
    assert result.self_hosted.adapter_policy.selection_surface == "backend_manifest"
    assert result.self_hosted.lower_scenario.protocol_surface == "self_hosted"
    assert result.self_hosted.endpoint.provider_identity == :self_hosted_simulation

    assert result.self_hosted.llama_cpp_sdk.role ==
             :real_llama_server_consumer_not_simulation_owner

    assert result.self_hosted.negative_failures.boot_spec ==
             {:simulation_backend_bypass_denied, :boot_spec}

    assert result.self_hosted.negative_failures.local_subprocess ==
             {:simulation_backend_bypass_denied, {:execution_surface, :local_subprocess}}

    assert result.no_egress.policy == :deny_real_provider_and_saas
    assert result.no_egress.provider_spend_cents == 0
    assert result.no_egress.external_write_refs == []

    assert result.no_egress.denied_attempts.unregistered_provider_route ==
             {:external_egress_denied, "api.openai.com"}

    assert result.no_egress.denied_attempts.raw_external_saas_write ==
             {:external_write_denied, "api.notion.com"}

    assert result.provider_sdk_fixture_inventory.claude_agent_sdk.scope ==
             :package_test_only_quarantined

    assert result.provider_sdk_fixture_inventory.claude_agent_sdk.global_runtime_switch_reintroduced? ==
             false

    assert result.provider_sdk_fixture_inventory.codex_sdk.scope == :package_fixture_only
    assert result.provider_sdk_fixture_inventory.gemini_cli_sdk.scope == :package_fixture_only
    assert result.provider_sdk_fixture_inventory.amp_sdk.scope == :package_fixture_only
    assert result.provider_sdk_fixture_inventory.llama_cpp_sdk.scope == :real_backend_consumer

    assert result.evidence_schema.contract_version ==
             "ExecutionPlane.LowerSimulationEvidence.v1"

    assert result.evidence_schema.raw_payload_persistence == :shape_only
    refute result.evidence_schema.raw_prompts_persisted?
    refute result.evidence_schema.provider_bodies_persisted?
    refute result.evidence_schema.workflow_histories_persisted?

    assert :ok = ProviderFamilyRuntimeIntegration.validate_service_mode_proof(result)
  end

  test "service-mode proof validation rejects M9 bypass and raw-payload regressions" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_provider_family_runtime_integration(
               :provider_family_runtime_integration
             )

    assert {:error, {:provider_local_mock_selector_forbidden, "ClaudeAgentSDK.Mock"}} =
             result
             |> put_in([:scenario_606_boundary, :used_selectors], ["ClaudeAgentSDK.Mock"])
             |> ProviderFamilyRuntimeIntegration.validate_service_mode_proof()

    assert {:error, {:public_simulation_selector_forbidden, :pristine}} =
             result
             |> put_in([:rest_graphql, :rest, :adapter_policy, :config_key], "request.simulation")
             |> ProviderFamilyRuntimeIntegration.validate_service_mode_proof()

    assert {:error, {:no_egress_negative_missing, :raw_external_saas_write}} =
             result
             |> put_in([:no_egress, :denied_attempts, :raw_external_saas_write], :allowed)
             |> ProviderFamilyRuntimeIntegration.validate_service_mode_proof()

    assert {:error, {:self_hosted_simulation_owner_invalid, "llama_cpp_sdk"}} =
             result
             |> put_in([:self_hosted, :owner_repo], "llama_cpp_sdk")
             |> ProviderFamilyRuntimeIntegration.validate_service_mode_proof()

    assert {:error, {:raw_payload_persistence_forbidden, :raw_provider_body}} =
             result
             |> put_in([:evidence_schema, :raw_provider_body], "leaked body")
             |> ProviderFamilyRuntimeIntegration.validate_service_mode_proof()
  end
end
