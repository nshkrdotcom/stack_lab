defmodule StackLab.SpecCell do
  @moduledoc """
  Executable requirement cell used by StackLab release gates.
  """

  @enforce_keys [
    :requirement_id,
    :owner_repo,
    :source_docs,
    :target_code_paths,
    :proof_command,
    :acceptance_fixture,
    :scanner_refs,
    :closeout_state,
    :release_claim
  ]
  defstruct @enforce_keys

  @type closeout_state :: :planned | :red | :green | :open_defect

  @type t :: %__MODULE__{
          requirement_id: String.t(),
          owner_repo: String.t(),
          source_docs: [String.t()],
          target_code_paths: [String.t()],
          proof_command: String.t(),
          acceptance_fixture: String.t(),
          scanner_refs: [String.t()],
          closeout_state: closeout_state(),
          release_claim: String.t()
        }

  @allowed_closeout_states [:planned, :red, :green, :open_defect]
  @allowed_fixture_prefixes [
    "UAA-",
    "MEM-",
    "PROMPT-",
    "GUARD-",
    "EVAL-",
    "COST-",
    "CONN-",
    "OPCON-",
    "SKILL-",
    "HIVE-",
    "AOC-",
    "PERSIST-AOC-"
  ]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, [atom()]}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    case missing_keys(attrs) do
      [] ->
        cell = struct!(__MODULE__, attrs)

        case validate(cell) do
          [] -> {:ok, cell}
          errors -> {:error, errors}
        end

      errors ->
        {:error, errors}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, cell} -> cell
      {:error, errors} -> raise ArgumentError, "invalid SpecCell: #{inspect(errors)}"
    end
  end

  @spec validate(t()) :: [atom()]
  def validate(%__MODULE__{} = cell) do
    []
    |> require_binary(:requirement_id, cell.requirement_id)
    |> require_binary(:owner_repo, cell.owner_repo)
    |> require_non_empty_list(:source_docs, cell.source_docs)
    |> require_non_empty_list(:target_code_paths, cell.target_code_paths)
    |> require_binary(:proof_command, cell.proof_command)
    |> require_binary(:acceptance_fixture, cell.acceptance_fixture)
    |> require_fixture_prefix(cell.acceptance_fixture)
    |> require_list(:scanner_refs, cell.scanner_refs)
    |> require_closeout_state(cell.closeout_state)
    |> require_binary(:release_claim, cell.release_claim)
    |> Enum.reverse()
  end

  @spec complete?(t()) :: boolean()
  def complete?(%__MODULE__{closeout_state: :green}), do: true
  def complete?(%__MODULE__{}), do: false

  defp missing_keys(attrs) do
    @enforce_keys
    |> Enum.reject(&Map.has_key?(attrs, &1))
    |> Enum.reverse()
  end

  defp require_binary(errors, _field, value) when is_binary(value) and value != "" do
    errors
  end

  defp require_binary(errors, field, _value), do: [field | errors]

  defp require_fixture_prefix(errors, fixture) when is_binary(fixture) do
    if Enum.any?(@allowed_fixture_prefixes, &String.starts_with?(fixture, &1)) do
      errors
    else
      [:acceptance_fixture | errors]
    end
  end

  defp require_fixture_prefix(errors, _fixture), do: [:acceptance_fixture | errors]

  defp require_non_empty_list(errors, field, [_ | _] = values) do
    require_list(errors, field, values)
  end

  defp require_non_empty_list(errors, field, _values), do: [field | errors]

  defp require_list(errors, _field, values) when is_list(values), do: errors
  defp require_list(errors, field, _values), do: [field | errors]

  defp require_closeout_state(errors, state) when state in @allowed_closeout_states do
    errors
  end

  defp require_closeout_state(errors, _state), do: [:closeout_state | errors]
end
