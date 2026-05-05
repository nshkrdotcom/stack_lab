defmodule StackLab.Examples.GovernedProviderRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.GovernedProviderRoundtrip
  alias StackLab.GnTenControlPlane
  alias StackLab.SpecCell

  test "scenario exposes Phase 15 proof cases and existing substrate paths" do
    scenario = GovernedProviderRoundtrip.scenario()

    assert scenario.name == :governed_provider_roundtrip
    assert scenario.memory_substrate == :multi_node_epoch_monotonicity_and_ordering
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)

    assert Enum.sort(Map.keys(scenario.cases)) == [
             :central_ref_dispatch,
             :disposable_live_provider,
             :standalone_promotion,
             :workspace_build_no_secret_bundle
           ]
  end

  test "dispatch matrix covers every provider family across every target mode" do
    assert {:ok, proof} = GovernedProviderRoundtrip.prove_dispatch()

    assert proof.row_count ==
             length(GovernedProviderRoundtrip.provider_families()) *
               length(GovernedProviderRoundtrip.target_modes())

    assert Enum.sort(proof.providers) ==
             Enum.sort([
               :amp,
               :claude,
               :codex,
               :gemini_cli,
               :gemini_ex,
               :github,
               :inference,
               :linear,
               :llama_cpp_sdk,
               :notion,
               :reqllm_next,
               :self_hosted_inference
             ])

    assert Enum.all?(proof.rows, &(&1.dispatch_selector == :central_refs))
    assert Enum.all?(proof.rows, &(&1.materializer_source == :authority_materializer))
    assert Enum.all?(proof.rows, &(not &1.raw_material_present?))
    assert proof.auth_layer_separation.substitution_allowed? == false
  end

  test "standalone promotion keeps default mode separate from governed authority" do
    assert {:ok, proof} = GovernedProviderRoundtrip.standalone_promotion_proof()

    assert length(proof.rows) == length(GovernedProviderRoundtrip.provider_families())

    assert Enum.all?(proof.rows, fn row ->
             row.governed_rejection == {:unmanaged_auth_rejected, row.provider}
           end)

    assert Enum.all?(proof.rows, &(not &1.raw_material_present?))
    assert [%GnTenControlPlane{state: "passed"}] = proof.standalone_receipts
  end

  test "missing disposable live provider credentials are release-blocking defects" do
    proof = GovernedProviderRoundtrip.live_provider_proof()

    assert proof.release_blocking?
    assert [%GnTenControlPlane{requirement_id: "UAA-023", state: "missing"}] = proof.receipts

    assert Enum.all?(proof.rows, fn row ->
             row.state == :open_defect and row.normal_auth_roots_mutated? == false
           end)
  end

  test "disposable live provider credentials prove cleanup without normal roots" do
    disposable_refs =
      Map.new(GovernedProviderRoundtrip.provider_families(), fn provider ->
        {provider.id, "credential://disposable/#{provider.id}/phase15"}
      end)

    proof = GovernedProviderRoundtrip.live_provider_proof(disposable_refs)

    refute proof.release_blocking?
    assert [%GnTenControlPlane{requirement_id: "UAA-023", state: "passed"}] = proof.receipts
    assert Enum.all?(proof.rows, &(&1.state == :passed))
    assert Enum.all?(proof.rows, & &1.cleanup_verified?)
    assert Enum.all?(proof.rows, &(not &1.normal_auth_roots_mutated?))
  end

  test "workspace build manifest carries refs and no private auth material" do
    assert {:ok, proof} = GovernedProviderRoundtrip.workspace_build_no_secret_bundle_proof()

    assert proof.manifest.bundled_raw_private_material? == false
    assert proof.manifest.bundled_normal_user_auth_root? == false
    assert proof.manifest.bundled_token_files? == false

    assert proof.manifest.required_providers ==
             Enum.map(GovernedProviderRoundtrip.provider_families(), & &1.id)
  end

  test "SpecCell and gn-ten receipts are bounded and redacted" do
    cells = GovernedProviderRoundtrip.spec_cells()

    assert Enum.all?(cells, &match?(%SpecCell{owner_repo: "stack_lab"}, &1))
    assert Enum.all?(cells, &SpecCell.complete?/1)

    assert [%GnTenControlPlane{} = receipt] =
             GovernedProviderRoundtrip.receipts("UAA-026", "passed")

    refute GnTenControlPlane.release_blocking?(receipt)

    [row | _] = GovernedProviderRoundtrip.dispatch_matrix()
    redacted = GovernedProviderRoundtrip.redacted_receipt(Map.put(row, :api_key, "raw-value"))

    refute Map.has_key?(redacted, :api_key)
    assert redacted.raw_material_present? == false
  end
end
