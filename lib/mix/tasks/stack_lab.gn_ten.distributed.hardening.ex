defmodule Mix.Tasks.StackLab.GnTen.Distributed.Hardening do
  @moduledoc "Writes the gn-ten distributed hardening receipt."

  use Mix.Task

  alias StackLab.GnTenDistributedHardening

  @shortdoc "Write the gn-ten distributed hardening receipt"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          receipt: :string,
          json: :boolean,
          source_ref: :string
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    run_opts =
      []
      |> maybe_put(opts, :source_ref)

    {:ok, receipt} = GnTenDistributedHardening.run(run_opts)
    receipt_path = Keyword.get(opts, :receipt, GnTenDistributedHardening.default_receipt_path())
    path = GnTenDistributedHardening.write_receipt!(receipt, receipt_path)
    print_success(receipt, path, Keyword.get(opts, :json, false))
  end

  defp maybe_put(run_opts, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> Keyword.put(run_opts, key, value)
      :error -> run_opts
    end
  end

  defp print_success(receipt, path, true) do
    receipt
    |> Map.put("receipt_path", path)
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp print_success(receipt, path, false) do
    Mix.shell().info("stack_lab.gn_ten.distributed.hardening passed")
    Mix.shell().info("receipt=#{path}")
    Mix.shell().info("receipt_ref=#{receipt["receipt_ref"]}")
  end
end
