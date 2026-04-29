defmodule Mix.Tasks.GnTen.Review.Summary do
  @moduledoc "Summarizes and validates a gn-ten batch receipt for review."

  use Mix.Task

  alias StackLab.GnTen.{BatchReceipt, ReviewSummary}

  @shortdoc "Validates a gn-ten batch receipt review summary"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [batch: :string, receipt_dir: :string, root: :string]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    batch = Keyword.get(opts, :batch) || Mix.raise("expected --batch <slug>")

    summary_opts = [
      receipt_dir: Keyword.get(opts, :receipt_dir, BatchReceipt.default_out_dir()),
      root: Keyword.get(opts, :root, File.cwd!())
    ]

    case ReviewSummary.summarize(batch, summary_opts) do
      {:ok, report} ->
        Mix.shell().info("gn_ten.review.summary passed")
        Mix.shell().info("batch_id=#{report.batch_id}")
        Mix.shell().info("receipt=#{report.receipt_path}")
        Mix.shell().info("commands=#{report.command_count}")
        Mix.shell().info("closeout=#{report.closeout_count}")
        Mix.shell().info("traces=#{report.trace_count}")

      {:error, report} ->
        Mix.shell().error("gn_ten.review.summary failed")
        Mix.shell().error("batch_id=#{report.batch_id}")
        Mix.shell().error("failures=#{inspect(report.failures)}")
        exit({:shutdown, 1})
    end
  end
end
