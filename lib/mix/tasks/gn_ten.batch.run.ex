defmodule Mix.Tasks.GnTen.Batch.Run do
  @moduledoc "Runs a gn-ten repo-local CI batch and writes receipts."

  use Mix.Task

  alias StackLab.GnTen.{BatchReceipt, BatchRunner, Manifest}

  @shortdoc "Runs a gn-ten repo-local CI batch"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          name: :string,
          dry_run: :boolean,
          resume: :boolean,
          confirm: :boolean,
          manifest: :string,
          out: :string,
          trace_out: :string
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    opts
    |> Keyword.fetch(:name)
    |> run_batch(opts)
  end

  defp run_batch(:error, _opts), do: Mix.raise("expected --name <slug>")

  defp run_batch({:ok, name}, opts) do
    runner_opts = [
      dry_run?: Keyword.get(opts, :dry_run, false),
      resume?: Keyword.get(opts, :resume, false),
      confirm?: Keyword.get(opts, :confirm, false),
      manifest_path: Keyword.get(opts, :manifest, Manifest.default_path()),
      out_dir: Keyword.get(opts, :out, BatchReceipt.default_out_dir()),
      trace_dir: Keyword.get(opts, :trace_out, BatchRunner.default_trace_dir())
    ]

    case BatchRunner.run(name, runner_opts) do
      {:ok, result} ->
        Mix.shell().info("gn_ten.batch.run #{result.status}")
        Mix.shell().info("batch_id=#{result.batch_id}")
        Mix.shell().info("markdown=#{result.md_path}")
        Mix.shell().info("json=#{result.json_path}")
        Mix.shell().info("trace=#{result.trace_path}")

      {:error, error} ->
        Mix.shell().error("gn_ten.batch.run failed: #{inspect(error)}")
        exit({:shutdown, 1})
    end
  end
end
