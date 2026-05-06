defmodule StackLab.GuardrailRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.GuardrailRoundtrip

  test "safe prompts pass through prompt and guardrail projections" do
    assert {:ok, receipt} = GuardrailRoundtrip.run(%{payload: "safe prompt"})

    assert receipt.status == :pass
    assert "PROMPT-009" in receipt.fixture_refs
    refute Map.has_key?(receipt.guard_projection, :payload)
  end

  test "guard rejection emits bounded violation refs" do
    assert {:ok, receipt} = GuardrailRoundtrip.run(%{payload: "contact me at test@example.com"})

    assert receipt.status == :rejected
    assert [%{violation_id: "guard-violation://" <> _rest}] = receipt.guard_projection.violations
  end
end
