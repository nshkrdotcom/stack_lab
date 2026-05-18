defmodule StackLab.GapClosureNegativeFixturesTest do
  use ExUnit.Case, async: true

  alias StackLab.GapClosureNegativeFixtures

  @required_ids [
    :unsafe_dynamic_atom_construction,
    :generic_raw_credential_ingress,
    :nested_concrete_binding_injection,
    :provider_fallback_default_in_bridge_root,
    :unclassified_provider_public_vocabulary,
    :duplicated_provider_family_list,
    :ambiguous_adapter_class,
    :unbundled_generic_dispatch_entrypoint,
    :nonserializable_boundary_payload,
    :noncanonical_boundary_hash,
    :cross_tenant_store_lookup,
    :governed_aitrace_replay_without_tenant,
    :production_secret_envelope_dev_key
  ]

  test "registry names every Phase 0 negative-control fixture" do
    ids = GapClosureNegativeFixtures.all() |> Enum.map(& &1.id) |> Enum.sort()

    assert ids == Enum.sort(@required_ids)
  end

  test "fixtures carry owner, claim, path, failure, and hostile source" do
    for fixture <- GapClosureNegativeFixtures.all() do
      assert is_atom(fixture.id)
      assert fixture.owner_phase =~ "Phase "
      assert is_binary(fixture.claim)
      assert byte_size(fixture.claim) > 20
      assert is_binary(fixture.path_hint)
      assert fixture.path_hint != ""
      assert is_atom(fixture.expected_failure)
      assert is_binary(fixture.source)
      assert fixture.source =~ "defmodule "
    end
  end

  test "fetch returns fixture by id" do
    assert %{id: :noncanonical_boundary_hash} =
             GapClosureNegativeFixtures.fetch!(:noncanonical_boundary_hash)
  end
end
