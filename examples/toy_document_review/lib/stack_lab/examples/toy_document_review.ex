defmodule StackLab.Examples.ToyDocumentReview do
  @moduledoc """
  Executable neutral product proof for the generic substrate foundation.
  """

  alias StackLab.Examples.ToyDocumentReview.{
    AppKitRoleRefProbe,
    ContentShapeGate,
    ContentStoreAcceptance,
    ExecutionPlaneProbe,
    FixtureFaultMatrix,
    FoundationProof,
    NeutralCodeScan,
    OperationGraphGate,
    ProductHost,
    ReplayProof
  }

  def scenario, do: ProductHost.scenario()

  def required_components, do: ProductHost.required_components()

  def full_acceptance_components, do: ProductHost.full_acceptance_components()

  def source_inputs, do: ProductHost.source_inputs()

  def state_mapping, do: ProductHost.state_mapping()

  def run_content_shape_gate, do: ContentShapeGate.run()

  def run_content_store_acceptance, do: ContentStoreAcceptance.run()

  def run_operation_graph_gate, do: OperationGraphGate.run()

  def run_foundation_proof(opts \\ []) when is_list(opts), do: FoundationProof.run(opts)

  def receipt_projection_replay_preflight, do: ReplayProof.preflight()

  def run_receipt_projection_replay_proof(opts \\ []) when is_list(opts),
    do: ReplayProof.run(opts)

  def run_full_gate3_proof(opts \\ []) when is_list(opts), do: ReplayProof.run_gate3(opts)

  def fault_matrix(service), do: FixtureFaultMatrix.run(service)

  def bypass_rejections(opts \\ []), do: FoundationProof.bypass_rejections(opts)

  def appkit_role_ref_probe, do: AppKitRoleRefProbe.run()

  def execution_plane_probe, do: ExecutionPlaneProbe.run()

  def neutral_code_scan do
    NeutralCodeScan.run(__ENV__.file, ProductHost.forbidden_neutral_terms())
  end

  def run_full_acceptance(opts \\ []) when is_list(opts) do
    service = Keyword.fetch!(opts, :service)
    content_shape = run_content_shape_gate()
    content_store = run_content_store_acceptance()
    faults = fault_matrix(service)
    bypass = bypass_rejections()

    with {:ok, graph} <- run_operation_graph_gate(),
         {:ok, appkit} <- appkit_role_ref_probe(),
         {:ok, execution_plane} <- execution_plane_probe(),
         {:ok, foundation} <- run_foundation_proof(opts),
         {:ok, receipt_replay} <- run_receipt_projection_replay_proof(opts),
         {:ok, gate3} <- run_full_gate3_proof(opts) do
      {:ok,
       %{
         scenario: scenario(),
         accepted?: true,
         execution_route_ref: ProductHost.execution_route_ref(),
         component_path: ProductHost.full_acceptance_components(),
         source_inputs: source_inputs(),
         state_mapping: state_mapping(),
         appkit_role_ref_boundary: appkit,
         foundation: FoundationProof.summary(foundation),
         content_shape_gate: content_shape.acceptance,
         content_store_acceptance: content_store.content_store_contract,
         operation_graph_gate: graph_summary(graph),
         fault_matrix: FixtureFaultMatrix.summary(faults),
         bypass_rejections: FoundationProof.bypass_summary(bypass),
         receipt_projection_replay: ReplayProof.summary(receipt_replay),
         full_gate3: gate3,
         execution_plane: execution_plane,
         neutral_code_scan: neutral_code_scan(),
         live_profiles: [],
         live_acceptance: %{
           required?: false,
           reason: :no_live_github_or_linear_profile_for_neutral_proof_app
         }
       }}
    end
  end

  defp graph_summary(proof) do
    %{
      graph: proof.graph,
      initial_ready_node_refs: proof.initial_ready_node_refs,
      alternate_completion_orders: proof.alternate_completion_orders,
      concurrent_runtime_evidence_branch: proof.concurrent_runtime_evidence_branch
    }
  end
end
