defmodule Mix.Tasks.StackLab.ProofApp.ToyDocumentReview.Acceptance do
  @moduledoc "Runs the full deterministic neutral-product acceptance proof."

  use Mix.Task

  alias StackLab.Examples.ToyDocumentReview
  alias StackLab.Examples.ToyDocumentReview.LocalHttpService

  @shortdoc "Run the Toy Document Review proof-app acceptance suite"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("setup")
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          json: :boolean
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    {:ok, supervisor} =
      Supervisor.start_link([{LocalHttpService, name: __MODULE__.LocalHttpService}],
        strategy: :one_for_one
      )

    try do
      service = Process.whereis(__MODULE__.LocalHttpService)

      case ToyDocumentReview.run_full_acceptance(service: service) do
        {:ok, %{accepted?: true} = receipt} ->
          print_success(receipt, Keyword.get(opts, :json, false))

        {:ok, receipt} ->
          print_failure({:acceptance_not_accepted, receipt}, Keyword.get(opts, :json, false))

        {:error, reason} ->
          print_failure(reason, Keyword.get(opts, :json, false))
      end
    after
      Supervisor.stop(supervisor)
    end
  end

  defp print_success(receipt, true) do
    receipt
    |> json_safe()
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp print_success(receipt, false) do
    Mix.shell().info("stack_lab.proof_app.toy_document_review.acceptance passed")
    Mix.shell().info("component_path=#{Enum.join(receipt.component_path, ",")}")
    Mix.shell().info("operation_count=#{receipt.foundation.operation_count}")
    Mix.shell().info("gate3_accepted=#{receipt.full_gate3.accepted?}")
  end

  defp print_failure(reason, true) do
    %{status: "fail", error: inspect(reason)}
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()

    exit({:shutdown, 1})
  end

  defp print_failure(reason, false) do
    Mix.shell().error("stack_lab.proof_app.toy_document_review.acceptance failed")
    Mix.shell().error("  #{inspect(reason)}")
    exit({:shutdown, 1})
  end

  defp json_safe(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> json_safe()
  end

  defp json_safe(%{} = map) do
    Map.new(map, fn {key, value} -> {json_key(key), json_safe(value)} end)
  end

  defp json_safe(values) when is_list(values), do: Enum.map(values, &json_safe/1)

  defp json_safe(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> json_safe()
  end

  defp json_safe(value) when is_boolean(value) or is_nil(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value), do: value

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: key
end
