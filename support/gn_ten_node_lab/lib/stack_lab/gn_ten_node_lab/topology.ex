defmodule StackLab.GnTenNodeLab.Topology do
  @moduledoc """
  Topology spec parser and validator for local gn-ten node-lab runs.
  """

  @enforce_keys [:topology_ref, :cookie_mode, :name_domain, :dist_port_range, :profiles]
  defstruct [:topology_ref, :cookie_mode, :name_domain, :dist_port_range, :profiles, proof: %{}]

  @type profile :: %{
          required(:profile) => atom(),
          required(:instances) => pos_integer(),
          optional(:node_ids) => [String.t()],
          optional(:required_apps) => [atom()],
          optional(:owner_groups) => [tuple()],
          optional(:env) => map(),
          optional(:vm_args) => [String.t()]
        }

  @type t :: %__MODULE__{
          topology_ref: String.t(),
          cookie_mode: :ephemeral,
          name_domain: :shortnames,
          dist_port_range: Range.t(),
          profiles: [profile()],
          proof: map()
        }

  @max_default_nodes 32
  @max_stress_nodes 49

  @spec load_file(Path.t()) :: {:ok, t()} | {:error, [map()]}
  def load_file(path) when is_binary(path) do
    with {:ok, spec} <- read_spec_file(path) do
      validate(spec)
    end
  end

  @spec validate(map()) :: {:ok, t()} | {:error, [map()]}
  def validate(spec) when is_map(spec) do
    topology = normalize(spec)
    failures = validation_failures(topology)

    if failures == [], do: {:ok, topology}, else: {:error, failures}
  end

  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{profiles: profiles}) do
    profiles
    |> Enum.map(&Map.get(&1, :instances, 0))
    |> Enum.sum()
  end

  @spec default_node_cap() :: pos_integer()
  def default_node_cap, do: @max_default_nodes

  @spec stress_node_cap() :: pos_integer()
  def stress_node_cap, do: @max_stress_nodes

  @spec instance_specs(t()) :: [map()]
  def instance_specs(%__MODULE__{profiles: profiles}) do
    Enum.flat_map(profiles, fn profile ->
      node_ids = profile_node_ids(profile)

      0..(profile.instances - 1)//1
      |> Enum.map(fn index ->
        %{
          node_id: Enum.at(node_ids, index),
          profile: profile.profile,
          instance_index: index,
          required_apps: profile.required_apps,
          owner_groups: profile.owner_groups,
          env: profile.env,
          vm_args: profile.vm_args
        }
      end)
    end)
  end

  defp normalize(spec) do
    %__MODULE__{
      topology_ref: field(spec, :topology_ref),
      cookie_mode: atom_field(spec, :cookie_mode),
      name_domain: atom_field(spec, :name_domain),
      dist_port_range: range_field(spec, :dist_port_range),
      profiles: Enum.map(List.wrap(field(spec, :profiles)), &normalize_profile/1),
      proof: field(spec, :proof) || %{}
    }
  end

  defp normalize_profile(profile) when is_map(profile) do
    %{
      profile: atom_field(profile, :profile),
      instances: field(profile, :instances),
      node_ids: Enum.map(List.wrap(field(profile, :node_ids)), &to_string/1),
      required_apps: Enum.map(List.wrap(field(profile, :required_apps)), &normalize_atom/1),
      owner_groups: List.wrap(field(profile, :owner_groups)),
      env: field(profile, :env) || %{},
      vm_args: Enum.map(List.wrap(field(profile, :vm_args)), &to_string/1)
    }
  end

  defp validation_failures(%__MODULE__{} = topology) do
    []
    |> require_binary(topology.topology_ref, "missing_topology_ref")
    |> require_value(topology.cookie_mode == :ephemeral, "unsupported_cookie_mode")
    |> require_value(topology.name_domain == :shortnames, "unsupported_name_domain")
    |> require_value(valid_range?(topology.dist_port_range), "invalid_dist_port_range")
    |> require_value(topology.profiles != [], "missing_profiles")
    |> require_value(node_count(topology) <= node_cap(topology), "node_count_above_cap")
    |> Kernel.++(profile_failures(topology.profiles))
    |> Kernel.++(instance_failures(topology))
  end

  defp profile_failures(profiles) do
    profiles
    |> Enum.flat_map(fn profile ->
      []
      |> require_value(is_atom(profile.profile), "invalid_profile_name")
      |> require_value(valid_instances?(profile.instances), "invalid_profile_instances")
      |> require_value(valid_node_ids?(profile), "invalid_profile_node_ids")
      |> require_value(
        owner_groups_safe?(profile.owner_groups),
        "stack_lab_owner_group_forbidden"
      )
    end)
  end

  defp instance_failures(%__MODULE__{} = topology) do
    node_ids = Enum.map(instance_specs(topology), & &1.node_id)

    if length(node_ids) == length(Enum.uniq(node_ids)) do
      []
    else
      [failure("duplicate_profile_instance_id")]
    end
  end

  defp node_cap(%__MODULE__{topology_ref: topology_ref}) do
    if String.contains?(to_string(topology_ref), "scale-49"),
      do: @max_stress_nodes,
      else: @max_default_nodes
  end

  defp owner_groups_safe?(owner_groups) do
    Enum.all?(owner_groups, fn
      {StackLab, _name} ->
        false

      {module, _name} when is_atom(module) ->
        not String.starts_with?(Atom.to_string(module), "Elixir.StackLab.")

      _other ->
        false
    end)
  end

  defp valid_instances?(instances), do: is_integer(instances) and instances > 0

  defp valid_node_ids?(%{node_ids: []}), do: true

  defp valid_node_ids?(%{node_ids: node_ids, instances: instances}) do
    length(node_ids) == instances and Enum.all?(node_ids, &valid_node_id?/1)
  end

  defp valid_node_id?(node_id) when is_binary(node_id) do
    Regex.match?(~r/^[a-z][a-z0-9_]*[a-z0-9]$/, node_id)
  end

  defp valid_node_id?(_node_id), do: false

  defp valid_range?(first..last//1), do: first >= 1 and last <= 65_535 and first < last
  defp valid_range?(_range), do: false

  defp require_binary(failures, value, _code) when is_binary(value) and value != "", do: failures
  defp require_binary(failures, _value, code), do: [failure(code) | failures]

  defp require_value(failures, true, _code), do: failures
  defp require_value(failures, false, code), do: [failure(code) | failures]

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp atom_field(map, key), do: map |> field(key) |> normalize_atom()

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_atom(value)
  defp normalize_atom(value), do: value

  defp range_field(map, key) do
    case field(map, key) do
      first..last//1 = range when is_integer(first) and is_integer(last) -> range
      %{"min" => first, "max" => last} -> first..last
      %{min: first, max: last} -> first..last
      other -> other
    end
  end

  defp profile_node_ids(%{node_ids: [_ | _] = node_ids}), do: node_ids

  defp profile_node_ids(%{profile: profile, instances: instances}) do
    0..(instances - 1)//1
    |> Enum.map(&"#{profile}_#{&1}")
  end

  defp read_spec_file(path) do
    case Path.extname(path) do
      ".exs" ->
        {spec, _binding} = Code.eval_file(path)
        {:ok, spec}

      ".json" ->
        path
        |> File.read()
        |> case do
          {:ok, body} -> Jason.decode(body)
          {:error, reason} -> {:error, [failure("topology_file_read_failed", reason)]}
        end

      _other ->
        {:error, [failure("unsupported_topology_file")]}
    end
  rescue
    error ->
      {:error, [failure("topology_file_eval_failed", Exception.message(error))]}
  end

  defp failure(code), do: %{code: code}
  defp failure(code, reason), do: %{code: code, reason: inspect(reason)}
end
