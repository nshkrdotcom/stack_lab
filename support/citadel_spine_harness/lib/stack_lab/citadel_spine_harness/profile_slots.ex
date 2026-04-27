defmodule StackLab.CitadelSpineHarness.ProfileSlots do
  @moduledoc false

  @defaults %{
    source_profile_ref: :stack_lab_fixture_source_v1,
    runtime_profile_ref: :stack_lab_fixture_runtime_v1,
    tool_scope_ref: :stack_lab_fixture_tools_v1,
    evidence_profile_ref: :stack_lab_fixture_evidence_v1,
    publication_profile_ref: :stack_lab_fixture_publication_v1,
    review_profile_ref: :operator_optional,
    memory_profile_ref: :none,
    projection_profile_ref: :runtime_readback_v1
  }

  @spec default(keyword() | map()) :: map()
  def default(overrides \\ []) do
    Map.merge(@defaults, Map.new(overrides))
  end
end
