defmodule Mix.Tasks.StackLab.Extravaganza.LiveE2e do
  @moduledoc """
  Root workspace entry point for the Extravaganza dynamic live E2E proof.

  The implementation lives in `support/citadel_spine_harness`; this task keeps
  the documented root command working by delegating to that package.
  """

  use Mix.Task

  @shortdoc "Run Extravaganza's dynamic live provider E2E proof"

  @stdin_flag "--linear-api-key-stdin"
  @file_flag "--linear-api-key-file"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case delegate(args) do
      :ok ->
        :ok

      {:error, reason} ->
        Mix.raise("Extravaganza dynamic live provider E2E failed: #{inspect(reason)}")
    end
  end

  @doc false
  def delegate_project_dir do
    Path.expand("../../../support/citadel_spine_harness", __DIR__)
  end

  defp delegate(args) do
    with {:ok, child_args, cleanup_paths} <- prepare_child_args(args) do
      try do
        case run_child_mix(child_args) do
          0 -> :ok
          status -> {:error, {:support_harness_exit_status, status}}
        end
      after
        Enum.each(cleanup_paths, &File.rm/1)
      end
    end
  end

  defp prepare_child_args(args) do
    cond do
      @stdin_flag in args and @file_flag in args ->
        {:error, {:duplicate_credential_source, [@stdin_flag, @file_flag]}}

      @stdin_flag in args ->
        with {:ok, secret} <- read_stdin_secret(),
             {:ok, path} <- write_stdin_secret(secret) do
          {:ok, replace_stdin_flag(args, path), [path]}
        end

      true ->
        {:ok, args, []}
    end
  end

  defp read_stdin_secret do
    case IO.read(:stdio, :all) do
      data when is_binary(data) -> {:ok, data}
      :eof -> {:ok, ""}
      {:error, reason} -> {:error, {:stdin_read_failed, reason}}
    end
  end

  defp write_stdin_secret(secret) do
    path =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_live_e2e_linear_#{System.unique_integer([:positive])}.secret"
      )

    with :ok <- File.write(path, secret, [:write, :exclusive]),
         :ok <- File.chmod(path, 0o600) do
      {:ok, path}
    else
      {:error, reason} -> {:error, {:linear_secret_file_failed, reason}}
    end
  end

  defp replace_stdin_flag([@stdin_flag | rest], path), do: [@file_flag, path | rest]
  defp replace_stdin_flag([head | rest], path), do: [head | replace_stdin_flag(rest, path)]
  defp replace_stdin_flag([], _path), do: []

  defp run_child_mix(args) do
    {_stream, status} =
      System.cmd(
        mix_executable(),
        ["stack_lab.extravaganza.live_e2e" | args],
        cd: delegate_project_dir(),
        stderr_to_stdout: true,
        into: IO.stream(:stdio, :line)
      )

    status
  end

  defp mix_executable do
    System.find_executable("mix") || "mix"
  end
end
