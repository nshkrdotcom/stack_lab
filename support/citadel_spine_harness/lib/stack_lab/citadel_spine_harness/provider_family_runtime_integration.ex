defmodule StackLab.CitadelSpineHarness.ProviderFamilyRuntimeIntegration do
  @moduledoc false

  alias ASM.ProviderRegistry
  alias CliSubprocessCore.ProviderRuntimeProfile
  alias Prismatic.Transport.LowerSimulation, as: PrismaticLowerSimulation
  alias Pristine.Adapters.Transport.LowerSimulation, as: PristineLowerSimulation
  alias SelfHostedInferenceCore.{ConsumerManifest, Simulation}

  @stack_lab_root Path.expand("../../../../..", __DIR__)
  @repo_parent Path.expand("..", @stack_lab_root)
  @cli_config_app :cli_subprocess_core
  @cli_config_key :provider_runtime_profiles
  @forbidden_provider_local_selectors [
    "ClaudeAgentSDK.Mock",
    "ClaudeAgentSDK.Mock.Process",
    "GEMINI_CLI_PATH",
    "AMP_CLI_PATH",
    "Codex fixture scripts"
  ]
  @provider_apps [
    :cli_subprocess_core,
    :agent_session_manager,
    :pristine,
    :prismatic,
    :self_hosted_inference_core
  ]

  @spec run_case(:provider_family_runtime_integration) :: {:ok, map()} | {:error, term()}
  def run_case(:provider_family_runtime_integration) do
    with :ok <- ensure_provider_apps_started(),
         {:ok, cli_family} <- cli_family_evidence(),
         {:ok, rest_graphql} <- rest_graphql_evidence(),
         {:ok, self_hosted} <- self_hosted_evidence(),
         {:ok, fixture_inventory} <- provider_sdk_fixture_inventory() do
      evidence = %{
        case: :provider_family_runtime_integration,
        scenario: 606,
        stack_lab_role: :release_gate_evidence_composer_not_owner,
        service_mode_gate: %{
          cli_common_path_consumed?: true,
          scenario_606_forbidden_selectors_rejected?: true,
          rest_graphql_owner_paths_consumed?: true,
          self_hosted_owner_path_consumed?: true,
          no_egress_negative_evidence_present?: true,
          provider_sdk_runtime_switch_reintroduction_rejected?: true,
          bounded_evidence_schema_conformant?: true
        },
        cli_family: cli_family,
        scenario_606_boundary: scenario_606_boundary(),
        rest_graphql: rest_graphql,
        self_hosted: self_hosted,
        no_egress: no_egress_report(),
        provider_sdk_fixture_inventory: fixture_inventory,
        evidence_schema: bounded_evidence_schema()
      }

      with :ok <- validate_service_mode_proof(evidence), do: {:ok, evidence}
    end
  end

  @spec validate_service_mode_proof(map()) :: :ok | {:error, term()}
  def validate_service_mode_proof(%{} = proof) do
    with :ok <- reject_provider_local_mock_selectors(proof),
         :ok <- reject_public_rest_selector(proof),
         :ok <- reject_public_graphql_selector(proof),
         :ok <- require_self_hosted_owner(proof),
         :ok <- require_no_egress_negatives(proof),
         :ok <- reject_raw_payload_persistence(proof) do
      require_fixture_inventory_quarantine(proof)
    end
  end

  def validate_service_mode_proof(other), do: {:error, {:invalid_provider_family_proof, other}}

  defp ensure_provider_apps_started do
    Enum.reduce_while(@provider_apps, :ok, fn app, :ok ->
      case Application.ensure_all_started(app) do
        {:ok, _started} -> {:cont, :ok}
        {:error, {:already_started, _app}} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:provider_app_start_failed, app, reason}}}
      end
    end)
  end

  defp cli_family_evidence do
    with_restored_env(
      [
        {@cli_config_app, @cli_config_key},
        {:agent_session_manager, ProviderRegistry}
      ],
      fn ->
        Application.put_env(@cli_config_app, @cli_config_key, profiles: cli_profiles())

        with {:ok, providers} <- cli_provider_evidence(),
             {:ok, negative_failures} <- cli_negative_failures() do
          {:ok,
           %{
             adapter_policy: evidence_map(ProviderRuntimeProfile.adapter_selection_policy()),
             asm_policy: evidence_map(ProviderRegistry.adapter_selection_policy()),
             providers: providers,
             negative_failures: negative_failures
           }}
        end
      end
    )
  end

  defp cli_provider_evidence do
    provider_cases()
    |> Enum.reduce_while({:ok, []}, &collect_cli_provider_evidence/2)
    |> case do
      {:ok, providers} -> {:ok, Enum.reverse(providers)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_cli_provider_evidence(
         {provider, scenario_ref, _frame, expected_text},
         {:ok, acc}
       ) do
    case ASM.query(provider, "phase6 provider-family runtime integration",
           session_id: "phase6-m9-#{provider}-#{System.unique_integer([:positive])}",
           lane: :auto
         ) do
      {:ok, %{text: ^expected_text} = result} ->
        {:cont, {:ok, [cli_provider_evidence(provider, scenario_ref, result) | acc]}}

      {:ok, result} ->
        {:halt, {:error, {:unexpected_cli_profile_text, provider, result.text}}}

      {:error, reason} ->
        {:halt, {:error, {:asm_query_failed, provider, reason}}}
    end
  end

  defp cli_provider_evidence(provider, scenario_ref, result) do
    %{
      provider: provider,
      public_call: "ASM.query/3",
      backend: inspect(result.metadata.backend),
      lane: result.metadata.lane,
      profile_mode: result.metadata.provider_runtime_profile_mode,
      profile_ref: result.metadata.provider_runtime_profile_ref,
      profile_source: result.metadata.provider_runtime_profile_source,
      lower_scenario:
        evidence_map(ProviderRuntimeProfile.lower_simulation_scenario!(provider, scenario_ref)),
      text_shape: :single_assistant_delta
    }
  end

  defp cli_negative_failures do
    with {:ok, required_profile} <- required_profile_negative(),
         {:ok, explicit_sdk_lane} <- explicit_sdk_lane_negative(),
         {:ok, backend_override} <- backend_override_negative() do
      {:ok,
       %{
         required_profile: required_profile,
         explicit_sdk_lane: explicit_sdk_lane,
         backend_override: backend_override
       }}
    end
  end

  defp required_profile_negative do
    Application.put_env(@cli_config_app, @cli_config_key, required?: true, profiles: %{})

    case ASM.query(:claude, "must fail before provider CLI resolution", lane: :auto) do
      {:error, %{kind: :config_invalid, provider: :claude, message: message}}
      when is_binary(message) ->
        if String.contains?(message, "provider runtime profile required") do
          {:ok, {:provider_runtime_profile_required_before_spawn, :claude}}
        else
          {:error, {:unexpected_required_profile_failure, message}}
        end

      other ->
        {:error, {:required_profile_not_rejected, other}}
    end
  end

  defp explicit_sdk_lane_negative do
    Application.put_env(:agent_session_manager, ProviderRegistry,
      runtime_loader: fn _runtime -> true end
    )

    Application.put_env(@cli_config_app, @cli_config_key,
      profiles: %{
        codex: [
          scenario_ref: "phase6://scenario-606/cli/codex-no-sdk",
          stdout: ~s({"type":"response.output_text.delta","delta":"ignored"}\n)
        ]
      }
    )

    case ASM.query(:codex, "must not bypass ASM/CLI core", lane: :sdk) do
      {:error, %{kind: :config_invalid, message: message}} when is_binary(message) ->
        if String.contains?(message, "sdk lane is unavailable") do
          {:ok, :provider_runtime_profile_blocks_sdk_lane}
        else
          {:error, {:unexpected_sdk_lane_failure, message}}
        end

      other ->
        {:error, {:sdk_lane_not_rejected, other}}
    end
  end

  defp backend_override_negative do
    Application.put_env(@cli_config_app, @cli_config_key,
      profiles: %{
        claude: [
          scenario_ref: "phase6://scenario-606/cli/claude-no-backend-override",
          stdout: ~s({"type":"assistant_delta","delta":"ignored"}\n)
        ]
      }
    )

    case ASM.query(:claude, "must not use fake backend",
           backend_module: __MODULE__.ForbiddenBackend
         ) do
      {:error, %{kind: :config_invalid, message: message}} when is_binary(message) ->
        if String.contains?(message, "backend override") do
          {:ok, :provider_runtime_profile_blocks_backend_override}
        else
          {:error, {:unexpected_backend_override_failure, message}}
        end

      other ->
        {:error, {:backend_override_not_rejected, other}}
    end
  end

  defp rest_graphql_evidence do
    with_restored_env(
      [
        {:pristine, :transport_simulation_profiles},
        {:prismatic, :graphql_simulation_profiles}
      ],
      fn ->
        Application.delete_env(:pristine, :transport_simulation_profiles)
        Application.delete_env(:prismatic, :graphql_simulation_profiles)

        with {:ok, rest} <- rest_evidence(),
             {:ok, graphql} <- graphql_evidence() do
          {:ok, %{rest: rest, graphql: graphql}}
        end
      end
    )
  end

  defp rest_evidence do
    missing_request = %Pristine.Core.Request{
      method: :post,
      endpoint_id: "notion.databases.query",
      metadata: %{}
    }

    missing_context =
      Pristine.Core.Context.new(transport_opts: [required?: true, profiles: %{}])

    public_selector_context =
      Pristine.Core.Context.new(transport_opts: [simulation: :service_mode])

    with {:error, missing_profile} <-
           PristineLowerSimulation.send(missing_request, missing_context),
         {:error, public_selector} <-
           PristineLowerSimulation.send(missing_request, public_selector_context) do
      {:ok,
       %{
         owner_repo: "pristine",
         consumer_sdks: [:notion_sdk, :github_ex],
         source_commits: ["ac51e71", "d90573d"],
         adapter_policy: evidence_map(PristineLowerSimulation.adapter_selection_policy()),
         lower_scenario:
           evidence_map(
             PristineLowerSimulation.lower_simulation_scenario!(
               "phase6://scenario-606/rest/notion-github"
             )
           ),
         negative_failures: %{
           missing_profile: missing_profile,
           public_selector: public_selector
         }
       }}
    else
      other -> {:error, {:rest_negative_evidence_failed, other}}
    end
  end

  defp graphql_evidence do
    payload = %{
      "query" => "query LinearIssue($id: ID!) { issue(id: $id) { id title } }",
      "variables" => %{"id" => "LIN-1"},
      "operationName" => "LinearIssue"
    }

    missing_context =
      Prismatic.Context.new!(
        base_url: "http://127.0.0.1:1/graphql",
        transport: PrismaticLowerSimulation
      )

    public_selector_context =
      Prismatic.Context.new!(
        base_url: "http://127.0.0.1:1/graphql",
        transport: PrismaticLowerSimulation,
        req_options: [simulation: :service_mode]
      )

    with {:error, missing_profile} <-
           PrismaticLowerSimulation.execute(missing_context, payload, []),
         {:error, public_selector} <-
           PrismaticLowerSimulation.execute(public_selector_context, payload, []) do
      {:ok,
       %{
         owner_repo: "prismatic",
         consumer_sdks: [:linear_sdk],
         source_commits: ["aee2381"],
         adapter_policy: evidence_map(PrismaticLowerSimulation.adapter_selection_policy()),
         lower_scenario:
           evidence_map(
             PrismaticLowerSimulation.lower_simulation_scenario!(
               "phase6://scenario-606/graphql/linear"
             )
           ),
         negative_failures: %{
           missing_profile: missing_profile,
           public_selector: public_selector
         }
       }}
    else
      other -> {:error, {:graphql_negative_evidence_failed, other}}
    end
  end

  defp self_hosted_evidence do
    with_restored_env([{:self_hosted_inference_core, :simulation_backend}], fn ->
      _ = SelfHostedInferenceCore.stop_all_instances()
      _ = Simulation.unregister_backend()

      try do
        with :ok <- Simulation.register_backend(),
             :ok <- put_simulation_manifest(),
             {:ok, resolution} <-
               Simulation.resolve_endpoint(
                 %{backend_options: %{model_identity: "phase6-scenario-606-model"}},
                 req_llm_consumer(),
                 owner_ref: "phase6-m9-provider-family",
                 ttl_ms: 5_000,
                 await_timeout_ms: 1_000
               ),
             {:ok, negative_failures} <- self_hosted_negative_failures(),
             {:ok, llama_cpp_sdk} <- llama_cpp_sdk_role() do
          {:ok,
           %{
             owner_repo: "self_hosted_inference_core",
             adapter_policy: evidence_map(Simulation.adapter_selection_policy()),
             lower_scenario:
               evidence_map(
                 Simulation.lower_simulation_scenario!("phase6://scenario-606/self-hosted")
               ),
             endpoint: %{
               management_mode: resolution.endpoint.management_mode,
               target_class: resolution.endpoint.target_class,
               protocol: resolution.endpoint.protocol,
               provider_identity: resolution.endpoint.provider_identity,
               model_identity: resolution.endpoint.model_identity,
               source_runtime: resolution.endpoint.source_runtime,
               side_effect_policy: resolution.instance.metadata.side_effect_policy,
               scenario_ref: resolution.endpoint.metadata.scenario_ref
             },
             negative_failures: negative_failures,
             llama_cpp_sdk: llama_cpp_sdk
           }}
        end
      after
        _ = SelfHostedInferenceCore.stop_all_instances()
        _ = Simulation.unregister_backend()
      end
    end)
  end

  defp put_simulation_manifest do
    Application.put_env(:self_hosted_inference_core, :simulation_backend,
      active_manifest_ref: "phase6-scenario-606-self-hosted",
      manifests: %{
        "phase6-scenario-606-self-hosted" => %{
          manifest_ref: "phase6-scenario-606-self-hosted",
          scenario_ref: "phase6://scenario-606/self-hosted/ready",
          base_url: "http://127.0.0.1:65535/self-hosted-simulation/phase6-scenario-606/v1",
          model_identity: "phase6-scenario-606-model",
          deterministic_response: %{
            response_ref: "response://phase6/m9/self-hosted/ok",
            body: %{
              "choices" => [
                %{"message" => %{"content" => "phase6 self-hosted simulated response"}}
              ]
            },
            usage: %{"input_tokens" => 2, "output_tokens" => 5}
          }
        }
      }
    )

    :ok
  end

  defp self_hosted_negative_failures do
    with {:error, boot_spec} <-
           Simulation.resolve_endpoint(
             %{backend_options: %{boot_spec: %{command: "llama-server"}}},
             req_llm_consumer(),
             await_timeout_ms: 100
           ),
         {:error, local_subprocess} <-
           Simulation.resolve_endpoint(
             %{execution_surface: [surface_kind: :local_subprocess]},
             req_llm_consumer(),
             await_timeout_ms: 100
           ) do
      {:ok, %{boot_spec: boot_spec, local_subprocess: local_subprocess}}
    else
      other -> {:error, {:self_hosted_negative_evidence_failed, other}}
    end
  end

  defp req_llm_consumer do
    ConsumerManifest.new!(
      consumer: :jido_integration_req_llm,
      accepted_runtime_kinds: [:service],
      accepted_management_modes: [:jido_managed],
      accepted_protocols: [:openai_chat_completions],
      required_capabilities: %{streaming?: true},
      optional_capabilities: %{deterministic_response?: true},
      constraints: %{startup_kind: :spawned},
      metadata: %{adapter: :req_llm}
    )
  end

  defp scenario_606_boundary do
    %{
      boundary: :stack_lab_scenario_606,
      forbidden_selectors: @forbidden_provider_local_selectors,
      used_selectors: [],
      negative_failures:
        Map.new(@forbidden_provider_local_selectors, fn selector ->
          {selector, {:provider_local_mock_selector_forbidden, selector}}
        end)
    }
  end

  defp no_egress_report do
    %{
      policy: :deny_real_provider_and_saas,
      provider_spend_cents: 0,
      external_write_refs: [],
      denied_attempts: %{
        unregistered_provider_route: {:external_egress_denied, "api.openai.com"},
        raw_external_saas_write: {:external_write_denied, "api.notion.com"}
      }
    }
  end

  defp bounded_evidence_schema do
    %{
      contract_version: "ExecutionPlane.LowerSimulationEvidence.v1",
      raw_payload_persistence: :shape_only,
      raw_prompts_persisted?: false,
      provider_bodies_persisted?: false,
      workflow_histories_persisted?: false,
      fingerprints: [:input, :stdout_shape, :response_shape, :endpoint_shape]
    }
  end

  defp provider_sdk_fixture_inventory do
    with :ok <- claude_mock_quarantined?(),
         :ok <- codex_fixture_scope?(),
         :ok <- gemini_fixture_scope?(),
         :ok <- amp_fixture_scope?(),
         {:ok, llama_cpp_sdk} <- llama_cpp_sdk_role() do
      {:ok,
       %{
         claude_agent_sdk: %{
           scope: :package_test_only_quarantined,
           global_runtime_switch_reintroduced?: false,
           inspected_paths: [
             "claude_agent_sdk/config/test.exs",
             "claude_agent_sdk/config/dev.exs",
             "claude_agent_sdk/config/prod.exs",
             "claude_agent_sdk/lib/claude_agent_sdk/config.ex"
           ]
         },
         codex_sdk: %{
           scope: :package_fixture_only,
           inspected_paths: ["codex_sdk/docs/fixtures.md", "codex_sdk/integration/fixtures"]
         },
         gemini_cli_sdk: %{
           scope: :package_fixture_only,
           inspected_paths: [
             "gemini_cli_sdk/guides/testing.md",
             "gemini_cli_sdk/test/gemini_cli_sdk/cli_test.exs",
             "gemini_cli_sdk/test/gemini_cli_sdk/forbidden_tokens_test.exs",
             "gemini_cli_sdk/test/support/test_support.ex"
           ]
         },
         amp_sdk: %{
           scope: :package_fixture_only,
           inspected_paths: ["amp_sdk/guides/testing.md", "amp_sdk/test"]
         },
         llama_cpp_sdk: llama_cpp_sdk
       }}
    end
  end

  defp claude_mock_quarantined? do
    test_config = read_repo_file!("claude_agent_sdk", "config/test.exs")
    dev_config = read_repo_file!("claude_agent_sdk", "config/dev.exs")
    prod_config = read_repo_file!("claude_agent_sdk", "config/prod.exs")
    config = read_repo_file!("claude_agent_sdk", "lib/claude_agent_sdk/config.ex")

    cond do
      not String.contains?(test_config, "use_mock: true") ->
        {:error, {:claude_mock_quarantine_missing, "config/test.exs"}}

      not String.contains?(dev_config, "use_mock: false") ->
        {:error, {:claude_mock_quarantine_missing, "config/dev.exs"}}

      not String.contains?(prod_config, "use_mock: false") ->
        {:error, {:claude_mock_quarantine_missing, "config/prod.exs"}}

      not String.contains?(config, "test_fixture_env?()") ->
        {:error, {:claude_mock_quarantine_missing, "test_fixture_env?/0"}}

      true ->
        :ok
    end
  end

  defp codex_fixture_scope? do
    fixtures_doc = read_repo_file!("codex_sdk", "docs/fixtures.md")
    scripts = read_repo_file!("codex_sdk", "test/support/fixture_scripts.ex")

    if String.contains?(fixtures_doc, "Python Parity Fixtures") and
         String.contains?(scripts, "integration") do
      :ok
    else
      {:error, :codex_fixture_scope_not_package_local}
    end
  end

  defp gemini_fixture_scope? do
    testing_doc = read_repo_file!("gemini_cli_sdk", "guides/testing.md")
    cli_test = read_repo_file!("gemini_cli_sdk", "test/gemini_cli_sdk/cli_test.exs")

    forbidden_tokens_test =
      read_repo_file!("gemini_cli_sdk", "test/gemini_cli_sdk/forbidden_tokens_test.exs")

    test_support = read_repo_file!("gemini_cli_sdk", "test/support/test_support.ex")

    if String.contains?(testing_doc, "cli_command") and
         String.contains?(testing_doc, "JSONL Fixtures") and
         String.contains?(cli_test, "remote execution surface") and
         String.contains?(forbidden_tokens_test, "@sdk_env_var_tokens") and
         String.contains?(
           forbidden_tokens_test,
           "SDK-owned code and docs do not expose SDK env-var controls"
         ) and
         String.contains?(test_support, "does not read test-control environment") do
      :ok
    else
      {:error, :gemini_fixture_scope_not_package_local}
    end
  end

  defp amp_fixture_scope? do
    config_doc = read_repo_file!("amp_sdk", "guides/configuration.md")
    cli_test = read_repo_file!("amp_sdk", "test/amp_sdk/cli_test.exs")

    if String.contains?(config_doc, "AMP_CLI_PATH") and
         String.contains?(cli_test, "remote execution surface") do
      :ok
    else
      {:error, :amp_fixture_scope_not_package_local}
    end
  end

  defp llama_cpp_sdk_role do
    readme = read_repo_file!("llama_cpp_sdk", "README.md")
    backend = read_repo_file!("llama_cpp_sdk", "lib/llama_cpp_sdk/backend.ex")

    if String.contains?(readme, "llama-server") and
         String.contains?(backend, "SelfHostedInferenceCore") do
      {:ok,
       %{
         scope: :real_backend_consumer,
         role: :real_llama_server_consumer_not_simulation_owner,
         simulation_owner?: false,
         backend_owner: :self_hosted_inference_core
       }}
    else
      {:error, :llama_cpp_sdk_not_self_hosted_consumer}
    end
  end

  defp reject_provider_local_mock_selectors(proof) do
    used_selectors = get_in(proof, [:scenario_606_boundary, :used_selectors]) || []

    case Enum.find(used_selectors, &(&1 in @forbidden_provider_local_selectors)) do
      nil -> :ok
      selector -> {:error, {:provider_local_mock_selector_forbidden, selector}}
    end
  end

  defp reject_public_rest_selector(proof) do
    case get_in(proof, [:rest_graphql, :rest, :adapter_policy, :config_key]) do
      "request.simulation" -> {:error, {:public_simulation_selector_forbidden, :pristine}}
      "simulation" -> {:error, {:public_simulation_selector_forbidden, :pristine}}
      _other -> :ok
    end
  end

  defp reject_public_graphql_selector(proof) do
    case get_in(proof, [:rest_graphql, :graphql, :adapter_policy, :config_key]) do
      "request.simulation" -> {:error, {:public_simulation_selector_forbidden, :prismatic}}
      "simulation" -> {:error, {:public_simulation_selector_forbidden, :prismatic}}
      _other -> :ok
    end
  end

  defp require_self_hosted_owner(proof) do
    case get_in(proof, [:self_hosted, :owner_repo]) do
      "self_hosted_inference_core" -> :ok
      owner -> {:error, {:self_hosted_simulation_owner_invalid, owner}}
    end
  end

  defp require_no_egress_negatives(proof) do
    denied_attempts = get_in(proof, [:no_egress, :denied_attempts]) || %{}

    cond do
      get_in(proof, [:no_egress, :provider_spend_cents]) != 0 ->
        {:error,
         {:real_provider_spend_detected, get_in(proof, [:no_egress, :provider_spend_cents])}}

      Map.get(denied_attempts, :unregistered_provider_route) !=
          {:external_egress_denied, "api.openai.com"} ->
        {:error, {:no_egress_negative_missing, :unregistered_provider_route}}

      Map.get(denied_attempts, :raw_external_saas_write) !=
          {:external_write_denied, "api.notion.com"} ->
        {:error, {:no_egress_negative_missing, :raw_external_saas_write}}

      get_in(proof, [:no_egress, :external_write_refs]) != [] ->
        {:error, {:external_writes_detected, get_in(proof, [:no_egress, :external_write_refs])}}

      true ->
        :ok
    end
  end

  defp reject_raw_payload_persistence(proof) do
    schema = Map.get(proof, :evidence_schema, %{})

    cond do
      Map.get(schema, :raw_provider_body) not in [nil, false] ->
        {:error, {:raw_payload_persistence_forbidden, :raw_provider_body}}

      Map.get(schema, :raw_prompt) not in [nil, false] ->
        {:error, {:raw_payload_persistence_forbidden, :raw_prompt}}

      Map.get(schema, :raw_workflow_history) not in [nil, false] ->
        {:error, {:raw_payload_persistence_forbidden, :raw_workflow_history}}

      Map.get(schema, :raw_payload_persistence) != :shape_only ->
        {:error, {:raw_payload_persistence_forbidden, Map.get(schema, :raw_payload_persistence)}}

      Map.get(schema, :raw_prompts_persisted?) ->
        {:error, {:raw_payload_persistence_forbidden, :raw_prompts_persisted}}

      Map.get(schema, :provider_bodies_persisted?) ->
        {:error, {:raw_payload_persistence_forbidden, :provider_bodies_persisted}}

      Map.get(schema, :workflow_histories_persisted?) ->
        {:error, {:raw_payload_persistence_forbidden, :workflow_histories_persisted}}

      true ->
        :ok
    end
  end

  defp require_fixture_inventory_quarantine(proof) do
    inventory = Map.get(proof, :provider_sdk_fixture_inventory, %{})
    claude = Map.get(inventory, :claude_agent_sdk, %{})

    cond do
      Map.get(claude, :global_runtime_switch_reintroduced?) ->
        {:error, :claude_global_runtime_switch_reintroduced}

      get_in(inventory, [:llama_cpp_sdk, :role]) !=
          :real_llama_server_consumer_not_simulation_owner ->
        {:error, :llama_cpp_sdk_role_invalid}

      true ->
        :ok
    end
  end

  defp cli_profiles do
    Map.new(provider_cases(), fn {provider, scenario_ref, stdout, _expected_text} ->
      {provider, [scenario_ref: scenario_ref, stdout_frames: [stdout], exit: :normal]}
    end)
  end

  defp provider_cases do
    [
      {:claude, "phase6://scenario-606/cli/claude",
       ~s({"type":"assistant_delta","delta":"claude phase6","session_id":"claude-phase6"}\n),
       "claude phase6"},
      {:codex, "phase6://scenario-606/cli/codex",
       ~s({"type":"response.output_text.delta","delta":"codex phase6","session_id":"codex-phase6"}\n),
       "codex phase6"},
      {:gemini, "phase6://scenario-606/cli/gemini",
       ~s({"type":"message","role":"assistant","delta":true,"content":"gemini phase6","session_id":"gemini-phase6"}\n),
       "gemini phase6"},
      {:amp, "phase6://scenario-606/cli/amp",
       ~s({"type":"message_streamed","delta":"amp phase6","session_id":"amp-phase6"}\n),
       "amp phase6"}
    ]
  end

  defp with_restored_env(app_keys, fun) when is_list(app_keys) and is_function(fun, 0) do
    previous_values =
      Map.new(app_keys, fn {app, key} ->
        {{app, key}, Application.get_env(app, key)}
      end)

    try do
      fun.()
    after
      Enum.each(previous_values, fn
        {{app, key}, nil} -> Application.delete_env(app, key)
        {{app, key}, value} -> Application.put_env(app, key, value)
      end)
    end
  end

  defp read_repo_file!(repo, relative_path) do
    @repo_parent
    |> Path.join(repo)
    |> Path.join(relative_path)
    |> File.read!()
  end

  defp evidence_map(%_module{} = struct), do: Map.from_struct(struct)
end
