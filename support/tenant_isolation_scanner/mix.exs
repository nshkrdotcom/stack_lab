defmodule StackLab.TenantIsolationScanner.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_tenant_isolation_scanner,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      name: "StackLab Tenant Isolation Scanner",
      description:
        "Tenant isolation receipts for auth, connector, target, projection, trace, memory, and receipt state"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  defp deps do
    [
      {:stack_lab_lab_core, path: "../lab_core"},
      {:stack_lab_spec_cell, path: "../spec_cell"},
      {:stack_lab_gn_ten_control_plane, path: "../gn_ten_control_plane"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
