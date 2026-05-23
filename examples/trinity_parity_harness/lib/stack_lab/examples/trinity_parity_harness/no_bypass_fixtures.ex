defmodule StackLab.Examples.TRINITYParityHarness.NoBypassFixtures do
  @moduledoc """
  Source fixtures for TRINITY no-bypass boundary validation.
  """

  @type result :: %{
          required(:id) => atom(),
          required(:expected_status) => :pass | :open_defect,
          required(:status) => :pass | :open_defect,
          required(:findings) => [map()]
        }

  @fixtures [
    %{
      id: :self_hosted_inference_core_import,
      expected_status: :open_defect,
      source: """
      defmodule Product.BadSelfHostedCore do
        alias SelfHostedInferenceCore.InstanceSpec
      end
      """
    },
    %{
      id: :crucible_factorization_import,
      expected_status: :open_defect,
      source: """
      defmodule Product.BadCrucibleFactorization do
        alias Crucible.Factorization.SVD
      end
      """
    },
    %{
      id: :trinity_router_import,
      expected_status: :pass,
      source: """
      defmodule Product.GoodTrinityRouter do
        alias Trinity.Router
      end
      """
    },
    %{
      id: :appkit_router_decision_projection_import,
      expected_status: :pass,
      source: """
      defmodule Product.GoodAppKitProjection do
        alias AppKit.CoordinationSurface.RouterDecisionProjection
      end
      """
    }
  ]

  @forbidden_prefixes [
    "SelfHostedInferenceCore",
    "SelfHostedInferenceBumblebee",
    "Crucible.Factorization",
    "CrucibleFactorization",
    "Crucible.Safetensors",
    "CrucibleSafetensors",
    "Crucible.TensorPatch",
    "CrucibleTensorPatch",
    "Crucible.ModelRegistry",
    "CrucibleModelRegistry"
  ]

  @spec run() :: [result()]
  def run do
    Enum.map(@fixtures, fn fixture ->
      findings = findings(fixture.source)
      status = if findings == [], do: :pass, else: :open_defect

      %{
        id: fixture.id,
        expected_status: fixture.expected_status,
        status: status,
        findings: findings
      }
    end)
  end

  @spec fixtures() :: [map()]
  def fixtures, do: @fixtures

  defp findings(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      @forbidden_prefixes
      |> Enum.filter(&forbidden_line?(&1, line))
      |> Enum.map(fn prefix ->
        %{
          rule: :trinity_runtime_bypass,
          forbidden: prefix,
          line: line_number,
          snippet: String.trim(line)
        }
      end)
    end)
  end

  defp forbidden_line?(prefix, line) do
    String.contains?(line, [
      "alias #{prefix}",
      "import #{prefix}",
      "require #{prefix}",
      "#{prefix}."
    ])
  end
end
