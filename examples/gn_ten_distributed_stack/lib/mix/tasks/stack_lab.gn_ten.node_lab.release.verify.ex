defmodule Mix.Tasks.StackLab.GnTen.NodeLab.Release.Verify do
  @moduledoc "Runs the gn-ten release-path parity prototype verifier."
  @shortdoc "Runs the gn-ten release-path parity prototype verifier"

  use Mix.Task

  alias StackLab.Examples.GnTenDistributedStack

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          manifest: :string,
          expected_version: :string,
          json: :boolean
        ]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    proof_opts =
      opts
      |> Keyword.take([:manifest, :expected_version])
      |> Enum.map(fn
        {:manifest, path} -> {:manifest_path, path}
        {:expected_version, version} -> {:expected_version, version}
      end)

    {:ok, receipt} = GnTenDistributedStack.run_release_peer(proof_opts)
    print(receipt, Keyword.get(opts, :json, false))
  end

  defp print(receipt, true) do
    Mix.shell().info(GnTenDistributedStack.to_json!(receipt))
  end

  defp print(receipt, false) do
    Mix.shell().info("status=#{receipt.status}")
    Mix.shell().info("receipt_ref=#{receipt.receipt_ref}")
    Mix.shell().info("release_ref=#{receipt.release_ref}")
  end
end
