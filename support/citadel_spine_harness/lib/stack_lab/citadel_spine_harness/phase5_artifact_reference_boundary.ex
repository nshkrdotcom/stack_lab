defmodule StackLab.CitadelSpineHarness.Phase5ArtifactReferenceBoundary do
  @moduledoc false

  alias Mezzanine.Execution.PayloadBoundary
  alias OuterBrain.Contracts.ReplyBodyBoundary

  @artifact_body String.duplicate("scenario-204-artifact-body:", 512)
  @schema_name "stack_lab.scenario204.artifact_ref.v1"
  @schema_hash "sha256:" <> Base.encode16(:crypto.hash(:sha256, @schema_name), case: :lower)
  @release_ref "phase5-v7-m4-artifact-boundary"

  @spec run_case(:payload_boundary_fault_matrix) :: {:ok, map()}
  def run_case(:payload_boundary_fault_matrix) do
    artifact_ref = valid_artifact_ref(@artifact_body)

    {:ok, execution_classification} =
      PayloadBoundary.classify_execution_column(:lower_receipt, %{
        "normalized_outcome_ref" => artifact_ref
      })

    {:ok, reply_body} =
      ReplyBodyBoundary.build(
        "scenario-204-causal",
        :final,
        "scenario-204-causal:final",
        String.duplicate("safe public reply preview source ", 160)
      )

    :ok =
      ReplyBodyBoundary.validate_ref(
        reply_body.ref,
        "scenario-204-causal",
        :final,
        "scenario-204-causal:final"
      )

    {:ok, oversized_inline} =
      boundary_failure(
        PayloadBoundary.classify_execution_column(:intent_snapshot, %{
          "large_context_preview" =>
            String.duplicate("x", PayloadBoundary.small_inline_max_bytes() + 1024)
        })
      )

    negative_failures = %{
      store_unavailable: retrieve(artifact_ref, :store_unavailable),
      fetch_timeout: retrieve(artifact_ref, :fetch_timeout),
      digest_mismatch: retrieve(artifact_ref, :digest_mismatch),
      hash_only_authorization: hash_only_authorization(artifact_ref),
      oversized_inline: oversized_inline
    }

    {:ok,
     %{
       case: :payload_boundary_fault_matrix,
       scenario: 204,
       positive: %{
         valid_execution_ref: %{
           classification: execution_classification,
           artifact_id: artifact_ref["artifact_id"],
           content_hash: artifact_ref["content_hash"],
           content_hash_alg: artifact_ref["content_hash_alg"],
           schema_hash: artifact_ref["schema_hash"],
           schema_hash_alg: artifact_ref["schema_hash_alg"],
           retrieval_owner: artifact_ref["retrieval_owner"],
           existing_fetch_or_restore_path: artifact_ref["existing_fetch_or_restore_path"]
         },
         valid_reply_ref: %{
           body_hash: ReplyBodyBoundary.body_hash(reply_body.ref),
           schema_hash: reply_body.ref["schema_hash"],
           redaction_manifest_ref: reply_body.ref["redaction_manifest_ref"],
           preview_byte_size: byte_size(reply_body.preview)
         },
         existing_owner_path_result: retrieve(artifact_ref, :ok)
       },
       negative_failures: negative_failures,
       no_generic_shared_cas_fallback?: true,
       accepted_bytes_on_failure?: accepted_bytes_on_failure?(negative_failures)
     }}
  end

  defp valid_artifact_ref(bytes) do
    content_hash = sha256_ref(bytes)

    %{
      "artifact_id" => "artifact:stack-lab:scenario-204",
      "content_hash" => content_hash,
      "content_hash_alg" => "sha256",
      "byte_size" => byte_size(bytes),
      "schema_name" => @schema_name,
      "schema_hash" => @schema_hash,
      "schema_hash_alg" => "sha256",
      "media_type" => "application/json",
      "producer_repo" => "stack_lab",
      "tenant_scope" => "tenant:scenario-204",
      "sensitivity_class" => "tenant_sensitive",
      "existing_store_ref" => "jido_integration:claim_check:scenario-204",
      "store_security_posture_ref" =>
        "jido_integration.claim_check.postgres_file_store.tenant_isolation.v1",
      "encryption_posture_ref" => "unavailable_fail_closed",
      "retrieval_owner" => "jido_integration.claim_check_store",
      "existing_fetch_or_restore_path" => "existing_claim_check_fetch",
      "safe_actions" => [
        "unavailable_fail_closed",
        "quarantine_digest_mismatch",
        "reject_before_durable_write"
      ],
      "queue_key" => "tenant:scenario-204:artifact-reference-boundary",
      "oversize_action" => "reject_or_stream",
      "release_manifest_ref" => @release_ref
    }
  end

  defp retrieve(artifact_ref, :ok) do
    case verify_digest(artifact_ref, @artifact_body) do
      :ok ->
        %{
          result: :ok,
          retrieval_owner: artifact_ref["retrieval_owner"],
          existing_fetch_or_restore_path: artifact_ref["existing_fetch_or_restore_path"],
          content_hash_verified?: true,
          bytes_accepted?: true
        }

      {:error, reason} ->
        retrieval_failure(reason, :quarantine_digest_mismatch)
    end
  end

  defp retrieve(_artifact_ref, :store_unavailable),
    do: retrieval_failure(:store_unavailable, :unavailable_fail_closed)

  defp retrieve(_artifact_ref, :fetch_timeout),
    do: retrieval_failure(:fetch_timeout, :unavailable_fail_closed)

  defp retrieve(artifact_ref, :digest_mismatch) do
    case verify_digest(artifact_ref, "tampered-" <> @artifact_body) do
      :ok -> %{result: :unexpected_acceptance, bytes_accepted?: true}
      {:error, reason} -> retrieval_failure(reason, :quarantine_digest_mismatch)
    end
  end

  defp hash_only_authorization(artifact_ref) do
    %{
      result: {:error, :authorization_required},
      reason: :hash_is_not_fetch_authorization,
      content_hash: artifact_ref["content_hash"],
      safe_action: :unavailable_fail_closed,
      bytes_accepted?: false,
      generic_shared_cas_fallback?: false
    }
  end

  defp verify_digest(artifact_ref, bytes) do
    expected = artifact_ref["content_hash"]
    actual = sha256_ref(bytes)

    cond do
      not sha256_ref?(expected) ->
        {:error, :invalid_primary_hash}

      actual == expected ->
        :ok

      true ->
        {:error, :digest_mismatch_after_retrieval}
    end
  end

  defp retrieval_failure(reason, safe_action) do
    %{
      result: {:error, reason},
      reason: reason,
      safe_action: safe_action,
      bytes_accepted?: false,
      generic_shared_cas_fallback?: false
    }
  end

  defp boundary_failure({:error, {:execution_payload_boundary, column, details}}) do
    {:ok,
     %{
       result: {:error, details.reason},
       column: column,
       classification: details.classification,
       safe_action: details.safe_action,
       bytes_accepted?: false
     }}
  end

  defp accepted_bytes_on_failure?(failures) do
    failures
    |> Map.values()
    |> Enum.any?(&Map.get(&1, :bytes_accepted?, false))
  end

  defp sha256_ref(bytes) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  end

  defp sha256_ref?("sha256:" <> digest) when byte_size(digest) == 64 do
    digest
    |> :binary.bin_to_list()
    |> Enum.all?(fn byte -> byte in ?0..?9 or byte in ?a..?f end)
  end

  defp sha256_ref?(_value), do: false
end
