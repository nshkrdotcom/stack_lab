defmodule Mix.Tasks.StackLab.ProofApp.Synapse.Acceptance do
  @moduledoc "Runs the Synapse product acceptance proof app."

  use Mix.Task

  alias StackLab.Examples.SynapseProductAcceptance

  @shortdoc "Run the Synapse product acceptance proof"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          json: :boolean,
          receipt: :string
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    case SynapseProductAcceptance.run() do
      {:ok, receipt} ->
        maybe_write_receipt!(receipt, Keyword.get(opts, :receipt))
        print_success(receipt, Keyword.get(opts, :json, false))

      {:error, reason} ->
        print_failure(reason, Keyword.get(opts, :json, false))
    end
  end

  defp maybe_write_receipt!(_receipt, nil), do: :ok

  defp maybe_write_receipt!(receipt, path) when is_binary(path) do
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(receipt, pretty: true))
  end

  defp print_success(receipt, true) do
    receipt
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp print_success(receipt, false) do
    Mix.shell().info("stack_lab.proof_app.synapse.acceptance passed")
    Mix.shell().info("product_repo=#{receipt["product_repo"]}")
    Mix.shell().info("run_ref=#{receipt["proofs"]["run_start"]["run_ref"]}")
    Mix.shell().info("no_bypass=#{receipt["no_bypass"]["status"]}")
  end

  defp print_failure(reason, true) do
    %{status: "fail", error: inspect(reason)}
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()

    exit({:shutdown, 1})
  end

  defp print_failure(reason, false) do
    Mix.shell().error("stack_lab.proof_app.synapse.acceptance failed")
    Mix.shell().error("  #{inspect(reason)}")
    exit({:shutdown, 1})
  end
end
