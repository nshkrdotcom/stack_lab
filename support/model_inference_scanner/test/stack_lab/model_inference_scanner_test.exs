defmodule StackLab.ModelInferenceScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.ModelInferenceScanner

  test "passes governed model facts with separated endpoint identity" do
    assert {:ok, receipt} =
             ModelInferenceScanner.scan(%{
               owner_repo: "jido_integration",
               package_path: "core/model_provider_registry",
               runtime_facts: [
                 %{
                   model_profile_ref: "model-profile://mock/proposer",
                   endpoint_profile_ref: "endpoint-profile://local/proposer",
                   endpoint_identity_ref: "endpoint-identity://local/proposer",
                   provider_credential_ref: "provider-credential://mock/profile",
                   operation_policy_ref: "policy://operation/propose"
                 }
               ],
               source_units: []
             })

    assert receipt.status == :pass
    assert receipt.fixture_ref == "AOC-041"
    assert receipt.findings == []
  end

  test "blocks ambient provider fallback, raw key projection, and identity merge" do
    key = Enum.join(["OPENAI", "API", "KEY"], "_")
    fallback_call = Enum.join(["System", "get_env"], ".") <> "(\"" <> key <> "\")"

    assert {:ok, receipt} =
             ModelInferenceScanner.scan(%{
               owner_repo: "product",
               package_path: "apps/product_surface",
               source_units: [
                 %{path: "apps/product_surface/lib/provider.ex", source: fallback_call},
                 %{
                   path: "apps/product_surface/lib/raw_key.ex",
                   source: Enum.join(["provider", "api", "key"], "_")
                 }
               ],
               runtime_facts: [
                 %{
                   model_profile_ref: "model-profile://mock/proposer",
                   endpoint_profile_ref: "endpoint-profile://local/proposer",
                   endpoint_identity_ref: "identity://merged",
                   provider_credential_ref: "identity://merged",
                   operation_policy_ref: "policy://operation/propose"
                 }
               ]
             })

    assert receipt.status == :open_defect

    assert Enum.map(receipt.findings, & &1.rule) == [
             :ambient_provider_fallback,
             :raw_key_projection,
             :endpoint_provider_identity_merge
           ]
  end

  test "requires model profile, endpoint profile, and operation policy refs" do
    assert {:ok, receipt} =
             ModelInferenceScanner.scan(%{
               owner_repo: "jido_integration",
               package_path: "core/model_provider_registry",
               runtime_facts: [%{}]
             })

    assert receipt.status == :open_defect

    assert Enum.map(receipt.findings, & &1.rule) == [
             :missing_model_profile_ref,
             :missing_endpoint_profile_ref,
             :missing_operation_policy_ref
           ]
  end
end
