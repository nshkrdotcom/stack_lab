defmodule StackLab.Examples.ToyDocumentReview.LocalHttpService do
  @moduledoc false

  use GenServer

  @schema_version "toy-document-review.v1"
  @default_lease_ref "credential-lease://toy-document-review/local-http/1"
  @default_latency_ms 25

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @impl true
  def init(opts) do
    state = %{
      accepted_credential_lease_ref:
        Keyword.get(opts, :accepted_credential_lease_ref, @default_lease_ref),
      latency_ms: Keyword.get(opts, :latency_ms, @default_latency_ms),
      documents: documents(),
      events: events(),
      archived: MapSet.new()
    }

    {:ok, state}
  end

  def default_lease_ref, do: @default_lease_ref
  def schema_version, do: @schema_version

  def request(server, method, path, opts \\ []) when is_list(opts) do
    GenServer.call(server, {:request, method, path, opts})
  end

  def refresh_lease(server, lease_ref) when is_binary(lease_ref) do
    GenServer.call(server, {:refresh_lease, lease_ref})
  end

  @impl true
  def handle_call({:refresh_lease, lease_ref}, _from, state) do
    {:reply, {:ok, %{credential_lease_ref: lease_ref}},
     %{state | accepted_credential_lease_ref: lease_ref}}
  end

  def handle_call({:request, method, path, opts}, _from, state) do
    case validate_request(state, opts) do
      :ok ->
        {reply, next_state} = route(method, path, opts, state)
        {:reply, reply, next_state}

      {:error, response} ->
        {:reply, {:error, response}, state}
    end
  end

  defp validate_request(state, opts) do
    cond do
      Keyword.get(opts, :credential_lease_ref) != state.accepted_credential_lease_ref ->
        {:error, %{status: 401, reason: :auth_rejected}}

      Keyword.get(opts, :schema_version, @schema_version) != @schema_version ->
        {:error, %{status: 409, reason: :schema_version_mismatch}}

      expired?(opts) ->
        {:error, %{status: 401, reason: :credential_expired, retryable?: true}}

      timeout?(state, opts) ->
        {:error, %{status: 504, reason: :timeout, retryable?: true}}

      true ->
        :ok
    end
  end

  defp route(:get, "/documents", opts, state) do
    case Keyword.get(opts, :failure_mode) do
      :retryable ->
        {{:error, %{status: 503, reason: :retryable_failure, retryable?: true}}, state}

      :terminal ->
        {{:error, %{status: 422, reason: :terminal_failure, retryable?: false}}, state}

      _other ->
        {{:ok,
          %{
            status: 200,
            body: %{documents: state.documents, latency_ms: state.latency_ms},
            headers: %{"x-schema-version" => @schema_version}
          }}, state}
    end
  end

  defp route(:post, "/reviews", opts, state) do
    document_id = input_value(opts, :document_id, "doc-001")

    {{:ok,
      %{
        status: 202,
        body: %{
          publication_ref: "publication://toy-document-review/#{document_id}",
          state: "reviewed"
        },
        headers: %{"x-schema-version" => @schema_version}
      }}, state}
  end

  defp route(:post, "/runtime/review", opts, state) do
    document_id = input_value(opts, :document_id, "doc-001")

    {{:ok,
      %{
        status: 200,
        body: %{
          runtime_result_ref: "runtime-result://toy-document-review/#{document_id}",
          findings: ["missing-title", "requires-operator-summary"],
          disposition: "needs_summary"
        },
        headers: %{"x-schema-version" => @schema_version}
      }}, state}
  end

  defp route(:post, "/tools/extract", opts, state) do
    document_id = input_value(opts, :document_id, "doc-001")

    {{:ok,
      %{
        status: 200,
        body: %{
          tool_result_ref: "tool-result://toy-document-review/#{document_id}/extract",
          fields: %{"title" => nil, "risk" => "medium"}
        },
        headers: %{"x-schema-version" => @schema_version}
      }}, state}
  end

  defp route(:post, "/evidence/collect", opts, state) do
    document_id = input_value(opts, :document_id, "doc-001")

    {{:ok,
      %{
        status: 200,
        body: %{
          evidence_ref: "evidence://toy-document-review/#{document_id}/review-report",
          artifacts: ["artifact://toy-document-review/#{document_id}/report"]
        },
        headers: %{"x-schema-version" => @schema_version}
      }}, state}
  end

  defp route(:post, "/effects/archive", opts, state) do
    document_id = input_value(opts, :document_id, "doc-001")
    next_state = %{state | archived: MapSet.put(state.archived, document_id)}

    {{:ok,
      %{
        status: 200,
        body: %{
          effect_ref: "effect://toy-document-review/#{document_id}/archive",
          archived?: true
        },
        headers: %{"x-schema-version" => @schema_version}
      }}, next_state}
  end

  defp route(:get, "/events", opts, state) do
    cursor = Keyword.get(opts, :cursor, 0)
    page_size = Keyword.get(opts, :page_size, 2)
    {page, remaining} = Enum.split(Enum.drop(state.events, cursor), page_size)
    next_cursor = if remaining == [], do: nil, else: cursor + length(page)

    {{:ok,
      %{
        status: 200,
        body: %{events: page, next_cursor: next_cursor},
        headers: %{"x-schema-version" => @schema_version}
      }}, state}
  end

  defp route(_method, path, _opts, state) do
    {{:error, %{status: 404, reason: {:not_found, path}, retryable?: false}}, state}
  end

  defp expired?(opts) do
    case Keyword.get(opts, :lease_expires_at) do
      nil -> false
      expires_at -> DateTime.compare(expires_at, Keyword.fetch!(opts, :now)) != :gt
    end
  end

  defp timeout?(state, opts) do
    case Keyword.get(opts, :timeout_ms) do
      nil -> false
      timeout_ms -> timeout_ms < state.latency_ms
    end
  end

  defp input_value(opts, key, default) do
    opts
    |> Keyword.get(:input, %{})
    |> Map.get(key, default)
  end

  defp documents do
    [
      %{id: "doc-001", state: "submitted", title: nil, ordinal: 1},
      %{id: "doc-002", state: "submitted", title: "Supplier Brief", ordinal: 2}
    ]
  end

  defp events do
    [
      %{event_ref: "event://toy-document-review/1", sequence: 1, kind: "document.submitted"},
      %{event_ref: "event://toy-document-review/2", sequence: 2, kind: "review.started"},
      %{event_ref: "event://toy-document-review/3", sequence: 3, kind: "review.completed"}
    ]
  end
end
