defmodule StackLab.GnTen.ProductNoBypassTest do
  use ExUnit.Case, async: false

  @stack_lab_root Path.expand("../..", __DIR__)
  @workspace_root Path.expand("..", @stack_lab_root)
  @app_kit_root Path.join(@workspace_root, "app_kit")
  @fixtures_root Path.join(@stack_lab_root, "fixtures/products")

  test "AppKit scanner accepts a minimal product fixture" do
    assert {output, 0} = scan_fixture("proof_product_minimal")
    assert output =~ "app_kit.no_bypass passed"
  end

  test "AppKit scanner rejects hostile product bypass imports" do
    assert {output, status} = scan_fixture("proof_product_hostile")
    assert status != 0
    assert output =~ "boundary violation"
    assert output =~ "AppKit.Bridges"
    assert output =~ "Mezzanine"
  end

  defp scan_fixture(name) do
    System.cmd(
      "mix",
      [
        "app_kit.no_bypass.scan",
        "--root",
        Path.join(@fixtures_root, name),
        "--profile",
        "product",
        "--profile",
        "hazmat",
        "--include",
        "lib/**/*.ex"
      ],
      cd: @app_kit_root,
      env: [{"MIX_ENV", "test"}],
      stderr_to_stdout: true
    )
  end
end
