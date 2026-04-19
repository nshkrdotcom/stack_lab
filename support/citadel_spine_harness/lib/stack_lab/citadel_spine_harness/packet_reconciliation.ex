defmodule StackLab.CitadelSpineHarness.PacketReconciliation do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  @current_file Path.expand(__ENV__.file)
  @stack_ir_doc "v4/0017_stack_ir_and_binding_map.md"
  @orchestration_doc "v4/0020_oban_hybrid_orchestration_architecture.md"
  @read_plane_doc "v4/0022_leased_read_stream_plane_and_bff_schema_registry.md"
  @aitrace_doc "v4/0023_aitrace_identity_and_claim_check_contract.md"
  @trace_doc "v4/0026_trace_identity_contract.md"

  @app_kit_bypass_patterns [
    ~r/\bJido\.Integration\b/,
    ~r/\bExecutionPlane\b/,
    ~r/\bHostIngress\b/,
    ~r/\bInvocationBridge\b/
  ]

  @stale_harness_patterns [
    ~r/jido_integration_v2_contracts/,
    ~r/\bDispatchOutboxEntry\b/,
    ~r/\bDispatcher\b/,
    ~r/dispatch_outbox_entry_id/
  ]

  @substrate_ingress_host_patterns [
    ~r/\bCitadel\.HostIngress\b/,
    ~r/\bHostIngress\.compile_run_request\b/,
    ~r/\bMezzanine\.CitadelBridge\.\{AuthorityAssembler,\s*RunIntentCompiler\}/,
    ~r/\bAuthorityAssembler\b/,
    ~r/\bRunIntentCompiler\b/,
    ~r/\bSessionServer\b/,
    ~r/\bSessionDirectory\b/,
    ~r/\bSessionContinuityCommit\b/,
    ~r/\bPersistedSessionBlob\b/,
    ~r/\bPersistedSessionEnvelope\b/
  ]

  @spec run_case(
          :packet_ownership_freeze
          | :stack_ir_binding_map_freeze
          | :control_path_boundaries
          | :stale_reference_absence
          | :substrate_origin_no_host_session_path
          | :direct_execution_plane_bypass_absence
        ) ::
          {:ok, map()}
  def run_case(:packet_ownership_freeze) do
    docs_root = CitadelSpineHarness.repo_roots().docs

    orchestration_doc = Path.join(docs_root, @orchestration_doc)
    read_plane_doc = Path.join(docs_root, @read_plane_doc)
    aitrace_doc = Path.join(docs_root, @aitrace_doc)
    trace_doc = Path.join(docs_root, @trace_doc)

    assert_contains!(
      orchestration_doc,
      [
        "Mezzanine.JobOutbox",
        "outbox polling, custom database leasing, synchronous held-process waiting",
        "The loop is strictly asynchronous."
      ]
    )

    assert_contains!(
      read_plane_doc,
      [
        "governed writes and mutations stay on the full control path",
        "reads and streams may use a leased direct lower path",
        "`PG NOTIFY` is optional as a latency optimization and is never the truth"
      ]
    )

    assert_contains!(
      aitrace_doc,
      [
        "The stack's common cross-layer incident key is `trace_id`.",
        "payloads larger than 64 KiB must use claim-check",
        "writing a success-path row first and attaching the claim-check reference later"
      ]
    )

    assert_contains!(
      trace_doc,
      [
        "`trace_id` is a 16-byte value rendered as 32 lowercase hexadecimal characters.",
        "`app_kit` mints `trace_id` at the request edge when absent."
      ]
    )

    {:ok,
     %{
       case: :packet_ownership_freeze,
       docs: %{
         orchestration: orchestration_doc,
         read_plane: read_plane_doc,
         aitrace: aitrace_doc,
         trace: trace_doc
       },
       anchors: %{
         dispatch_seam: "Mezzanine.JobOutbox",
         write_path: "strict governed path",
         read_lease: "leased direct lower path",
         trace_key: "trace_id",
         notify_posture: "latency optimization",
         claim_check: "pre-transaction"
       }
     }}
  end

  def run_case(:stack_ir_binding_map_freeze) do
    roots = CitadelSpineHarness.repo_roots()
    docs_root = roots.docs

    stack_ir_doc = Path.join(docs_root, @stack_ir_doc)
    read_plane_doc = Path.join(docs_root, @read_plane_doc)
    trace_doc = Path.join(docs_root, @trace_doc)

    assert_contains!(
      stack_ir_doc,
      [
        "ExecutionRecord(submission_dedupe_key)",
        "`ReadLease` / `StreamAttachLease`",
        "`schema_ref` and `schema_version` freeze opaque payload-envelope contracts for",
        "northbound BFF surfaces",
        "direct lower reads and stream attaches derive lower lineage from",
        "they do not accept caller-supplied",
        "lower ids as the primary key"
      ]
    )

    assert_contains!(
      read_plane_doc,
      [
        "## 2. `ReadLease` And `StreamAttachLease`",
        "Required fields:",
        "- `trace_id`",
        "`allowed_operations = [\"fetch_run\", \"events\", \"attempts\", \"run_artifacts\"]`",
        "payload bodies may remain opaque maps validated by `schema_ref` and",
        "`schema_version`"
      ]
    )

    assert_contains!(
      trace_doc,
      [
        "`app_kit` mints `trace_id` at the request edge when absent.",
        "Caller-supplied `trace_id` is validated against the W3C format."
      ]
    )

    code_anchors = %{
      boundary_generator: Path.join(roots.app_kit, "lib/app_kit/workspace/boundary_generator.ex"),
      workspace_contract: Path.join(roots.app_kit, "test/app_kit/workspace_test.exs"),
      read_lease: Path.join(roots.mezzanine, "core/leasing/lib/mezzanine/read_lease.ex"),
      stream_attach_lease:
        Path.join(roots.mezzanine, "core/leasing/lib/mezzanine/stream_attach_lease.ex"),
      execution_record:
        Path.join(
          roots.mezzanine,
          "core/execution_engine/lib/mezzanine/execution/execution_record.ex"
        ),
      operator_services_test:
        Path.join(
          roots.app_kit,
          "bridges/mezzanine_bridge/test/mezzanine_app_kit_bridge_operator_services_test.exs"
        )
    }

    assert_contains!(code_anchors.boundary_generator, [
      "@enforce_keys [:schema_ref, :schema_version]"
    ])

    assert_contains!(code_anchors.workspace_contract, ["schema_ref", "schema_version"])

    assert_contains!(
      code_anchors.read_lease,
      [
        "field(:trace_id, :string)",
        "field(:allowed_family, :string)",
        "field(:allowed_operations, {:array, :string}, default: [])"
      ]
    )

    assert_contains!(
      code_anchors.stream_attach_lease,
      [
        "field(:trace_id, :string)",
        "field(:allowed_family, :string)"
      ]
    )

    assert_contains!(code_anchors.execution_record, ["submission_dedupe_key"])

    assert_contains!(
      code_anchors.operator_services_test,
      [
        "assert read_lease.allowed_family == \"unified_trace\"",
        "\"attempts\"",
        "\"events\"",
        "\"fetch_run\"",
        "\"run_artifacts\""
      ]
    )

    {:ok,
     %{
       case: :stack_ir_binding_map_freeze,
       docs: %{
         stack_ir: stack_ir_doc,
         read_plane: read_plane_doc,
         trace: trace_doc
       },
       code_anchors: Map.keys(code_anchors)
     }}
  end

  def run_case(:control_path_boundaries) do
    roots = CitadelSpineHarness.repo_roots()

    {:ok, extravaganza_report} =
      run_no_bypass_scan(roots,
        root: roots.extravaganza,
        profiles: [:product],
        include: [
          "apps/extravaganza_core/lib/**/*.ex",
          "apps/extravaganza_web/lib/**/*.ex"
        ]
      )

    app_kit_files =
      scan_absence!(
        [
          Path.join(roots.app_kit, "core/**/*.ex"),
          Path.join(roots.app_kit, "bridges/**/*.ex"),
          Path.join(roots.app_kit, "core/*/mix.exs"),
          Path.join(roots.app_kit, "bridges/*/mix.exs")
        ],
        @app_kit_bypass_patterns
      )

    {:ok,
     %{
       case: :control_path_boundaries,
       scanner: :app_kit_no_bypass,
       checked_files: %{
         extravaganza: extravaganza_report.checked_files,
         app_kit: length(app_kit_files)
       }
     }}
  end

  def run_case(:stale_reference_absence) do
    roots = CitadelSpineHarness.repo_roots()

    checked_files =
      scan_absence!(
        [
          Path.join(roots.stack_lab, "support/citadel_spine_harness/**/*.ex"),
          Path.join(roots.stack_lab, "support/citadel_spine_harness/README.md"),
          Path.join(roots.stack_lab, "README.md")
        ],
        @stale_harness_patterns,
        exclude: [@current_file]
      )

    {:ok,
     %{
       case: :stale_reference_absence,
       checked_files: length(checked_files)
     }}
  end

  def run_case(:substrate_origin_no_host_session_path) do
    roots = CitadelSpineHarness.repo_roots()

    checked_files =
      scan_absence!(
        [
          Path.join(
            roots.stack_lab,
            "support/citadel_spine_harness/lib/stack_lab/citadel_spine_harness/app_kit_operational_surface.ex"
          )
        ],
        @substrate_ingress_host_patterns
      )

    {:ok,
     %{
       case: :substrate_origin_no_host_session_path,
       checked_files: length(checked_files),
       active_surface: List.first(checked_files)
     }}
  end

  def run_case(:direct_execution_plane_bypass_absence) do
    roots = CitadelSpineHarness.repo_roots()

    {:ok, extravaganza_report} =
      run_no_bypass_scan(roots,
        root: roots.extravaganza,
        profiles: [:hazmat],
        include: [
          "apps/extravaganza_core/lib/**/*.ex",
          "apps/extravaganza_web/lib/**/*.ex"
        ]
      )

    {:ok, app_kit_report} =
      run_no_bypass_scan(roots,
        root: roots.app_kit,
        profiles: [:hazmat],
        include: [
          "core/**/*.ex",
          "bridges/**/*.ex",
          "examples/**/*.ex"
        ]
      )

    {:ok,
     %{
       case: :direct_execution_plane_bypass_absence,
       scanner: :app_kit_no_bypass,
       checked_files: %{
         extravaganza: extravaganza_report.checked_files,
         app_kit: app_kit_report.checked_files
       }
     }}
  end

  defp assert_contains!(path, required_fragments) do
    contents = File.read!(path)

    Enum.each(required_fragments, fn fragment ->
      if not String.contains?(contents, fragment) do
        raise "#{path} is missing required fragment: #{fragment}"
      end
    end)
  end

  defp scan_absence!(patterns, banned_patterns, opts \\ []) do
    excluded = Keyword.get(opts, :exclude, [])

    checked_files =
      patterns
      |> Enum.flat_map(&Path.wildcard(&1, match_dot: true))
      |> Enum.uniq()
      |> Enum.reject(&(&1 in excluded))

    Enum.each(checked_files, &assert_absent!(&1, banned_patterns))

    checked_files
  end

  defp assert_absent!(path, banned_patterns) do
    contents = File.read!(path)

    Enum.each(banned_patterns, fn banned_pattern ->
      if Regex.match?(banned_pattern, contents) do
        raise "#{path} still matches banned pattern #{inspect(banned_pattern)}"
      end
    end)
  end

  defp no_bypass_module(roots) do
    unless Code.ensure_loaded?(AppKit.Boundary.NoBypass) do
      Code.require_file(Path.join(roots.app_kit, "lib/app_kit/boundary/no_bypass.ex"))
    end

    AppKit.Boundary.NoBypass
  end

  defp run_no_bypass_scan(roots, opts) do
    scanner = Function.capture(no_bypass_module(roots), :scan, 1)

    scanner.(opts)
  end
end
