defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.Fixtures do
  @moduledoc false

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support

  for {name, arity} <- [
        lower_backed_install_template!: 0,
        activate_fixture_registration!: 1,
        activate_governed_workload_registration!: 0,
        governed_workload_fixture_stack: 1,
        governed_workload_install_template!: 0,
        governed_workload_attrs: 0,
        bare_asm_substitute_attrs: 0,
        governed_workload_summary: 1,
        operational_fixture_stack: 1,
        operational_fixture_stack: 2,
        workflow_body: 1,
        connector_console_case_file: 3,
        latest_execution_id: 2,
        choose_operator_action: 1,
        choose_operator_action: 2,
        payload_value: 2,
        map_value!: 2,
        optional_map_value: 2,
        optional_map_value: 3,
        map_value: 2,
        bounded_atom_key_value: 2,
        normalize_runtime_class: 1,
        semantic_failure_carrier!: 3,
        semantic_failure_carrier_value: 2
      ] do
    args = Macro.generate_arguments(arity, __MODULE__)
    defdelegate unquote(name)(unquote_splicing(args)), to: Support
  end
end
