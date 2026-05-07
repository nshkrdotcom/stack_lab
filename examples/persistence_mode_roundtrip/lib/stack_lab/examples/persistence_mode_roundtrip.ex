defmodule StackLab.Examples.PersistenceModeRoundtrip.ProfileReceipt do
  @moduledoc "One deterministic persistence profile receipt."
  @enforce_keys [
    :profile_id,
    :selected_tier,
    :store_set_id,
    :capture_level,
    :proof_command,
    :durable_opt_in?,
    :durable_tag,
    :preflight,
    :storage_behavior_ref,
    :authority_semantics_ref,
    :restart_claim,
    :debug_event,
    :debug_result,
    :gn_ten_receipt
  ]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end

defmodule StackLab.Examples.PersistenceModeRoundtrip.Receipt do
  @moduledoc "Deterministic persistence profile matrix receipt."
  @enforce_keys [
    :receipt_ref,
    :fixture_refs,
    :fixture_mappings,
    :status,
    :provider_dependency?,
    :postgres_dependency?,
    :temporal_dependency?,
    :object_store_dependency?,
    :network_dependency?,
    :external_substrate_dependency?,
    :debug_sidecar_dependency?,
    :storage_behavior_switch?,
    :authority_semantics_ref,
    :authority_semantics_stable?,
    :profile_receipts,
    :matrix_scan
  ]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end

