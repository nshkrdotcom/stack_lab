defmodule StackLab.ExtravaganzaExternalAcceptanceTest do
  use ExUnit.Case, async: true

  alias StackLab.ExtravaganzaExternalAcceptance

  @required_readbacks ~w(
    state
    queue
    subject
    run
    evidence
    route_evidence
    context_ai_summary
    events
    reviews
    review_decision
    source_preview
    source_publish
    source_publication
    refresh
    control
    read_lease
    stream_attach_lease
    profile
    profile_validate
    profile_reload
    status
    logs
    live_preflight_denial
    command_coverage
    route_coverage
    error_classes
  )

  test "runs Extravaganza's public deterministic same-run smoke and validates externally" do
    root = Path.expand("../extravaganza", File.cwd!())
    parent = self()

    runner = fn command, args, opts ->
      send(parent, {:product_command, command, args, opts})
      {Jason.encode!(product_receipt()), 0}
    end

    assert {:ok, receipt} =
             ExtravaganzaExternalAcceptance.run(
               extravaganza_root: root,
               mix_executable: "mix",
               runner: runner
             )

    assert_received {:product_command, "mix",
                     ["extravaganza.headless.smoke", "--deterministic", "--same-run", "--json"],
                     command_opts}

    assert command_opts[:cd] == root
    assert command_opts[:env] == [{"MIX_ENV", "test"}]
    assert command_opts[:env_allowlist] == ["MIX_ENV"]
    assert command_opts[:stderr_to_stdout] == true

    assert receipt["schema_version"] == "stack_lab.extravaganza_external_acceptance.v1"
    assert receipt["status"] == "pass"
    assert receipt["product_acceptance_owner"] == "extravaganza"
    assert receipt["stack_lab_role"] == "external_acceptance"
    assert receipt["proof_posture"]["imports_extravaganza_internals?"] == false
    assert receipt["proof_posture"]["product_implementation_in_stack_lab?"] == false
    assert receipt["proof_posture"]["multi_node_topology_proven?"] == false

    assert receipt["provider_smoke"]["classification"] ==
             "separate_provider_only_not_product_acceptance"

    assert receipt["product_receipt"]["operation"] == "smoke"
    assert receipt["product_receipt"]["proof_class"] == "product_same_run_deterministic"
    assert receipt["product_receipt"]["readbacks"] == @required_readbacks
    assert receipt["validated_refs"]["lower_terminal_ref"] == "lower-receipt://example"
    assert receipt["validated_refs"]["authority_ref"] == "authority-decision://example"
    assert receipt["validated_refs"]["evidence_chain_ref"] == "evidence-chain://example"
    assert receipt["validated_route_evidence"]["binding_ref"] == "binding://example"
    assert receipt["validated_route_evidence"]["trace_replay"]["status"] == "not_emitted"
    assert receipt["validated_context_ai_summary"]["surface"] == "AppKit.ContextSurface"
    assert receipt["validated_context_ai_summary"]["payload_hash"] =~ "sha256:"
  end

  test "rejects product output that lacks required refs" do
    runner = fn _command, _args, _opts ->
      product_receipt =
        product_receipt()
        |> update_in(["refs"], &Map.delete(&1, "authority_ref"))

      {Jason.encode!(product_receipt), 0}
    end

    assert {:error, reason} = ExtravaganzaExternalAcceptance.run(runner: runner)
    assert reason.code == "extravaganza_receipt_missing_refs"
    assert reason.missing_refs == ["authority_ref"]
  end

  test "accepts product receipt with compile warning prefix" do
    runner = fn _command, _args, _opts ->
      {"==> dependency warning\n" <> Jason.encode!(product_receipt()), 0}
    end

    assert {:ok, receipt} = ExtravaganzaExternalAcceptance.run(runner: runner)
    assert receipt["status"] == "pass"
  end

  test "rejects product output without a lower receipt or lower denial ref" do
    runner = fn _command, _args, _opts ->
      product_receipt =
        product_receipt()
        |> update_in(["refs"], &Map.delete(&1, "lower_receipt_ref"))

      {Jason.encode!(product_receipt), 0}
    end

    assert {:error, reason} = ExtravaganzaExternalAcceptance.run(runner: runner)
    assert reason.code == "extravaganza_receipt_missing_lower_terminal_ref"
  end

  test "rejects product output that did not prove runtime projection readback" do
    runner = fn _command, _args, _opts ->
      product_receipt =
        product_receipt()
        |> put_in(["data", "proof", "steps"], [])

      {Jason.encode!(product_receipt), 0}
    end

    assert {:error, reason} = ExtravaganzaExternalAcceptance.run(runner: runner)
    assert reason.code == "extravaganza_receipt_missing_projection_proof"
  end

  test "rejects product output without deterministic route evidence" do
    runner = fn _command, _args, _opts ->
      product_receipt =
        product_receipt()
        |> pop_in(["data", "route_evidence"])
        |> elem(1)
        |> pop_in(["data", "proof", "route_evidence"])
        |> elem(1)
        |> update_in(["data", "proof", "readbacks"], fn readbacks ->
          Enum.map(readbacks, fn
            %{"name" => "route_evidence"} = readback -> Map.put(readback, "data", %{})
            readback -> readback
          end)
        end)

      {Jason.encode!(product_receipt), 0}
    end

    assert {:error, reason} = ExtravaganzaExternalAcceptance.run(runner: runner)
    assert reason.code == "extravaganza_receipt_missing_route_evidence"
    assert "product_role_ref" in reason.missing_fields
  end

  test "rejects product output without product-safe context AI summary" do
    runner = fn _command, _args, _opts ->
      product_receipt =
        product_receipt()
        |> pop_in(["data", "context_ai_summary"])
        |> elem(1)
        |> pop_in(["data", "proof", "context_ai_summary"])
        |> elem(1)
        |> update_in(["data", "proof", "readbacks"], fn readbacks ->
          Enum.map(readbacks, fn
            %{"name" => "context_ai_summary"} = readback -> Map.put(readback, "data", %{})
            readback -> readback
          end)
        end)

      {Jason.encode!(product_receipt), 0}
    end

    assert {:error, reason} = ExtravaganzaExternalAcceptance.run(runner: runner)
    assert reason.code == "extravaganza_receipt_missing_context_ai_summary"
  end

  test "rejects product output with raw context AI fields" do
    runner = fn _command, _args, _opts ->
      product_receipt =
        product_receipt()
        |> put_in(["data", "context_ai_summary", "forbidden_raw_fields_present?"], true)
        |> put_in(["data", "proof", "context_ai_summary", "forbidden_raw_fields_present?"], true)
        |> update_in(["data", "proof", "readbacks"], fn readbacks ->
          Enum.map(readbacks, fn
            %{"name" => "context_ai_summary"} = readback ->
              put_in(readback, ["data", "forbidden_raw_fields_present?"], true)

            readback ->
              readback
          end)
        end)

      {Jason.encode!(product_receipt), 0}
    end

    assert {:error, reason} = ExtravaganzaExternalAcceptance.run(runner: runner)
    assert reason.code == "extravaganza_receipt_context_summary_has_raw_fields"
  end

  defp product_receipt do
    refs = %{
      "subject_ref" => "subject://example",
      "run_ref" => "run://example",
      "workflow_ref" => "workflow://example",
      "runtime_profile_ref" => "codex_session",
      "product_role_ref" => "runtime-role://example",
      "binding_ref" => "binding://example",
      "manifest_ref" => "manifest://example",
      "authority_ref" => "authority-decision://example",
      "decision_ref" => "decision://example",
      "connector_binding_ref" => "connector-binding://example",
      "connector_manifest_ref" => "manifest://example",
      "capability_negotiation_ref" => "cap-neg://example",
      "credential_lease_ref" => "credential-lease://example",
      "lower_request_ref" => "lower-request://example",
      "lower_receipt_ref" => "lower-receipt://example",
      "receipt_ref" => "lower-receipt://example",
      "source_publication_ref" => "source-publication://example",
      "projection_ref" => "projection://example",
      "evidence_ref" => "evidence-chain://example",
      "evidence_chain_ref" => "evidence-chain://example",
      "event_page_ref" => "event-page://example",
      "trace_ref" => "trace://example"
    }

    route_evidence = route_evidence(refs)
    context_summary = context_ai_summary(refs)

    %{
      "schema" => "extravaganza.headless.response.v1",
      "ok" => true,
      "operation" => "smoke",
      "generated_at" => "2026-05-11T03:34:21Z",
      "trace_id" => "trace:extravaganza:headless:test",
      "runtime_profile_ref" => "codex_session",
      "refs" => refs,
      "data" => %{
        "route_evidence" => route_evidence,
        "context_ai_summary" => context_summary,
        "proof" => %{
          "proof_class" => "product_same_run_deterministic",
          "all_readbacks_share_refs" => true,
          "route_evidence" => route_evidence,
          "context_ai_summary" => context_summary,
          "steps" => ["mezzanine_runtime_projection_projected"],
          "readbacks" =>
            Enum.map(@required_readbacks, &readback(&1, refs, route_evidence, context_summary))
        },
        "start" => %{
          "subject_ref" => refs["subject_ref"],
          "run_ref" => refs["run_ref"],
          "workflow_ref" => refs["workflow_ref"],
          "runtime_profile_ref" => refs["runtime_profile_ref"]
        }
      }
    }
  end

  defp readback("route_evidence" = name, refs, route_evidence, _context_summary) do
    refs
    |> Map.put("name", name)
    |> Map.put("ok", true)
    |> Map.put("data", route_evidence)
  end

  defp readback("context_ai_summary" = name, refs, _route_evidence, context_summary) do
    refs
    |> Map.put("name", name)
    |> Map.put("ok", true)
    |> Map.put("data", context_summary)
  end

  defp readback(name, refs, _route_evidence, _context_summary) do
    refs
    |> Map.put("name", name)
    |> Map.put("ok", true)
    |> Map.put("data", %{})
  end

  defp route_evidence(refs) do
    %{
      "product_role_ref" => refs["product_role_ref"],
      "binding_ref" => refs["binding_ref"],
      "manifest_ref" => refs["manifest_ref"],
      "authority_ref" => refs["authority_ref"],
      "connector_binding_ref" => refs["connector_binding_ref"],
      "credential_lease_ref" => refs["credential_lease_ref"],
      "lower_request_ref" => refs["lower_request_ref"],
      "receipt_ref" => refs["receipt_ref"],
      "projection_ref" => refs["projection_ref"],
      "evidence_ref" => refs["evidence_ref"],
      "trace_ref" => refs["trace_ref"],
      "trace_replay" => %{
        "status" => "not_emitted",
        "replay_system_ref" => "ai_trace",
        "trace_ref" => refs["trace_ref"]
      }
    }
  end

  defp context_ai_summary(refs) do
    %{
      "surface" => "AppKit.ContextSurface",
      "proof_class" => "extravaganza_context_ai_product_projection",
      "live_provider_required?" => false,
      "lower_stack_imports?" => false,
      "forbidden_raw_fields_present?" => false,
      "context_packet" => %{
        "context_packet_ref" => "context-packet://example",
        "packet_hash" => "sha256:" <> String.duplicate("a", 64),
        "receipt_ref" => "context-packet-receipt://example"
      },
      "route_decision" => %{"route_decision_ref" => "route-decision://example"},
      "model_invocation" => %{
        "model_invocation_ref" => "model-invocation://example",
        "model_receipt_ref" => "model-receipt://example",
        "prompt_artifact_ref" => "prompt-artifact://example",
        "provider_payload_ref" => "provider-payload://example",
        "payload_hash" => "sha256:" <> String.duplicate("b", 64)
      },
      "eval_verdict" => %{"eval_verdict_ref" => "eval-verdict://example"},
      "operator_review" => %{"review_ref" => "review://example"},
      "projection_facts" => %{
        "context_packet_ref" => "context-packet://example",
        "trace_ref" => refs["trace_ref"]
      }
    }
  end
end
