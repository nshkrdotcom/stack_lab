defmodule Mix.Tasks.StackLab.Fugu.PostCutoverHardening do
  @moduledoc "Writes the fugu post-cutover hardening receipt."

  use Mix.Task

  alias StackLab.FuguPostCutoverHardening

  @shortdoc "Write the fugu post-cutover hardening receipt"

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

    {:ok, receipt} = FuguPostCutoverHardening.run(run_opts)
    receipt_path = Keyword.get(opts, :receipt, FuguPostCutoverHardening.default_receipt_path())
    path = FuguPostCutoverHardening.write_receipt!(receipt, receipt_path)
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
    Mix.shell().info("stack_lab.fugu.post_cutover_hardening passed")
    Mix.shell().info("receipt=#{path}")
    Mix.shell().info("receipt_ref=#{receipt["receipt_ref"]}")
  end
end
