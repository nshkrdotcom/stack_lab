defmodule StackLab.Examples.TRINITYSingleNodeRoundtrip.Receipt do
  @moduledoc "Receipt for the standalone TRINITY single-node roundtrip."
  @enforce_keys [
    :receipt_ref,
    :fixture_refs,
    :status,
    :runtime_profile,
    :direct_dependency_apps,
    :forbidden_dependency_apps,
    :selected_agent_id,
    :selected_role_id,
    :role_name,
    :token_count,
    :transcript_hash,
    :route_hash,
    :provider_status,
    :provider_ref,
    :trace_path,
    :trace_events
  ]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end

defmodule StackLab.Examples.TRINITYSingleNodeRoundtrip do
  @moduledoc """
  Standalone TRINITY single-node validation with no product-platform deps.
  """

  alias StackLab.Examples.TRINITYSingleNodeRoundtrip.Receipt

  @fixture_refs ["AOC-026", "AOC-036", "AOC-039", "AOC-043"]
  @forbidden_dependency_apps [
    :app_kit,
    :app_kit_coordination_surface,
    :jido,
    :jido_integration,
    :mezzanine,
    :outer_brain,
    :citadel
  ]

  @spec run(keyword()) :: {:ok, Receipt.t()} | {:error, term()}
  def run(opts \\ []) do
    trace_path = Keyword.get_lazy(opts, :trace_path, &tmp_trace_path/0)
    messages = Keyword.get(opts, :messages, default_messages())
    mock_response = Keyword.get(opts, :mock_response, "mock single-node completion")

    :ok = File.mkdir_p!(Path.dirname(trace_path))
    File.rm(trace_path)

    with {:ok, _apps} <- Application.ensure_all_started(:trinity_single_node),
         {:ok, route} <- route(messages, opts, trace_path),
         {:ok, provider_receipt} <- dispatch(route, messages, mock_response, opts, trace_path) do
      decision = route.decision
      direct_dependency_apps = direct_dependency_apps()

      forbidden_dependency_apps =
        Enum.filter(direct_dependency_apps, &(&1 in @forbidden_dependency_apps))

      trace_events = read_trace_events(trace_path)

      {:ok,
       %Receipt{
         receipt_ref: "stack-lab-trinity-single-node-roundtrip://mock-tiny",
         fixture_refs: @fixture_refs,
         status: status(forbidden_dependency_apps, trace_events, provider_receipt),
         runtime_profile: :mock_tiny,
         direct_dependency_apps: direct_dependency_apps,
         forbidden_dependency_apps: forbidden_dependency_apps,
         selected_agent_id: decision.selected_agent_id,
         selected_role_id: decision.selected_role_id,
         role_name: decision.role_name,
         token_count: decision.token_count,
         transcript_hash: decision.transcript_hash,
         route_hash: decision.route_hash,
         provider_status: provider_receipt.status,
         provider_ref: provider_receipt.response_ref,
         trace_path: trace_path,
         trace_events: trace_events
       }}
    end
  end

  @spec direct_dependency_apps() :: [atom()]
  def direct_dependency_apps do
    Mix.Project.config()
    |> Keyword.fetch!(:deps)
    |> Enum.map(fn
      {app, _requirement_or_opts} -> app
      {app, _requirement, _opts} -> app
    end)
    |> Enum.sort()
  end

  defp status([], [_route_event, _provider_event | _rest], %{status: :ok}), do: :pass
  defp status(_forbidden_deps, _trace_events, _provider_receipt), do: :open_defect

  defp read_trace_events(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
  end

  defp default_messages do
    [%{role: "user", content: "Route this deterministic prompt."}]
  end

  defp route(messages, opts, trace_path) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(single_node(), :route, [
      messages,
      [
        runtime_profile: :mock_tiny,
        trace_path: trace_path,
        timestamp_ms: Keyword.get(opts, :timestamp_ms, 1_700_000_000_000)
      ]
    ])
  end

  defp dispatch(route, messages, mock_response, opts, trace_path) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(single_node(), :dispatch, [
      route,
      messages,
      [
        provider_pool: :mock,
        mock_response: mock_response,
        trace_path: trace_path,
        timestamp_ms: Keyword.get(opts, :timestamp_ms, 1_700_000_000_000)
      ]
    ])
  end

  defp single_node, do: Module.concat([Trinity, SingleNode])

  defp tmp_trace_path do
    Path.join(
      System.tmp_dir!(),
      "stack-lab-trinity-single-node-#{System.unique_integer([:positive])}.jsonl"
    )
  end
end
