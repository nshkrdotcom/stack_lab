defmodule StackLab.CitadelSpineHarness.ExtensionAuthoring do
  @moduledoc """
  Scenario 34 proof harness for internal/operator bundle import and activation.
  """

  alias Mezzanine.Authoring.Bundle
  alias Mezzanine.Pack.{Compiler, ExecutionRecipeSpec, LifecycleSpec, Manifest, Serializer}
  alias Mezzanine.Pack.{ContextSourceSpec, ProjectionSpec, SubjectKindSpec}
  alias StackLab.CitadelSpineHarness.MezzanineOperationalStack

  @signing_key "stacklab-phase3-m7-signing-key"
  @policy_refs ["policy.default"]
  @context_adapters %{"memory_adapter" => __MODULE__}

  @spec run_case(:activation_failure_matrix) :: {:ok, map()} | {:error, term()}
  def run_case(:activation_failure_matrix) do
    MezzanineOperationalStack.with_store(:phase3_m7_extension_authoring, fn _repo_config ->
      with {:ok, valid} <- import_valid_bundle(),
           {:ok, rejections} <- rejection_matrix(),
           {:ok, stale_revision} <- stale_revision_case(valid.installation_id) do
        {:ok,
         %{
           scenario: 34,
           case: :activation_failure_matrix,
           runbook: "pack_activation_failure.md",
           valid: valid,
           rejections: rejections,
           stale_revision: stale_revision,
           absence: %{pack_authored_platform_migrations: :rejected_before_activation}
         }}
      end
    end)
  end

  defp import_valid_bundle do
    attrs = signed_bundle_attrs(bundle_id: "bundle-stacklab-valid", pack_slug: :stacklab_valid)

    with {:ok, result} <- import_bundle(attrs) do
      {:ok,
       %{
         bundle_id: result.bundle.bundle_id,
         status: result.installation.status,
         installation_id: result.installation.id,
         installation_revision: result.installation.compiled_pack_revision
       }}
    end
  end

  defp rejection_matrix do
    checks = %{
      checksum:
        signed_bundle_attrs(bundle_id: "bundle-stacklab-checksum", pack_slug: :stacklab_checksum)
        |> Map.put("checksum", "sha256:invalid"),
      signature:
        signed_bundle_attrs(
          bundle_id: "bundle-stacklab-signature",
          pack_slug: :stacklab_signature
        )
        |> Map.put("signature", "hmac-sha256:invalid"),
      policy_ref:
        signed_bundle_attrs(
          bundle_id: "bundle-stacklab-policy",
          pack_slug: :stacklab_policy,
          policy_refs: ["policy.missing"]
        ),
      platform_migration:
        signed_bundle_attrs(
          bundle_id: "bundle-stacklab-migration",
          pack_slug: :stacklab_migration,
          platform_migrations: [%{"table" => "subjects"}]
        ),
      lifecycle_hint:
        signed_bundle_attrs(
          bundle_id: "bundle-stacklab-hint",
          pack_slug: :stacklab_hint,
          required_lifecycle_hints: [:ticket_status],
          produced_lifecycle_hints: []
        ),
      context_adapter:
        signed_bundle_attrs(
          bundle_id: "bundle-stacklab-adapter",
          pack_slug: :stacklab_adapter,
          context_adapter_key: "missing_adapter"
        )
    }

    result =
      Map.new(checks, fn {name, attrs} ->
        {:error, {:invalid_authoring_bundle, issues}} = import_bundle(attrs)
        {name, hd(issues).code}
      end)

    {:ok, result}
  end

  defp stale_revision_case(installation_id) do
    attrs =
      signed_bundle_attrs(
        bundle_id: "bundle-stacklab-stale",
        installation_id: installation_id,
        pack_slug: :stacklab_valid
      )

    with {:error, {:stale_installation_revision, details}} <-
           import_bundle(attrs, expected_installation_revision: 0) do
      {:ok,
       %{
         status: :stale_revision,
         attempted_revision: details.attempted_revision,
         current_revision: details.current_revision
       }}
    end
  end

  defp import_bundle(attrs, opts \\ []) do
    MezzanineConfigRegistry.import_authoring_bundle(
      attrs,
      [
        signing_key: @signing_key,
        allowed_policy_refs: @policy_refs,
        context_adapter_registry: @context_adapters
      ] ++ opts
    )
  end

  defp signed_bundle_attrs(opts) do
    manifest = manifest(opts)
    manifest_payload = Serializer.serialize_manifest(manifest)
    context_adapter_key = Keyword.get(opts, :context_adapter_key, "memory_adapter")

    unsigned = %{
      "bundle_id" => Keyword.fetch!(opts, :bundle_id),
      "tenant_id" => "tenant-stacklab-authoring",
      "installation_id" => Keyword.get(opts, :installation_id, "stacklab-authoring"),
      "pack_manifest" => manifest_payload,
      "lifecycle_specs" => manifest_payload["lifecycle_specs"],
      "decision_specs" => manifest_payload["decision_specs"],
      "binding_descriptors" => binding_descriptors(context_adapter_key, opts),
      "observer_descriptors" => [
        %{"binding_key" => "audit_export", "subscriber_key" => "audit_export"}
      ],
      "context_adapter_descriptors" => [
        %{"binding_key" => "memory_adapter", "adapter_key" => context_adapter_key}
      ],
      "policy_refs" => Keyword.get(opts, :policy_refs, @policy_refs),
      "authored_by" => "operator:stacklab"
    }

    unsigned = maybe_put_platform_migrations(unsigned, opts)

    unsigned
    |> Map.put("checksum", Bundle.checksum_for(unsigned))
    |> Map.put("signature", Bundle.signature_for(unsigned, @signing_key))
  end

  defp maybe_put_platform_migrations(attrs, opts) do
    case Keyword.fetch(opts, :platform_migrations) do
      {:ok, migrations} -> Map.put(attrs, "platform_migrations", migrations)
      :error -> attrs
    end
  end

  defp binding_descriptors(context_adapter_key, opts) do
    produced_hints = Keyword.get(opts, :produced_lifecycle_hints, [:ticket_status])

    %{
      "execution_bindings" => %{
        "phase3_capture" => %{
          "placement_ref" => "local_runner",
          "connector_capability" => %{
            "capability_id" => "phase3.capture",
            "version" => "2026.04",
            "produces_lifecycle_hints" => Enum.map(produced_hints, &to_string/1)
          }
        }
      },
      "context_bindings" => %{
        "memory_adapter" => %{"adapter_key" => context_adapter_key, "config" => %{}}
      }
    }
  end

  defp manifest(opts) do
    required_lifecycle_hints = Keyword.get(opts, :required_lifecycle_hints, [])

    manifest = %Manifest{
      pack_slug: Keyword.fetch!(opts, :pack_slug),
      version: "1.0.0",
      subject_kind_specs: [%SubjectKindSpec{name: :phase3_request}],
      context_source_specs: [
        %ContextSourceSpec{
          source_ref: :workspace_memory,
          binding_key: :memory_adapter,
          usage_phase: :retrieval,
          timeout_ms: 250
        }
      ],
      lifecycle_specs: [
        %LifecycleSpec{
          subject_kind: :phase3_request,
          initial_state: :submitted,
          terminal_states: [:completed],
          transitions: [
            %{
              from: :submitted,
              to: :processing,
              trigger: {:execution_requested, :phase3_capture}
            },
            %{from: :processing, to: :completed, trigger: {:execution_completed, :phase3_capture}}
          ]
        }
      ],
      execution_recipe_specs: [
        %ExecutionRecipeSpec{
          recipe_ref: :phase3_capture,
          runtime_class: :session,
          placement_ref: :local_runner,
          workspace_policy: %{
            strategy: :per_subject,
            root_ref: :stacklab_authoring_workspaces
          },
          sandbox_policy_ref: :stacklab_authoring_sandbox,
          prompt_refs: [:phase3_capture_prompt],
          required_lifecycle_hints: required_lifecycle_hints
        }
      ],
      projection_specs: [
        %ProjectionSpec{name: :phase3_active, subject_kinds: [:phase3_request]}
      ]
    }

    case Compiler.compile(manifest) do
      {:ok, compiled} -> compiled.manifest
      {:error, errors} -> raise "invalid scenario manifest: #{inspect(errors)}"
    end
  end
end
