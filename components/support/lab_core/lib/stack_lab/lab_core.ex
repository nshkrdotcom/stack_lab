defmodule StackLab.LabCore do
  @moduledoc """
  Shared helpers for StackLab support packages and examples.
  """

  @repo_root Path.expand("../../../..", __DIR__)

  @spec repo_root() :: String.t()
  def repo_root, do: @repo_root

  @spec compose_file(:single | :multi) :: String.t()
  def compose_file(:single), do: Path.join(@repo_root, "tools/compose/single-node.yml")
  def compose_file(:multi), do: Path.join(@repo_root, "tools/compose/multi-node.yml")

  @spec toxiproxy_config() :: String.t()
  def toxiproxy_config, do: Path.join(@repo_root, "tools/toxiproxy/toxiproxy.json")

  @spec otel_config() :: String.t()
  def otel_config, do: Path.join(@repo_root, "tools/otel/config.yaml")

  @spec runbook(:up_single | :up_multi | :faults) :: String.t()
  def runbook(:up_single), do: Path.join(@repo_root, "docs/runbooks/up_single.md")
  def runbook(:up_multi), do: Path.join(@repo_root, "docs/runbooks/up_multi.md")
  def runbook(:faults), do: Path.join(@repo_root, "docs/runbooks/faults.md")

  @spec example_name(atom()) :: String.t()
  def example_name(name) when is_atom(name), do: Atom.to_string(name)

  @spec required_paths() :: [String.t()]
  def required_paths do
    [
      compose_file(:single),
      compose_file(:multi),
      toxiproxy_config(),
      otel_config(),
      runbook(:up_single),
      runbook(:up_multi),
      runbook(:faults)
    ]
  end
end
