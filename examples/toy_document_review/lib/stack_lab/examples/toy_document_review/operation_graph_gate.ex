defmodule StackLab.Examples.ToyDocumentReview.OperationGraphGate do
  @moduledoc """
  Deterministic operation graph proof for the neutral document-review product.
  """

  alias Mezzanine.WorkflowRuntime.OperationGraphExecutor

  @document_source "node://toy-document-review/document-source"
  @review_extract_tool "node://toy-document-review/review-extract-tool"
  @review_runtime "node://toy-document-review/review-runtime"
  @review_evidence "node://toy-document-review/review-evidence"
  @review_publication "node://toy-document-review/review-publication"
  @archive_effect "node://toy-document-review/archive-effect"

  @nodes [
    %{
      node_ref: @document_source,
      operation_role_ref: "document_source",
      operation_class: :source_read,
      projection_order_key: 10
    },
    %{
      node_ref: @review_extract_tool,
      operation_role_ref: "review_extract_tool",
      operation_class: :runtime_tool_invocation,
      projection_order_key: 20
    },
    %{
      node_ref: @review_runtime,
      operation_role_ref: "review_runtime",
      operation_class: :runtime_session,
      projection_order_key: 30
    },
    %{
      node_ref: @review_evidence,
      operation_role_ref: "review_evidence",
      operation_class: :evidence_collection,
      projection_order_key: 40
    },
    %{
      node_ref: @review_publication,
      operation_role_ref: "review_publication",
      operation_class: :source_write,
      projection_order_key: 50
    },
    %{
      node_ref: @archive_effect,
      operation_role_ref: "archive_effect",
      operation_class: :resource_effect,
      projection_order_key: 60
    }
  ]

  @node_refs %{
    document_source: @document_source,
    review_extract_tool: @review_extract_tool,
    review_runtime: @review_runtime,
    review_evidence: @review_evidence,
    review_publication: @review_publication,
    archive_effect: @archive_effect
  }

  @doc "Returns the proof graph consumed by the deterministic operation graph gate."
  @spec graph() :: map()
  def graph do
    %{
      graph_ref: "operation-graph://toy-document-review/review-run",
      nodes: @nodes,
      dependencies: dependencies()
    }
  end

  @doc "Returns stable node refs used by the proof."
  @spec node_refs() :: map()
  def node_refs, do: @node_refs

  @doc "Runs the deterministic graph-shape proof for the neutral product."
  @spec run() :: {:ok, map()}
  def run do
    graph = graph()

    source_first =
      reduce_events([
        event(@document_source, :succeeded),
        event(@review_extract_tool, :succeeded)
      ])

    tool_first =
      reduce_events([
        event(@review_extract_tool, :succeeded),
        event(@document_source, :succeeded)
      ])

    runtime_ready_from_source_first = ready_node_refs(source_first)
    runtime_ready_from_tool_first = ready_node_refs(tool_first)
    publication_facts = publication_gate_facts()

    with {:ok, publication_intents} <-
           OperationGraphExecutor.ready_activity_intents(
             graph,
             publication_facts,
             intent_attrs()
           ) do
      {:ok,
       %{
         graph: %{
           graph_ref: graph.graph_ref,
           node_count: length(graph.nodes),
           dependency_count: length(graph.dependencies),
           dependency_relations: dependency_relations()
         },
         initial_ready_node_refs: ready_node_refs(%{}),
         one_branch_ready_node_refs:
           ready_node_refs(reduce_events([event(@document_source, :succeeded)])),
         alternate_completion_orders: %{
           source_first_ready_node_refs: runtime_ready_from_source_first,
           tool_first_ready_node_refs: runtime_ready_from_tool_first,
           converge?: runtime_ready_from_source_first == runtime_ready_from_tool_first,
           projection_signatures: [
             projection_signature(runtime_ready_from_source_first),
             projection_signature(runtime_ready_from_tool_first)
           ]
         },
         review_confirmation_gate: %{
           before_review_ready_node_refs: ready_node_refs(runtime_succeeded_facts()),
           before_confirmation_ready_node_refs: ready_node_refs(runtime_reviewed_facts()),
           after_confirmation_ready_node_refs: ready_node_refs(publication_facts)
         },
         optional_branch_failure: %{
           failed_node_ref: @review_evidence,
           ready_node_refs: ready_node_refs(publication_facts),
           allows_publication?: @review_publication in ready_node_refs(publication_facts)
         },
         concurrent_runtime_evidence_branch: concurrent_runtime_evidence_branch(),
         retry_cancellation_exclusion: %{
           retry_ready_node_refs:
             publication_facts
             |> Map.put(:retry_node_refs, [@review_publication])
             |> ready_node_refs(),
           canceled_ready_node_refs:
             publication_facts
             |> Map.put(:canceled_node_refs, [@review_publication])
             |> ready_node_refs()
         },
         publication_activity_intents: publication_intents
       }}
    end
  end

  defp dependency(from_node_ref, to_node_ref, relation, completion_policy) do
    %{
      dependency_ref:
        "dependency://toy-document-review/#{role_ref(from_node_ref)}/#{role_ref(to_node_ref)}/#{Atom.to_string(relation)}",
      from_node_ref: from_node_ref,
      to_node_ref: to_node_ref,
      relation: relation,
      completion_policy: completion_policy
    }
  end

  defp dependencies do
    [
      dependency(@document_source, @review_extract_tool, :parallel_allowed, :required),
      dependency(@document_source, @review_runtime, :blocks_on_success, :required),
      dependency(@review_extract_tool, @review_runtime, :blocks_on_success, :required),
      dependency(@review_runtime, @review_evidence, :blocks_on_success, :required),
      dependency(@review_runtime, @review_publication, :blocks_on_success, :required),
      dependency(@review_runtime, @review_publication, :blocks_on_review, :required),
      dependency(@review_runtime, @review_publication, :blocks_on_confirmation, :required),
      dependency(@review_evidence, @review_publication, :blocks_on_success, :optional),
      dependency(@review_publication, @archive_effect, :blocks_on_success, :required)
    ]
  end

  defp concurrent_runtime_evidence_branch do
    graph = %{
      graph_ref: "operation-graph://toy-document-review/concurrent-runtime-evidence",
      nodes:
        Enum.filter(@nodes, fn node ->
          node.node_ref in [
            @document_source,
            @review_runtime,
            @review_evidence,
            @review_publication
          ]
        end),
      dependencies: [
        dependency(@document_source, @review_runtime, :blocks_on_success, :required),
        dependency(@document_source, @review_evidence, :blocks_on_success, :required),
        dependency(@review_runtime, @review_publication, :blocks_on_success, :required),
        dependency(@review_evidence, @review_publication, :blocks_on_success, :required)
      ]
    }

    source_done = reduce_events([event(@document_source, :succeeded)])

    runtime_first =
      reduce_events([
        event(@document_source, :succeeded),
        event(@review_runtime, :succeeded)
      ])

    evidence_first =
      reduce_events([
        event(@document_source, :succeeded),
        event(@review_evidence, :succeeded)
      ])

    both_done =
      reduce_events([
        event(@document_source, :succeeded),
        event(@review_runtime, :succeeded),
        event(@review_evidence, :succeeded)
      ])

    %{
      graph_ref: graph.graph_ref,
      source_done_ready_node_refs: ready_node_refs(graph, source_done),
      runtime_first_ready_node_refs: ready_node_refs(graph, runtime_first),
      evidence_first_ready_node_refs: ready_node_refs(graph, evidence_first),
      both_done_ready_node_refs: ready_node_refs(graph, both_done),
      alternate_completion_orders_converge?:
        ready_node_refs(graph, both_done) == [@review_publication]
    }
  end

  defp ready_node_refs(facts), do: ready_node_refs(graph(), facts)

  defp ready_node_refs(graph, facts), do: OperationGraphExecutor.ready_node_refs(graph, facts)

  defp reduce_events(events) do
    events
    |> Enum.reduce(empty_facts(), &apply_event/2)
    |> normalize_fact_lists()
  end

  defp apply_event(%{node_ref: node_ref, status: :succeeded, event_ref: event_ref}, facts) do
    facts
    |> update_fact_refs(:succeeded_node_refs, node_ref)
    |> put_in([:terminal_event_refs_by_node_ref, node_ref], event_ref)
  end

  defp apply_event(%{node_ref: node_ref, status: :failed, event_ref: event_ref}, facts) do
    facts
    |> update_fact_refs(:failed_node_refs, node_ref)
    |> put_in([:terminal_event_refs_by_node_ref, node_ref], event_ref)
  end

  defp empty_facts do
    %{
      succeeded_node_refs: [],
      reviewed_node_refs: [],
      confirmed_node_refs: [],
      failed_node_refs: [],
      terminal_event_refs_by_node_ref: %{},
      review_event_refs_by_node_ref: %{},
      confirmation_event_refs_by_node_ref: %{}
    }
  end

  defp update_fact_refs(facts, key, node_ref) do
    Map.update!(facts, key, &[node_ref | &1])
  end

  defp normalize_fact_lists(facts) do
    facts
    |> Map.update!(:succeeded_node_refs, &Enum.reverse/1)
    |> Map.update!(:reviewed_node_refs, &Enum.reverse/1)
    |> Map.update!(:confirmed_node_refs, &Enum.reverse/1)
    |> Map.update!(:failed_node_refs, &Enum.reverse/1)
  end

  defp event(node_ref, status) do
    %{
      node_ref: node_ref,
      status: status,
      event_ref: "event://toy-document-review/#{role_ref(node_ref)}/#{Atom.to_string(status)}"
    }
  end

  defp runtime_succeeded_facts do
    [
      event(@document_source, :succeeded),
      event(@review_extract_tool, :succeeded),
      event(@review_runtime, :succeeded)
    ]
    |> reduce_events()
  end

  defp runtime_reviewed_facts do
    runtime_succeeded_facts()
    |> update_fact_refs(:reviewed_node_refs, @review_runtime)
    |> put_in(
      [:review_event_refs_by_node_ref, @review_runtime],
      "event://toy-document-review/review-runtime/reviewed"
    )
    |> normalize_fact_lists()
  end

  defp publication_gate_facts do
    runtime_reviewed_facts()
    |> update_fact_refs(:confirmed_node_refs, @review_runtime)
    |> put_in(
      [:confirmation_event_refs_by_node_ref, @review_runtime],
      "event://toy-document-review/review-runtime/confirmed"
    )
    |> then(&apply_event(event(@review_evidence, :failed), &1))
    |> normalize_fact_lists()
  end

  defp intent_attrs do
    %{
      workflow_run_ref: "workflow-run://toy-document-review/review-run",
      operation_context_ref: "operation-context://toy-document-review/graph-gate",
      operation_plans_by_node_ref: %{
        @review_publication => "operation-plan://toy-document-review/review-publication"
      },
      retry_policies_by_node_ref: %{
        @review_publication => %{max_attempts: 2, backoff: :linear}
      },
      timeout_policies_by_node_ref: %{
        @review_publication => %{timeout_ms: 30_000}
      },
      cancellation_policies_by_node_ref: %{
        @review_publication => %{
          cancellation_scope_ref: "cancel://toy-document-review/review-run"
        }
      }
    }
  end

  defp dependency_relations do
    dependencies()
    |> Enum.map(& &1.relation)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp projection_signature(node_refs) do
    Enum.map_join(node_refs, ">", &role_ref/1)
  end

  defp role_ref(@document_source), do: "document_source"
  defp role_ref(@review_extract_tool), do: "review_extract_tool"
  defp role_ref(@review_runtime), do: "review_runtime"
  defp role_ref(@review_evidence), do: "review_evidence"
  defp role_ref(@review_publication), do: "review_publication"
  defp role_ref(@archive_effect), do: "archive_effect"
end
