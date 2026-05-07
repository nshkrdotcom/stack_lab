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
    :status,
    :provider_dependency?,
    :postgres_dependency?,
    :temporal_dependency?,
    :external_substrate_dependency?,
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

  @fixture_refs ["PERSIST-001", "PERSIST-008", "PERSIST-015", "PERSIST-016", "PERSIST-020"]
  @profiles [:mickey_mouse, :memory_debug, :integration_postgres, :full_debug_tracked]
  @proof_command "mix test"
  @durable_tag "persistence-durable-opt-in"

  @spec run() :: {:ok, Receipt.t()} | {:error, term()}
  def run do
    with {:ok, profile_receipts} <- build_profile_receipts(),
         {:ok, matrix_scan} <- PersistenceMatrixScanner.scan(scanner_input(profile_receipts)) do
      {:ok,
       %Receipt{
         receipt_ref: "persistence-mode-roundtrip://phase-3/deterministic",
         fixture_refs: @fixture_refs,
         status: status(profile_receipts, matrix_scan),
         provider_dependency?: false,
         postgres_dependency?: false,
         temporal_dependency?: false,
         external_substrate_dependency?: false,
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
             adapter: :phase3_mock_capability,
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
        store_set_id: profile.store_set.id
      }
    }
  end

  defp scanner_input(profile_receipts) do
    %{
      owner_repo: "stack_lab",
      package_path: "examples/persistence_mode_roundtrip",
      persistence_facts: Enum.map(profile_receipts, &scanner_fact/1)
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
      postgres_required_by_default?: false,
      temporal_required_by_default?: false,
      optional_external_required_by_default?: false,
      debug_capture_redacted?: true,
      durable_opt_in?: receipt.durable_opt_in?,
      durable_tag: receipt.durable_tag,
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
      examples: [":mickey_mouse", ":memory_debug", ":integration_postgres"],
      test_refs: ["examples/persistence_mode_roundtrip", "support/persistence_matrix_scanner"]
    }
  end

  defp gn_ten_receipt(profile) do
    %{
      selected_persistence_profile: profile.id,
      selected_tier: profile.default_tier,
      store_set_id: profile.store_set.id,
      capture_level: profile.capture_level,
      proof_command: @proof_command
    }
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
