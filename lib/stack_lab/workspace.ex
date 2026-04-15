unless Code.ensure_loaded?(StackLab.Build.WorkspaceContract) do
  Code.require_file("../../build_support/workspace_contract.exs", __DIR__)
end

defmodule StackLab.Workspace do
  @moduledoc """
  Root helpers for the StackLab workspace.
  """

  alias StackLab.Build.WorkspaceContract

  @spec active_project_globs() :: [String.t()]
  def active_project_globs, do: WorkspaceContract.active_project_globs()

  @spec package_paths() :: [String.t()]
  def package_paths, do: WorkspaceContract.package_paths()
end