defmodule StackLab.Examples.PersistenceModeRoundtrip do
  @moduledoc """
  Deterministic persistence profile matrix proof.
  """

  alias GroundPlane.PersistencePolicy
  alias GroundPlane.PersistencePolicy.DebugTap
  alias StackLab.Examples.PersistenceModeRoundtrip.{ProfileReceipt, Receipt}
  alias StackLab.PersistenceMatrixScanner

  @fixture_refs [
    "PERSIST-001",
    "PERSIST-002",
    "PERSIST-003",
    "PERSIST-004",
    "PERSIST-005",
    "PERSIST-006",
    "PERSIST-007",
    "PERSIST-008",
    "PERSIST-009",
    "PERSIST-010",
    "PERSIST-011",
    "PERSIST-012",
    "PERSIST-013",
    "PERSIST-014",
    "PERSIST-015",
    "PERSIST-016",
    "PERSIST-017",
    "PERSIST-018",
    "PERSIST-019",
    "PERSIST-020"
  ]
  @profiles [:mickey_mouse, :memory_debug, :integration_postgres, :full_debug_tracked]
  @proof_command "mix test --color"
  @durable_tag "persistence-durable-opt-in"
  @authority_semantics_ref "authority-semantics://phase-10/governed-provider/decision-v1"
  @source_paths [
    "examples/persistence_mode_roundtrip/lib/stack_lab/examples/persistence_mode_roundtrip.ex",
    "support/persistence_matrix_scanner/lib/stack_lab/persistence_matrix_scanner.ex"
  ]
  @test_paths [
    "examples/persistence_mode_roundtrip/test/stack_lab/examples/persistence_mode_roundtrip_test.exs",
    "support/persistence_matrix_scanner/test/stack_lab/persistence_matrix_scanner_test.exs"
  ]
  @docs_paths [
    "README.md",
    "docs/gn_ten_proof_matrix.md",
    "examples/persistence_mode_roundtrip/README.md",
    "support/persistence_matrix_scanner/README.md"
  ]
  @receipt_paths [
    "receipt.fixture_mappings",
    "receipt.profile_receipts",
    "receipt.matrix_scan"
  ]
  @fixture_scanner_rules %{
    "PERSIST-001" => [
      :memory_default,
      :no_default_provider,
      :no_default_postgres,
      :temporal_disabled_by_default,
      :no_default_object_store,
      :no_default_network,
      :optional_external_substrate_disabled_by_default,
      :no_default_debug_sidecar
    ],
    "PERSIST-002" => [:memory_default, :authority_semantics_stable],
    "PERSIST-003" => [:profile_coverage, :storage_behavior_switch],
    "PERSIST-004" => [:restart_claim_classification],
    "PERSIST-005" => [:durable_opt_in_tag, :storage_behavior_switch],
    "PERSIST-006" => [:durable_opt_in_tag, :restart_claim_classification],
    "PERSIST-007" => [
      :memory_default,
      :no_default_postgres,
      :temporal_disabled_by_default,
      :no_default_object_store,
      :optional_external_substrate_disabled_by_default
    ],
    "PERSIST-008" => [:debug_redaction],
    "PERSIST-009" => [:debug_redaction, :authority_semantics_stable],
    "PERSIST-010" => [:storage_behavior_switch],
    "PERSIST-011" => [:memory_default, :restart_claim_classification],
    "PERSIST-012" => [:durable_opt_in_tag, :restart_claim_classification],
    "PERSIST-013" => [:optional_external_substrate_disabled_by_default],
    "PERSIST-014" => [:profile_coverage],
    "PERSIST-015" => [:knob_docs],
    "PERSIST-016" => [:product_no_bypass],
    "PERSIST-017" => [:no_default_provider],
    "PERSIST-018" => [:storage_behavior_switch, :authority_semantics_stable],
    "PERSIST-019" => [:restart_claim_classification],
    "PERSIST-020" => [
      :gn_ten_profile_field,
      :gn_ten_tier_field,
      :gn_ten_store_field,
      :gn_ten_capture_field,
      :gn_ten_proof_command_field
    ]
  }

  @spec run() :: {:ok, Receipt.t()} | {:error, term()}
  def run do
    with {:ok, profile_receipts} <- build_profile_receipts(),
         fixture_mappings <- fixture_mappings(),
         {:ok, matrix_scan} <-
           PersistenceMatrixScanner.scan(scanner_input(profile_receipts, fixture_mappings)) do
      {:ok,
       %Receipt{
         receipt_ref: "persistence-mode-roundtrip://phase-10/full-profile-matrix",
         fixture_refs: @fixture_refs,
         fixture_mappings: fixture_mappings,
         status: status(profile_receipts, matrix_scan),
         provider_dependency?: false,
         postgres_dependency?: false,
         temporal_dependency?: false,
         object_store_dependency?: false,
         network_dependency?: false,
         external_substrate_dependency?: false,
         debug_sidecar_dependency?: false,
         storage_behavior_switch?: storage_behavior_switch?(profile_receipts),
         authority_semantics_ref: @authority_semantics_ref,
         authority_semantics_stable?: authority_semantics_stable?(profile_receipts),
         profile_receipts: profile_receipts,
         matrix_scan: matrix_scan
       }}
    end
  end

  defp build_profile_receipts do
    @profiles
    |> Enum.reduce_while({:ok, []}, fn profile_id, {:ok, receipts} ->
      case build_profile_receipt(profile_id) do
        {:ok, receipt} -> {:cont, {:ok, receipts ++ [receipt]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_profile_receipt(profile_id) do
    with {:ok, profile} <- PersistencePolicy.resolve(profile: profile_id),
         {:ok, capabilities} <- capabilities_for(profile),
         preflight <- PersistencePolicy.preflight(profile, capabilities, &mock_preflight/1),
         {:ok, debug_result} <- emit_debug(profile),
         :ok <- normalize_preflight(preflight) do
      {:ok,
       %ProfileReceipt{
         profile_id: profile.id,
         selected_tier: profile.default_tier,
         store_set_id: profile.store_set.id,
         capture_level: profile.capture_level,
         proof_command: @proof_command,
         durable_opt_in?: profile.durable?,
         durable_tag: durable_tag(profile),
         preflight: preflight,
         storage_behavior_ref: storage_behavior_ref(profile),
         authority_semantics_ref: @authority_semantics_ref,
         restart_claim: Map.fetch!(profile.metadata, :restart_claim),
         debug_event: debug_event(profile),
         debug_result: debug_result,
         gn_ten_receipt: gn_ten_receipt(profile)
       }}
    end
  end

  defp capabilities_for(%PersistencePolicy.Profile{durable?: false}), do: {:ok, []}

  defp capabilities_for(%PersistencePolicy.Profile{} = profile) do
    with {:ok, capability} <-
           PersistencePolicy.StoreCapability.new(
             store_ref: profile.default_tier,
             tier: profile.default_tier,
             data_classes: [:all],
             adapter: :phase10_mock_capability,
             partitions: profile.store_set.partitions
           ) do
      {:ok, [capability]}
    end
  end

  defp mock_preflight(%PersistencePolicy.StoreCapability{} = _capability), do: :ok

  defp emit_debug(%PersistencePolicy.Profile{debug_tap: DebugTap.Noop} = profile) do
    with {:ok, tap} <- PersistencePolicy.emit_debug(DebugTap.Noop, %{}, debug_event(profile)) do
      {:ok, %{tap: tap, mutated?: false}}
    end
  end

  defp emit_debug(%PersistencePolicy.Profile{} = profile) do
    tap = DebugTap.MemoryRing.new(limit: 4)

    with {:ok, next_tap} <-
           PersistencePolicy.emit_debug(DebugTap.MemoryRing, tap, debug_event(profile)) do
      {:ok, %{tap: next_tap, mutated?: true}}
    end
  end

  defp debug_event(profile) do
    %{
      safe_ref: "trace://persistence/#{profile.id}",
      hash_ref: "hash://persistence/#{profile.id}",
      metadata: %{
        capture_level: profile.capture_level,
        store_set_id: profile.store_set.id,
        storage_behavior_ref: storage_behavior_ref(profile),
        authority_semantics_ref: @authority_semantics_ref
      }
    }
  end

  defp scanner_input(profile_receipts, fixture_mappings) do
    %{
      owner_repo: "stack_lab",
      package_path: "examples/persistence_mode_roundtrip",
      persistence_facts: Enum.map(profile_receipts, &scanner_fact/1),
      fixture_mappings: fixture_mappings
    }
  end

  defp scanner_fact(%ProfileReceipt{} = receipt) do
    %{
      profile_id: receipt.profile_id,
      selected_tier: receipt.selected_tier,
      store_set_id: receipt.store_set_id,
      capture_level: receipt.capture_level,
      proof_command: receipt.proof_command,
      memory_default?: receipt.profile_id == :mickey_mouse,
      provider_dependency_by_default?: false,
      postgres_required_by_default?: false,
      temporal_required_by_default?: false,
      object_store_required_by_default?: false,
      network_required_by_default?: false,
      optional_external_required_by_default?: false,
      debug_sidecar_required_by_default?: false,
      debug_capture_redacted?: true,
      durable_opt_in?: receipt.durable_opt_in?,
      durable_tag: receipt.durable_tag,
      storage_behavior_ref: receipt.storage_behavior_ref,
      authority_semantics_ref: receipt.authority_semantics_ref,
      restart_claim: receipt.restart_claim,
      knob_docs: [knob_doc()],
      product_direct_lower_store_imports: [],
      debug_events: [receipt.debug_event],
      gn_ten_receipt: receipt.gn_ten_receipt
    }
  end

  defp knob_doc do
    %{
      name: "persistence_profile",
      type: "atom",
      default: ":mickey_mouse",
      validation: "GroundPlane built-in profile",
      examples: [":mickey_mouse", ":memory_debug", ":integration_postgres", ":full_debug_tracked"],
      test_refs: ["examples/persistence_mode_roundtrip", "support/persistence_matrix_scanner"]
    }
  end

  defp gn_ten_receipt(profile) do
    %{
      selected_persistence_profile: profile.id,
      selected_tier: profile.default_tier,
      store_set_id: profile.store_set.id,
      capture_level: profile.capture_level,
      proof_command: @proof_command,
      storage_behavior_ref: storage_behavior_ref(profile),
      authority_semantics_ref: @authority_semantics_ref,
      restart_claim: Map.fetch!(profile.metadata, :restart_claim)
    }
  end

  defp fixture_mappings do
    Enum.map(@fixture_refs, fn fixture_ref ->
      %{
        fixture_ref: fixture_ref,
        source_paths: @source_paths,
        test_paths: @test_paths,
        scanner_rules: Map.fetch!(@fixture_scanner_rules, fixture_ref),
        docs_paths: @docs_paths,
        receipt_paths: @receipt_paths
      }
    end)
  end

  defp storage_behavior_ref(profile) do
    "storage-behavior://#{profile.default_tier}/#{profile.store_set.id}"
  end

  defp storage_behavior_switch?(profile_receipts) do
    memory_refs =
      profile_receipts
      |> Enum.filter(&(&1.selected_tier == :memory_ephemeral))
      |> Enum.map(& &1.storage_behavior_ref)

    durable_refs =
      profile_receipts
      |> Enum.reject(&(&1.selected_tier == :memory_ephemeral))
      |> Enum.map(& &1.storage_behavior_ref)

    Enum.any?(memory_refs, fn memory_ref ->
      Enum.any?(durable_refs, &(&1 != memory_ref))
    end)
  end

  defp authority_semantics_stable?(profile_receipts) do
    profile_receipts
    |> Enum.map(& &1.authority_semantics_ref)
    |> MapSet.new()
    |> MapSet.size()
    |> Kernel.==(1)
  end

  defp durable_tag(%PersistencePolicy.Profile{durable?: true}), do: @durable_tag
  defp durable_tag(%PersistencePolicy.Profile{}), do: nil

  defp normalize_preflight(:ok), do: :ok
  defp normalize_preflight({:error, reason}), do: {:error, reason}

  defp status(profile_receipts, matrix_scan) do
    if matrix_scan.status == :pass and Enum.all?(profile_receipts, &(&1.preflight == :ok)) do
      :pass
    else
      :open_defect
    end
  end
end
