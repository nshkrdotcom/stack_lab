defmodule Mix.Tasks.StackLab.Fugu.LiveProviderSmoke do
  @moduledoc """
  Guarded live-provider smoke wrapper for fugu closeout.

  The command refuses to run unless live behavior is explicitly requested and
  the caller asserts that secrets were loaded through the documented wrapper.
  Provider arguments are passed after `--`.
  """

  use Mix.Task

  alias StackLab.FuguLiveProviderGuard

  @shortdoc "Run guarded opt-in live provider smoke for fugu"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {guard_args, provider_args} = split_forwarded_args(args)

    {opts, _argv, invalid} =
      OptionParser.parse(guard_args,
        strict: [
          allow_live: :boolean,
          secrets_loaded: :boolean,
          dry_run: :boolean,
          json: :boolean
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    guard_opts = [
      allow_live?: Keyword.get(opts, :allow_live, false),
      secrets_loaded?: Keyword.get(opts, :secrets_loaded, false),
      execution_mode: execution_mode(opts),
      command: forwarded_command(provider_args)
    ]

    case FuguLiveProviderGuard.validate(guard_opts) do
      {:ok, receipt} ->
        maybe_run_provider_smoke(opts, provider_args)
        print_success(receipt, Keyword.get(opts, :json, false))

      {:error, reason} ->
        print_failure(reason, Keyword.get(opts, :json, false))
    end
  end

  defp split_forwarded_args(args) do
    {guard_args, rest} = Enum.split_while(args, &(&1 != "--"))

    case rest do
      ["--" | provider_args] -> {guard_args, provider_args}
      [] -> {guard_args, []}
    end
  end

  defp execution_mode(opts) do
    if Keyword.get(opts, :dry_run, false), do: "dry_run_guard_passed", else: "delegated_live_run"
  end

  defp forwarded_command([]), do: "mix stack_lab.provider_smoke_check"

  defp forwarded_command(provider_args) do
    Enum.join(["mix", "stack_lab.provider_smoke_check" | provider_args], " ")
  end

  defp maybe_run_provider_smoke(opts, provider_args) do
    if Keyword.get(opts, :dry_run, false) do
      :ok
    else
      Mix.Task.reenable("stack_lab.provider_smoke_check")
      Mix.Task.run("stack_lab.provider_smoke_check", provider_args)
    end
  end

  defp print_success(receipt, true), do: Mix.shell().info(Jason.encode!(receipt, pretty: true))

  defp print_success(receipt, false) do
    Mix.shell().info("stack_lab.fugu.live_provider_smoke guard passed")
    Mix.shell().info("execution_mode=#{receipt["execution_mode"]}")
    Mix.shell().info("forwarded_command=#{receipt["forwarded_command"]}")
  end

  defp print_failure(reason, true) do
    %{status: "fail", error: reason}
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()

    exit({:shutdown, 1})
  end

  defp print_failure(reason, false) do
    Mix.shell().error("stack_lab.fugu.live_provider_smoke rejected")
    Mix.shell().error("  #{inspect(reason)}")
    exit({:shutdown, 1})
  end
end
