defmodule Mix.Tasks.StackLab.Extravaganza.ExternalAcceptance do
  @moduledoc "Runs StackLab external acceptance against Extravaganza's public headless command."

  use Mix.Task

  alias StackLab.ExtravaganzaExternalAcceptance

  @shortdoc "Run external acceptance against Extravaganza headless smoke"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          extravaganza_root: :string,
          receipt: :string,
          json: :boolean
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    run_opts =
      []
      |> maybe_put(opts, :extravaganza_root)

    case ExtravaganzaExternalAcceptance.run(run_opts) do
      {:ok, receipt} ->
        receipt_path =
          Keyword.get(opts, :receipt, ExtravaganzaExternalAcceptance.default_receipt_path())

        path = ExtravaganzaExternalAcceptance.write_receipt!(receipt, receipt_path)
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
    refs = receipt["validated_refs"]

    Mix.shell().info("stack_lab.extravaganza.external_acceptance passed")
    Mix.shell().info("receipt=#{path}")
    Mix.shell().info("product_acceptance_owner=#{receipt["product_acceptance_owner"]}")
    Mix.shell().info("run_ref=#{refs["run_ref"]}")
    Mix.shell().info("lower_terminal_ref=#{refs["lower_terminal_ref"]}")
    Mix.shell().info("provider_smoke=#{receipt["provider_smoke"]["classification"]}")
  end

  defp print_failure(reason, true) do
    %{status: "fail", error: reason}
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()

    exit({:shutdown, 1})
  end

  defp print_failure(reason, false) do
    Mix.shell().error("stack_lab.extravaganza.external_acceptance failed")
    Mix.shell().error("  #{inspect(reason)}")
    exit({:shutdown, 1})
  end
end
