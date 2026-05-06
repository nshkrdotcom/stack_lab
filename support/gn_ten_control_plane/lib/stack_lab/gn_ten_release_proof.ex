defmodule StackLab.GnTenReleaseProof do
  @moduledoc """
  Release proof mapper for adaptive AOC and persistence fixture evidence.
  """

  alias StackLab.GnTenControlPlane

  @enforce_keys [
    :release_id,
    :release_name,
    :required_fixture_ids,
    :claims,
    :receipts,
    :open_defects
  ]
  defstruct @enforce_keys ++
              [
                :covered_fixture_ids,
                :missing_fixture_ids,
                :status,
                :complete?
              ]

  @claim_evidence_fields [
    :fixture_ids,
    :spec_cell_refs,
    :scanner_refs,
    :docs_refs,
    :qc_refs,
    :receipt_refs
  ]

  @type claim :: %{
          required(:claim_id) => String.t(),
          required(:fixture_ids) => [String.t()],
          required(:spec_cell_refs) => [String.t()],
          required(:scanner_refs) => [String.t()],
          required(:docs_refs) => [String.t()],
          required(:qc_refs) => [String.t()],
          required(:receipt_refs) => [String.t()],
          required(:status) => String.t()
        }

  @type t :: %__MODULE__{
          release_id: String.t(),
          release_name: String.t(),
          required_fixture_ids: [String.t()],
          claims: [claim()],
          receipts: [GnTenControlPlane.t()],
          open_defects: [String.t()],
          covered_fixture_ids: [String.t()],
          missing_fixture_ids: [String.t()],
          status: String.t(),
          complete?: boolean()
        }

  @spec build(map() | keyword()) :: {:ok, t()} | {:error, [atom()]}
  def build(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    case missing_keys(attrs) do
      [] -> build_checked(attrs)
      errors -> {:error, errors}
    end
  end

  @spec complete?(t()) :: boolean()
  def complete?(%__MODULE__{complete?: complete?}), do: complete?

  defp build_checked(attrs) do
    required_fixture_ids = unique(Map.fetch!(attrs, :required_fixture_ids))
    claims = Map.fetch!(attrs, :claims)
    receipts = Map.fetch!(attrs, :receipts)
    open_defects = Map.fetch!(attrs, :open_defects)

    covered_fixture_ids = covered_fixture_ids(required_fixture_ids, claims, receipts)
    missing_fixture_ids = required_fixture_ids -- covered_fixture_ids

    errors =
      []
      |> require_binary(:release_id, Map.fetch!(attrs, :release_id))
      |> require_binary(:release_name, Map.fetch!(attrs, :release_name))
      |> require_non_empty_list(:required_fixture_ids, required_fixture_ids)
      |> require_non_empty_list(:claims, claims)
      |> require_list(:receipts, receipts)
      |> require_list(:open_defects, open_defects)
      |> validate_claims(claims)
      |> validate_receipts(receipts)
      |> validate_missing_fixture_ids(missing_fixture_ids)
      |> Enum.reverse()
      |> Enum.uniq()

    case errors do
      [] ->
        {:ok,
         %__MODULE__{
           release_id: Map.fetch!(attrs, :release_id),
           release_name: Map.fetch!(attrs, :release_name),
           required_fixture_ids: required_fixture_ids,
           claims: claims,
           receipts: receipts,
           open_defects: open_defects,
           covered_fixture_ids: covered_fixture_ids,
           missing_fixture_ids: missing_fixture_ids,
           status: status(open_defects),
           complete?: open_defects == []
         }}

      errors ->
        {:error, errors}
    end
  end

  defp covered_fixture_ids(required_fixture_ids, claims, receipts) do
    receipt_fixture_ids =
      receipts
      |> Enum.reject(&GnTenControlPlane.release_blocking?/1)
      |> Enum.map(& &1.requirement_id)
      |> unique()

    claim_fixture_ids =
      claims
      |> Enum.flat_map(&claim_fixture_ids/1)
      |> unique()

    Enum.filter(required_fixture_ids, fn fixture_id ->
      fixture_id in receipt_fixture_ids and fixture_id in claim_fixture_ids
    end)
  end

  defp claim_fixture_ids(%{fixture_ids: fixture_ids}) when is_list(fixture_ids), do: fixture_ids
  defp claim_fixture_ids(_claim), do: []

  defp missing_keys(attrs) do
    @enforce_keys
    |> Enum.reject(&Map.has_key?(attrs, &1))
    |> Enum.reverse()
  end

  defp validate_claims(errors, claims) when is_list(claims) do
    Enum.reduce(claims, errors, &validate_claim/2)
  end

  defp validate_claims(errors, _claims), do: [:claims | errors]

  defp validate_claim(claim, errors) when is_map(claim) do
    errors =
      errors
      |> require_binary(:claim_id, Map.get(claim, :claim_id))
      |> require_binary(:claim_status, Map.get(claim, :status))

    Enum.reduce(@claim_evidence_fields, errors, fn field, acc ->
      require_claim_evidence(acc, field, Map.get(claim, field))
    end)
  end

  defp validate_claim(_claim, errors), do: [:claim | errors]

  defp require_claim_evidence(errors, field, values) when is_list(values) and values != [] do
    errors
    |> require_list(field, values)
    |> require_binary_values(claim_error(field), values)
  end

  defp require_claim_evidence(errors, field, _values), do: [claim_error(field) | errors]

  defp validate_receipts(errors, receipts) when is_list(receipts) do
    if Enum.all?(receipts, &match?(%GnTenControlPlane{}, &1)) do
      errors
    else
      [:receipts | errors]
    end
  end

  defp validate_receipts(errors, _receipts), do: [:receipts | errors]

  defp validate_missing_fixture_ids(errors, []), do: errors

  defp validate_missing_fixture_ids(errors, _missing_fixture_ids),
    do: [:missing_fixture_ids | errors]

  defp require_binary(errors, _field, value) when is_binary(value) and value != "" do
    errors
  end

  defp require_binary(errors, field, _value), do: [field | errors]

  defp require_non_empty_list(errors, field, [_ | _] = values),
    do: require_list(errors, field, values)

  defp require_non_empty_list(errors, field, _values), do: [field | errors]

  defp require_list(errors, _field, values) when is_list(values), do: errors
  defp require_list(errors, field, _values), do: [field | errors]

  defp require_binary_values(errors, _field, values) do
    if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
      errors
    else
      [:claim_evidence_value | errors]
    end
  end

  defp claim_error(:fixture_ids), do: :claim_fixture_ids
  defp claim_error(:spec_cell_refs), do: :claim_spec_cell_refs
  defp claim_error(:scanner_refs), do: :claim_scanner_refs
  defp claim_error(:docs_refs), do: :claim_docs_refs
  defp claim_error(:qc_refs), do: :claim_qc_refs
  defp claim_error(:receipt_refs), do: :claim_receipt_refs

  defp status([]), do: "passed"
  defp status([_ | _]), do: "open_defect"

  defp unique(values), do: Enum.uniq(values)
end
