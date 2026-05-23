defmodule StackLab.Examples.TRINITYSingleNodeRoundtripTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.TRINITYSingleNodeRoundtrip
  alias Trinity.SingleNode

  @expected_transcript_hash "6f7d00cd47d137afbaf4bf479a305cd2e11b5ceb4138230648eb21a57c9e5106"
  @cases_path "/home/home/p/g/n/trinity_coordinator/examples/fixtures/qwen_router_prompt_eval_cases.json"
  @snapshot_path "/home/home/p/g/n/trinity_coordinator/examples/fixtures/qwen_router_prompt_eval_logits.json"

  setup do
    Application.ensure_all_started(:trinity_single_node)
    SelfHostedInferenceCore.stop_all_instances()

    on_exit(fn ->
      SelfHostedInferenceCore.stop_all_instances()
      Application.stop(:trinity_single_node)
    end)

    :ok
  end

  test "proves standalone mock-tiny route, provider dispatch, and trace parity" do
    assert {:ok, receipt} = TRINITYSingleNodeRoundtrip.run()

    assert receipt.status == :pass
    assert receipt.runtime_profile == :mock_tiny
    assert receipt.fixture_refs == ["AOC-026", "AOC-036", "AOC-039", "AOC-043"]
    assert receipt.forbidden_dependency_apps == []
    assert receipt.direct_dependency_apps == [:credo, :dialyxir, :ex_doc, :trinity_framework]
    assert receipt.provider_status == :ok
    assert receipt.transcript_hash == @expected_transcript_hash
    assert receipt.token_count == 4
    assert Enum.any?(receipt.trace_events, &String.contains?(&1, "\"route_selected\""))
    assert Enum.any?(receipt.trace_events, &String.contains?(&1, "\"provider_called\""))
  end

  @tag :qwen_sakana_adapted
  @tag timeout: 300_000
  test "optional Qwen route eval matches the 37-case coordinator snapshot" do
    artifact_root = required_artifact_root!()

    assert {:ok, runtime} =
             SingleNode.load_runtime(
               runtime_profile: :cuda_exla,
               artifact_root: artifact_root,
               messages: []
             )

    cases = fixture_cases_with_snapshot()
    assert length(cases) == 37

    for %{"messages" => messages, "snapshot" => snapshot} <- cases do
      assert {:ok, result} =
               SingleNode.route(messages,
                 runtime_profile: :cuda_exla,
                 artifact_root: artifact_root,
                 runtime: runtime
               )

      assert result.decision.selected_agent_id == snapshot["agent_id"]
      assert result.decision.selected_role_id == snapshot["role_id"]
      assert result.decision.token_count == snapshot["token_count"]
      assert result.decision.transcript_hash == snapshot["transcript_hash"]
    end
  end

  defp required_artifact_root! do
    artifact_root =
      System.get_env("TRINITY_ARTIFACT_DIR") ||
        "/home/home/p/g/n/trinity_coordinator/priv/sakana_trinity/adapted_qwen3_0_6b_layer26"

    unless File.dir?(artifact_root) do
      raise "TRINITY_ARTIFACT_DIR must point at an adapted artifact directory"
    end

    artifact_root
  end

  defp fixture_cases_with_snapshot do
    snapshot_by_id =
      @snapshot_path
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!("cases")
      |> Map.new(&{Map.fetch!(&1, "id"), &1})

    @cases_path
    |> File.read!()
    |> JSON.decode!()
    |> Map.fetch!("cases")
    |> Enum.map(fn case_spec ->
      Map.put(case_spec, "snapshot", Map.fetch!(snapshot_by_id, Map.fetch!(case_spec, "id")))
    end)
  end
end
