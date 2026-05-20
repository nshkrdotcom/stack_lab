defmodule StackLab.Examples.ToyDocumentReview.FixtureFaultMatrix do
  @moduledoc false

  alias StackLab.Examples.ToyDocumentReview.LocalHttpService

  def run(service) do
    now = ~U[2026-05-17 00:01:00Z]
    expired_at = ~U[2026-05-17 00:00:00Z]
    refreshed_lease = "credential-lease://toy-document-review/local-http/refreshed"

    {:ok, _refresh} = LocalHttpService.refresh_lease(service, refreshed_lease)

    base = [
      credential_lease_ref: refreshed_lease,
      schema_version: LocalHttpService.schema_version(),
      now: now
    ]

    matrix = %{
      retryable_failure:
        LocalHttpService.request(
          service,
          :get,
          "/documents",
          Keyword.put(base, :failure_mode, :retryable)
        ),
      terminal_failure:
        LocalHttpService.request(
          service,
          :get,
          "/documents",
          Keyword.put(base, :failure_mode, :terminal)
        ),
      auth_rejection:
        LocalHttpService.request(
          service,
          :get,
          "/documents",
          Keyword.put(base, :credential_lease_ref, "credential-lease://wrong")
        ),
      credential_expiry:
        LocalHttpService.request(
          service,
          :get,
          "/documents",
          base
          |> Keyword.put(:lease_expires_at, expired_at)
          |> Keyword.put(:now, now)
        ),
      schema_mismatch:
        LocalHttpService.request(
          service,
          :get,
          "/documents",
          Keyword.put(base, :schema_version, "toy-document-review.v0")
        ),
      timeout:
        LocalHttpService.request(service, :get, "/documents", Keyword.put(base, :timeout_ms, 1)),
      ordered_page_one:
        LocalHttpService.request(service, :get, "/events", base ++ [cursor: 0, page_size: 2]),
      ordered_page_two:
        LocalHttpService.request(service, :get, "/events", base ++ [cursor: 2, page_size: 2])
    }

    {:ok, _restore} =
      LocalHttpService.refresh_lease(service, LocalHttpService.default_lease_ref())

    matrix
  end

  def summary(matrix) do
    %{
      retryable_failure?: fault_reason?(matrix.retryable_failure, :retryable_failure),
      terminal_failure?: fault_reason?(matrix.terminal_failure, :terminal_failure),
      auth_rejection?: fault_reason?(matrix.auth_rejection, :auth_rejected),
      credential_expiry?: fault_reason?(matrix.credential_expiry, :credential_expired),
      schema_mismatch?: fault_reason?(matrix.schema_mismatch, :schema_version_mismatch),
      timeout?: fault_reason?(matrix.timeout, :timeout),
      pagination_ordered?: pagination_ordered?(matrix.ordered_page_one, matrix.ordered_page_two)
    }
  end

  defp fault_reason?({:error, %{reason: reason}}, reason), do: true
  defp fault_reason?(_result, _reason), do: false

  defp pagination_ordered?({:ok, page_one}, {:ok, page_two}) do
    Enum.map(page_one.body.events ++ page_two.body.events, & &1.sequence) == [1, 2, 3]
  end

  defp pagination_ordered?(_page_one, _page_two), do: false
end
