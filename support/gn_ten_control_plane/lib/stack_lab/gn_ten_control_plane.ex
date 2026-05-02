defmodule StackLab.GnTenControlPlane do
  @moduledoc """
  Bounded receipt records for StackLab release gates.
  """

  alias StackLab.SpecCell

  @enforce_keys [
    :receipt_id,
    :requirement_id,
    :owner_repo,
    :state,
    :proof_command,
    :receipt_path,
    :spec_cell
  ]
  defstruct @enforce_keys

  @states ["passed", "failed", "skipped", "missing", "not_applicable"]

  @type state :: String.t()

  @type t :: %__MODULE__{
          receipt_id: String.t(),
          requirement_id: String.t(),
          owner_repo: String.t(),
          state: state(),
          proof_command: String.t(),
          receipt_path: String.t(),
          spec_cell: SpecCell.t()
        }

  @spec states() :: [state()]
  def states, do: @states

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, [atom()]}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    case missing_keys(attrs) do
      [] ->
        receipt = struct!(__MODULE__, attrs)

        case validate(receipt) do
          [] -> {:ok, receipt}
          errors -> {:error, errors}
        end

      errors ->
        {:error, errors}
    end
  end

  @spec validate(t()) :: [atom()]
  def validate(%__MODULE__{} = receipt) do
    []
    |> require_binary(:receipt_id, receipt.receipt_id)
    |> require_binary(:requirement_id, receipt.requirement_id)
    |> require_binary(:owner_repo, receipt.owner_repo)
    |> require_state(receipt.state)
    |> require_binary(:proof_command, receipt.proof_command)
    |> require_binary(:receipt_path, receipt.receipt_path)
    |> require_spec_cell(receipt.spec_cell)
    |> Enum.reverse()
  end

  @spec release_blocking?(t()) :: boolean()
  def release_blocking?(%__MODULE__{state: state}) when state in ["failed", "missing"] do
    true
  end

  def release_blocking?(%__MODULE__{}), do: false

  defp missing_keys(attrs) do
    @enforce_keys
    |> Enum.reject(&Map.has_key?(attrs, &1))
    |> Enum.reverse()
  end

  defp require_binary(errors, _field, value) when is_binary(value) and value != "" do
    errors
  end

  defp require_binary(errors, field, _value), do: [field | errors]

  defp require_state(errors, state) when state in @states, do: errors
  defp require_state(errors, _state), do: [:state | errors]

  defp require_spec_cell(errors, %SpecCell{} = cell) do
    case SpecCell.validate(cell) do
      [] -> errors
      _errors -> [:spec_cell | errors]
    end
  end

  defp require_spec_cell(errors, _cell), do: [:spec_cell | errors]
end
