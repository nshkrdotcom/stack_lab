defmodule StackLab.AppEnvSandboxTest do
  use ExUnit.Case, async: false

  alias StackLab.AppEnvSandbox

  @app :stack_lab_lab_core
  @key :app_env_sandbox_test_value

  setup do
    AppEnvSandbox.delete(@app, @key)

    on_exit(fn -> AppEnvSandbox.delete(@app, @key) end)
  end

  test "restores a missing key after sandboxed mutation" do
    assert AppEnvSandbox.get(@app, @key, :missing) == :missing

    AppEnvSandbox.with_env([{@app, @key}], fn ->
      AppEnvSandbox.put(@app, @key, "temporary")
      assert AppEnvSandbox.get(@app, @key) == "temporary"
    end)

    assert AppEnvSandbox.get(@app, @key, :missing) == :missing
  end

  test "restores a present nil value distinctly from a missing key" do
    AppEnvSandbox.put(@app, @key, nil)

    AppEnvSandbox.with_env([{:put, @app, @key, "temporary"}], fn ->
      assert AppEnvSandbox.get(@app, @key) == "temporary"
      AppEnvSandbox.delete(@app, @key)
    end)

    assert AppEnvSandbox.get(@app, @key, :missing) == nil
  end

  test "restores after the sandboxed function raises" do
    AppEnvSandbox.put(@app, @key, "original")

    assert_raise RuntimeError, "boom", fn ->
      AppEnvSandbox.with_env([{:put, @app, @key, "temporary"}], fn ->
        raise "boom"
      end)
    end

    assert AppEnvSandbox.get(@app, @key) == "original"
  end

  test "validates app keys" do
    assert_raise ArgumentError, fn ->
      AppEnvSandbox.with_env([{"app", @key}], fn -> :ok end)
    end
  end
end
