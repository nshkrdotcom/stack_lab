defmodule Mix.Tasks.StackLab.Synapse.Acceptance do
  @moduledoc "Runs StackLab external acceptance against the Synapse product proof app."

  use Mix.Task

  alias StackLab.SynapseAcceptance

  @shortdoc "Run external acceptance against Synapse"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          example_root: :string,
          receipt: :string,
          json: :boolean
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    run_opts =
      []
      |> maybe_put(opts, :example_root)

    case SynapseAcceptance.run(run_opts) do
      {:ok, receipt} ->
        receipt_path = Keyword.get(opts, :receipt, SynapseAcceptance.default_receipt_path())
        path = SynapseAcceptance.write_receipt!(receipt, receipt_path)
        print_success(receipt, path, Keyword.get(opts, :json, false))

      {:error, reason} ->
        print_failure(reason, Keyword.get(opts, :json, false))
    end
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
    proofs = receipt["proofs"]

    Mix.shell().info("stack_lab.synapse.acceptance passed")
    Mix.shell().info("receipt=#{path}")
    Mix.shell().info("product_repo=#{receipt["product_repo"]}")
    Mix.shell().info("run_ref=#{proofs["run_start"]["run_ref"]}")
    Mix.shell().info("no_bypass=#{receipt["no_bypass"]["status"]}")
  end

  defp print_failure(reason, true) do
    %{status: "fail", error: reason}
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()

    exit({:shutdown, 1})
  end

  defp print_failure(reason, false) do
    Mix.shell().error("stack_lab.synapse.acceptance failed")
    Mix.shell().error("  #{inspect(reason)}")
    exit({:shutdown, 1})
  end
end
