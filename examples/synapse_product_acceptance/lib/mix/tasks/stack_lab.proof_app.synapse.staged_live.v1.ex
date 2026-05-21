defmodule Mix.Tasks.StackLab.ProofApp.Synapse.StagedLive.V1 do
  @moduledoc "Runs the Synapse staged-live governed-effect proof app."

  use Mix.Task

  alias StackLab.Examples.SynapseStagedLive

  @shortdoc "Run the Synapse staged-live governed-effect proof"

  @impl Mix.Task
  def run(args) do
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

    case SynapseStagedLive.run() do
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
    proofs = receipt["proofs"]

    Mix.shell().info("stack_lab.proof_app.synapse.staged_live.v1 passed")
    Mix.shell().info("product_repo=#{receipt["product_repo"]}")
    Mix.shell().info("effect_ref=#{proofs["run_start"]["effect_ref"]}")
    Mix.shell().info("receipt_ref=#{proofs["run_start"]["receipt_ref"]}")
    Mix.shell().info("no_bypass=#{receipt["no_bypass"]["status"]}")
  end

  defp print_failure(reason, true) do
    %{status: "fail", error: inspect(reason)}
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()

    exit({:shutdown, 1})
  end

  defp print_failure(reason, false) do
    Mix.shell().error("stack_lab.proof_app.synapse.staged_live.v1 failed")
    Mix.shell().error("  #{inspect(reason)}")
    exit({:shutdown, 1})
  end
end
