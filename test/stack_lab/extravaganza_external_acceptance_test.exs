defmodule StackLab.ExtravaganzaExternalAcceptanceTest do
  use ExUnit.Case, async: true

  alias StackLab.ExtravaganzaExternalAcceptance

  @required_readbacks ~w(
    state
    queue
    subject
    run
    evidence
    events
    reviews
    review_decision
    source_preview
    source_publication
    refresh
    control
    read_lease
    stream_attach_lease
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

  defp product_receipt do
    refs = %{
      "subject_ref" => "subject://example",
      "run_ref" => "run://example",
      "workflow_ref" => "workflow://example",
      "runtime_profile_ref" => "codex_session",
      "authority_ref" => "authority-decision://example",
      "decision_ref" => "decision://example",
      "connector_manifest_ref" => "manifest://example",
      "capability_negotiation_ref" => "cap-neg://example",
      "lower_request_ref" => "lower-request://example",
      "lower_receipt_ref" => "lower-receipt://example",
      "source_publication_ref" => "source-publication://example",
      "evidence_chain_ref" => "evidence-chain://example",
      "event_page_ref" => "event-page://example"
    }

    %{
      "schema" => "extravaganza.headless.response.v1",
      "ok" => true,
      "operation" => "smoke",
      "generated_at" => "2026-05-11T03:34:21Z",
      "trace_id" => "trace:extravaganza:headless:test",
      "runtime_profile_ref" => "codex_session",
      "refs" => refs,
      "data" => %{
        "proof" => %{
          "proof_class" => "product_same_run_deterministic",
          "all_readbacks_share_refs" => true,
          "steps" => ["mezzanine_runtime_projection_projected"],
          "readbacks" => Enum.map(@required_readbacks, &readback(&1, refs))
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

  defp readback(name, refs) do
    refs
    |> Map.put("name", name)
    |> Map.put("ok", true)
    |> Map.put("data", %{})
  end
end
