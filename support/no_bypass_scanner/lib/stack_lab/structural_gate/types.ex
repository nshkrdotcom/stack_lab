defmodule StackLab.StructuralGateScanner.AllowlistEntry do
  @moduledoc """
  Explicit scanner allowlist entry.
  """
  @enforce_keys [:token, :path, :reason, :owner, :expires, :permanent_zone]
  @type t :: %__MODULE__{
          token: String.t() | atom(),
          path: String.t(),
          reason: String.t(),
          owner: String.t(),
          expires: String.t(),
          permanent_zone: boolean()
        }
  defstruct @enforce_keys
end

defmodule StackLab.StructuralGateScanner.Finding do
  @moduledoc """
  Structural scanner finding.
  """
  alias StackLab.StructuralGateScanner.AllowlistEntry

  @enforce_keys [
    :rule,
    :reason,
    :path,
    :line,
    :zone,
    :owner_phase,
    :severity,
    :ast_role,
    :remediation
  ]
  @type t :: %__MODULE__{
          rule: atom(),
          reason: atom(),
          path: String.t(),
          package_path: String.t() | nil,
          line: non_neg_integer(),
          zone: atom(),
          owner_phase: String.t(),
          severity: :error | :warning,
          token: String.t() | atom() | nil,
          ast_role: atom(),
          remediation: String.t(),
          allowlist_entry: AllowlistEntry.t() | nil,
          structural_proof_status: atom() | nil
        }
  defstruct [
    :rule,
    :reason,
    :path,
    :package_path,
    :line,
    :zone,
    :owner_phase,
    :severity,
    :token,
    :ast_role,
    :remediation,
    :allowlist_entry,
    :structural_proof_status
  ]
end

defmodule StackLab.StructuralGateScanner.SkippedPath do
  @moduledoc """
  Path skipped by structural scanner traversal.
  """
  @enforce_keys [:path, :reason]
  @type t :: %__MODULE__{path: String.t(), reason: atom()}
  defstruct @enforce_keys
end

defmodule StackLab.StructuralGateScanner.CheckedPath do
  @moduledoc """
  Path checked by structural scanner traversal.
  """
  @enforce_keys [:path, :repo, :zone, :package_path]
  @type t :: %__MODULE__{
          path: String.t(),
          repo: String.t(),
          zone: atom(),
          package_path: String.t() | nil
        }
  defstruct @enforce_keys
end

defmodule StackLab.StructuralGateScanner.ProofBundle do
  @moduledoc """
  Static proof bundle for a generic operation entry point.
  """
  @enforce_keys [
    :path,
    :line,
    :entrypoint_id,
    :entrypoint_kind,
    :operation_name,
    :operation_arity,
    :zone,
    :status,
    :checks,
    :missing_checks,
    :paired_test_path,
    :negative_fixture_id,
    :remote_boundary
  ]
  @type t :: %__MODULE__{
          path: String.t(),
          line: non_neg_integer(),
          entrypoint_id: atom() | nil,
          entrypoint_kind: atom(),
          operation_name: atom(),
          operation_arity: non_neg_integer(),
          zone: atom(),
          status: :passed | :incomplete,
          checks: %{atom() => boolean()},
          missing_checks: [atom()],
          paired_test_path: String.t() | nil,
          negative_fixture_id: atom() | nil,
          remote_boundary: map()
        }
  defstruct @enforce_keys
end

defmodule StackLab.StructuralGateScanner.Receipt do
  @moduledoc """
  Structural scanner receipt for Phase 6A.
  """
  alias StackLab.StructuralGateScanner.{CheckedPath, Finding, ProofBundle, SkippedPath}

  @enforce_keys [
    :scanner,
    :scanner_version,
    :mode,
    :target_roots,
    :target_scope_status,
    :checked_paths,
    :skipped_paths,
    :zones,
    :findings,
    :proof_bundles,
    :remote_boundary,
    :status
  ]
  @type t :: %__MODULE__{
          scanner: String.t(),
          scanner_version: String.t(),
          mode: atom(),
          target_roots: %{String.t() => String.t()},
          target_scope_status: :exact_target_roots | :custom_target_roots,
          checked_paths: [CheckedPath.t()],
          skipped_paths: [SkippedPath.t()],
          zones: %{atom() => non_neg_integer()},
          findings: [Finding.t()],
          proof_bundles: [ProofBundle.t()],
          remote_boundary: map(),
          status: :pass | :open_defect | :baseline_findings
        }
  defstruct @enforce_keys
end
