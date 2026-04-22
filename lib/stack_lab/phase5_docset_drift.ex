defmodule StackLab.Phase5DocsetDrift do
  @moduledoc """
  Phase 5 docset drift checker for Stack Lab release evidence.

  The checker compares the release manifest, Stack Lab spec, runbook index,
  runbook files, master checklist, runtime envelopes, and Scenario 212 semantic
  predicate profile. It deliberately treats Stack Lab prose as one input, not as
  the authority for its own drift check.
  """

  @checker_ref "stack_lab:lib/stack_lab/phase5_docset_drift.ex + mix phase5.docset_drift"
  @semantic_profile_key "m10_scenario_212_semantic_closeout_predicate_check"
  @required_runbook_sections [
    "Failure Mode",
    "Expected Safe Action",
    "Operator Procedure",
    "Evidence To Collect",
    "Code Reduction Expectation",
    "Stop Conditions"
  ]
  @credential_patterns [
    ~r/\bAKIA[0-9A-Z]{16}\b/,
    ~r/\bghp_[A-Za-z0-9_]{20,}\b/,
    ~r/\bsk-[A-Za-z0-9]{20,}\b/,
    ~r/-----BEGIN [A-Z ]*PRIVATE KEY-----/
  ]

  @type check_result :: {:ok, map()} | {:error, map()}

  @spec checker_ref() :: String.t()
  def checker_ref, do: @checker_ref

  @spec default_docs_root() :: Path.t()
  def default_docs_root do
    stack_lab_root = Path.expand("../..", __DIR__)

    Path.expand(
      "../../j/jido_brainstorm/nshkrdotcom/docs/20260419/ecosystem_buildout_phase5",
      stack_lab_root
    )
  end

  @spec run(keyword()) :: check_result()
  def run(opts \\ []) do
    docs_root =
      Keyword.get(opts, :docs_root) || System.get_env("PHASE5_DOCS_ROOT") ||
        default_docs_root()

    stack_lab_root = Keyword.get(opts, :stack_lab_root) || Path.expand("../..", __DIR__)

    with {:ok, manifest} <- read_manifest(docs_root),
         {:ok, spec} <- read_text(docs_root, "stack_lab/STACK_LAB_SPEC.md"),
         {:ok, readme} <- read_text(docs_root, "runbooks/README.md"),
         {:ok, checklist} <- read_text(docs_root, "v7/0010_master_checklist.md") do
      result =
        build_result(%{
          docs_root: docs_root,
          stack_lab_root: stack_lab_root,
          manifest: manifest,
          spec: spec,
          readme: readme,
          checklist: checklist
        })

      if result.status == :pass do
        {:ok, result}
      else
        {:error, result}
      end
    end
  end

  defp read_manifest(docs_root) do
    with {:ok, body} <- read_text(docs_root, "contracts/phase5_release_manifest.json"),
         {:ok, manifest} <- Jason.decode(body) do
      {:ok, manifest}
    else
      {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_manifest_json, error}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_text(docs_root, relative_path) do
    docs_root
    |> Path.join(relative_path)
    |> File.read()
  end

  defp build_result(context) do
    manifest = context.manifest
    targeted_proofs = Map.fetch!(manifest, "targeted_proofs")
    runtime_envelopes = Map.fetch!(manifest, "stack_lab_runtime_envelopes")

    manifest_ids = targeted_proofs |> Enum.map(&normalise_id(&1["id"])) |> Enum.sort()
    spec_ids = context.spec |> spec_scenario_ids() |> Enum.sort()
    manifest_runbooks = manifest_runbook_names(targeted_proofs)
    spec_runbooks = spec_runbook_names(context.spec)
    readme_index = context.readme |> runbook_readme_index() |> Enum.sort()
    filesystem_paths = context.docs_root |> runbook_filesystem_paths() |> Enum.sort()
    checklist_refs = checklist_scenario_refs(context.checklist, manifest_ids)
    source_backed = source_backed_proofs(targeted_proofs)

    checks = [
      scenario_id_alignment(manifest_ids, spec_ids),
      runbook_index_alignment(manifest_runbooks, spec_runbooks, readme_index, filesystem_paths),
      checklist_ref_alignment(checklist_refs),
      runtime_envelope_alignment(manifest_ids, runtime_envelopes, source_backed),
      operator_runbook_audit(context.docs_root, readme_index),
      semantic_closeout_audit(manifest),
      fixture_hygiene_audit(context.stack_lab_root)
    ]

    failures =
      checks
      |> Enum.flat_map(& &1.failures)

    %{
      status: if(failures == [], do: :pass, else: :fail),
      failures: failures,
      release_manifest_scenario_ids: manifest_ids,
      stack_lab_spec_scenario_ids: spec_ids,
      runbook_readme_index: readme_index,
      runbook_filesystem_paths: filesystem_paths,
      master_checklist_scenario_refs: checklist_refs,
      source_backed_scenario_ids: Enum.map(source_backed, &normalise_id(&1["id"])),
      checker_source_or_command_ref: @checker_ref,
      checker_digest_or_commit_ref: checker_digest(),
      audits: checks_to_map(checks)
    }
  end

  defp checks_to_map(checks) do
    Map.new(checks, fn check -> {check.name, Map.delete(check, :name)} end)
  end

  defp spec_scenario_ids(spec) do
    spec
    |> section("## Scenario Matrix", "## Runtime Envelope Matrix")
    |> markdown_table_rows()
    |> Enum.map(fn row -> normalise_id(Enum.at(row, 0)) end)
  end

  defp spec_runbook_names(spec) do
    ~r/`runbooks\/([^`]+\.md)`/
    |> Regex.scan(section(spec, "## Scenario Matrix", "## Runtime Envelope Matrix"))
    |> Enum.map(fn [_match, name] -> name end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp runbook_readme_index(readme) do
    ~r/- `([^`]+\.md)`/
    |> Regex.scan(section(readme, "## Runbook Index", "## Standard Fields"))
    |> Enum.map(fn [_match, name] -> name end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp runbook_filesystem_paths(docs_root) do
    docs_root
    |> Path.join("runbooks/*.md")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.reject(&(&1 == "README.md"))
    |> Enum.sort()
  end

  defp manifest_runbook_names(targeted_proofs) do
    targeted_proofs
    |> Enum.map(& &1["runbook"])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Path.basename/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp markdown_table_rows(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "|"))
    |> Enum.map(fn line ->
      line
      |> String.trim()
      |> String.trim_leading("|")
      |> String.trim_trailing("|")
      |> String.split("|")
      |> Enum.map(&String.trim/1)
    end)
    |> Enum.reject(fn
      ["Scenario" | _] -> true
      ["---" | _] -> true
      _other -> false
    end)
  end

  defp section(text, start_heading, end_heading) do
    [_before, after_start] = String.split(text, start_heading, parts: 2)

    case String.split(after_start, end_heading, parts: 2) do
      [body, _after] -> body
      [body] -> body
    end
  rescue
    MatchError -> ""
  end

  defp normalise_id(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.trim("`")
  end

  defp checklist_scenario_refs(checklist, scenario_ids) do
    Map.new(scenario_ids, fn scenario_id ->
      pattern = ~r/\b#{Regex.escape(scenario_id)}\b/
      {scenario_id, length(Regex.scan(pattern, checklist))}
    end)
  end

  defp source_backed_proofs(targeted_proofs) do
    Enum.filter(targeted_proofs, fn proof ->
      source_ref = proof["source_ref"]
      output_ref = proof["output_ref"] || proof["proof_output_ref"]

      is_binary(source_ref) and is_binary(output_ref)
    end)
  end

  defp scenario_id_alignment(manifest_ids, spec_ids) do
    %{
      name: :scenario_id_alignment,
      status: pass_fail(manifest_ids == spec_ids),
      failures: diff_failure(:scenario_id_mismatch, manifest_ids, spec_ids)
    }
  end

  defp runbook_index_alignment(manifest_runbooks, spec_runbooks, readme_index, filesystem_paths) do
    failures =
      []
      |> maybe_subset(:manifest_runbook_not_in_readme, manifest_runbooks, readme_index)
      |> maybe_subset(:spec_runbook_not_in_readme, spec_runbooks, readme_index)
      |> maybe_diff(:readme_filesystem_mismatch, readme_index, filesystem_paths)

    %{
      name: :runbook_index_alignment,
      status: pass_fail(failures == []),
      failures: failures,
      manifest_runbooks: manifest_runbooks,
      spec_runbooks: spec_runbooks
    }
  end

  defp checklist_ref_alignment(checklist_refs) do
    missing =
      checklist_refs
      |> Enum.filter(fn {_id, count} -> count == 0 end)
      |> Enum.map(fn {id, _count} -> id end)

    failures =
      if missing == [] do
        []
      else
        [%{check: :master_checklist_missing_scenario_refs, missing: missing}]
      end

    %{
      name: :checklist_ref_alignment,
      status: pass_fail(failures == []),
      failures: failures
    }
  end

  defp runtime_envelope_alignment(manifest_ids, runtime_envelopes, source_backed) do
    envelopes_by_id = Map.new(runtime_envelopes, &{normalise_id(&1["scenario_id"]), &1})
    envelope_ids = envelopes_by_id |> Map.keys() |> Enum.sort()

    failures =
      []
      |> maybe_diff(:runtime_envelope_id_mismatch, manifest_ids, envelope_ids)
      |> Kernel.++(base_runtime_envelope_failures(envelopes_by_id))
      |> Kernel.++(source_backed_runtime_failures(source_backed, envelopes_by_id))

    %{
      name: :runtime_envelope_alignment,
      status: pass_fail(failures == []),
      failures: failures,
      source_backed_count: length(source_backed)
    }
  end

  defp base_runtime_envelope_failures(envelopes_by_id) do
    required = [
      "scenario_id",
      "runtime_class",
      "expected_local_max_ms",
      "ci_timeout_ms",
      "measurement_scope",
      "timeout_safe_action"
    ]

    envelopes_by_id
    |> Enum.flat_map(fn {scenario_id, envelope} ->
      missing = Enum.reject(required, &present?(envelope[&1]))

      beam_missing =
        if envelope["runtime_class"] == "beam_hot_path_load" do
          Enum.reject(
            ["sustained_load_duration_ms", "sustained_load_min_operations"],
            &present?(envelope[&1])
          )
        else
          []
        end

      case missing ++ beam_missing do
        [] ->
          []

        fields ->
          [%{check: :runtime_envelope_missing_fields, scenario_id: scenario_id, fields: fields}]
      end
    end)
  end

  defp source_backed_runtime_failures(source_backed, envelopes_by_id) do
    source_backed
    |> Enum.flat_map(fn proof ->
      scenario_id = normalise_id(proof["id"])
      envelope = Map.get(envelopes_by_id, scenario_id, %{})

      proof_fields =
        ["proof_status", "source_ref", "owning_milestone"]
        |> Enum.reject(&present?(proof[&1]))

      output_present? = present?(proof["output_ref"]) or present?(proof["proof_output_ref"])

      runtime_fields =
        [
          "positive_path_runtime_ref",
          "negative_failure_runtime_ref",
          "observed_local_or_ci_runtime_ms",
          "timeout_result",
          "proof_output_ref"
        ]
        |> Enum.reject(&present?(envelope[&1]))

      runtime_exceeded? =
        is_number(envelope["observed_local_or_ci_runtime_ms"]) and
          is_number(envelope["ci_timeout_ms"]) and
          envelope["observed_local_or_ci_runtime_ms"] > envelope["ci_timeout_ms"]

      []
      |> append_if(proof_fields != [], %{
        check: :source_backed_proof_missing_fields,
        scenario_id: scenario_id,
        fields: proof_fields
      })
      |> append_if(not output_present?, %{
        check: :source_backed_proof_missing_output_ref,
        scenario_id: scenario_id
      })
      |> append_if(runtime_fields != [], %{
        check: :source_backed_runtime_missing_fields,
        scenario_id: scenario_id,
        fields: runtime_fields
      })
      |> append_if(runtime_exceeded?, %{
        check: :source_backed_runtime_exceeds_ci_timeout,
        scenario_id: scenario_id,
        observed_ms: envelope["observed_local_or_ci_runtime_ms"],
        ci_timeout_ms: envelope["ci_timeout_ms"]
      })
    end)
  end

  defp operator_runbook_audit(docs_root, readme_index) do
    failures =
      Enum.flat_map(readme_index, fn runbook ->
        path = Path.join([docs_root, "runbooks", runbook])

        case File.read(path) do
          {:ok, body} ->
            section_failures(runbook, body) ++ operator_steps_failures(runbook, body)

          {:error, reason} ->
            [%{check: :runbook_file_unreadable, runbook: runbook, reason: reason}]
        end
      end)

    %{
      name: :operator_runbook_audit,
      status: pass_fail(failures == []),
      failures: failures,
      audited_runbooks: length(readme_index)
    }
  end

  defp section_failures(runbook, body) do
    missing =
      @required_runbook_sections
      |> Enum.reject(&String.contains?(body, "## #{&1}"))

    if missing == [] do
      []
    else
      [%{check: :runbook_missing_required_sections, runbook: runbook, sections: missing}]
    end
  end

  defp operator_steps_failures(runbook, body) do
    steps =
      ~r/^\d+\.\s+/m
      |> Regex.scan(section(body, "## Operator Procedure", "## Evidence To Collect"))
      |> length()

    if steps >= 4 do
      []
    else
      [%{check: :runbook_operator_procedure_too_thin, runbook: runbook, step_count: steps}]
    end
  end

  defp semantic_closeout_audit(manifest) do
    schema = Map.fetch!(manifest, "semantic_closeout_profile_schema")
    required_predicates = schema |> Map.fetch!("predicate_ids") |> Enum.sort()
    allowed_statuses = Map.fetch!(schema, "predicate_status_values")
    profile = Map.get(manifest, @semantic_profile_key, %{})
    matrix = Map.get(profile, "predicate_matrix", [])

    structural_only? =
      matrix == [] or profile["structural_only_rejected"] != true or
        profile["negative_structural_only_fixture_rejected"] != true

    predicate_ids = matrix |> Enum.map(& &1["predicate_id"]) |> Enum.sort()

    failures =
      []
      |> append_if(profile == %{}, %{check: :semantic_closeout_profile_missing})
      |> append_if(structural_only?, %{check: :semantic_closeout_structural_only})
      |> maybe_diff(:semantic_closeout_predicate_id_mismatch, required_predicates, predicate_ids)
      |> Kernel.++(semantic_predicate_field_failures(matrix, allowed_statuses))

    %{
      name: :semantic_closeout_audit,
      status: pass_fail(failures == []),
      failures: failures,
      predicate_count: length(matrix),
      profile_key: @semantic_profile_key
    }
  end

  defp semantic_predicate_field_failures(matrix, allowed_statuses) do
    required = [
      "predicate_id",
      "predicate_status",
      "source_anchor_refs",
      "evidence_refs",
      "failing_anchor_refs",
      "checker_source_or_command_ref",
      "release_manifest_ref"
    ]

    Enum.flat_map(matrix, fn predicate ->
      predicate_id = predicate["predicate_id"] || "unknown"

      missing = Enum.reject(required, &predicate_field_present?(predicate, &1))

      predicate_status_failures(predicate_id, predicate, allowed_statuses) ++
        predicate_missing_field_failures(predicate_id, missing)
    end)
  end

  defp predicate_field_present?(predicate, "failing_anchor_refs"),
    do: Map.has_key?(predicate, "failing_anchor_refs")

  defp predicate_field_present?(predicate, field), do: present?(predicate[field])

  defp predicate_status_failures(predicate_id, predicate, allowed_statuses) do
    if predicate["predicate_status"] in allowed_statuses do
      []
    else
      [
        %{
          check: :semantic_closeout_invalid_predicate_status,
          predicate_id: predicate_id,
          status: predicate["predicate_status"]
        }
      ]
    end
  end

  defp predicate_missing_field_failures(_predicate_id, []), do: []

  defp predicate_missing_field_failures(predicate_id, missing) do
    [
      %{
        check: :semantic_closeout_predicate_missing_fields,
        predicate_id: predicate_id,
        fields: missing
      }
    ]
  end

  defp fixture_hygiene_audit(stack_lab_root) do
    paths =
      [
        "lib/**/*.ex",
        "test/**/*.exs",
        "support/citadel_spine_harness/lib/**/*.ex",
        "support/citadel_spine_harness/test/**/*.exs"
      ]
      |> Enum.flat_map(&Path.wildcard(Path.join(stack_lab_root, &1)))

    failures =
      Enum.flat_map(paths, fn path ->
        body = File.read!(path)
        sensitive_literal_failures(path, body, stack_lab_root)
      end)

    %{
      name: :fixture_hygiene_audit,
      status: pass_fail(failures == []),
      failures: failures,
      scanned_files: length(paths)
    }
  end

  defp sensitive_literal_failures(path, body, stack_lab_root) do
    @credential_patterns
    |> Enum.filter(&Regex.match?(&1, body))
    |> Enum.map(fn _pattern ->
      %{check: :fixture_sensitive_literal_match, path: Path.relative_to(path, stack_lab_root)}
    end)
  end

  defp diff_failure(kind, expected, actual) do
    if expected == actual do
      []
    else
      [
        %{
          check: kind,
          missing_from_actual: expected -- actual,
          unexpected_in_actual: actual -- expected
        }
      ]
    end
  end

  defp maybe_diff(failures, kind, expected, actual),
    do: failures ++ diff_failure(kind, expected, actual)

  defp maybe_subset(failures, kind, expected_subset, actual) do
    missing = expected_subset -- actual

    if missing == [] do
      failures
    else
      failures ++ [%{check: kind, missing_from_actual: missing}]
    end
  end

  defp append_if(list, true, item), do: list ++ [item]
  defp append_if(list, false, _item), do: list

  defp pass_fail(true), do: :pass
  defp pass_fail(false), do: :fail

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(nil), do: false
  defp present?(_value), do: true

  defp checker_digest do
    __ENV__.file
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&("sha256:" <> &1))
  end
end
