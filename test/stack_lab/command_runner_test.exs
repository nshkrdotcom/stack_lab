defmodule StackLab.CommandRunnerTest do
  use ExUnit.Case, async: true

  alias StackLab.CommandRunner
  alias StackLab.CommandRunner.Receipt

  test "validates cwd before running" do
    missing = Path.join(System.tmp_dir!(), "stack_lab_missing_cwd")

    assert {:error, %Receipt{status: :blocked, reason: {:invalid_cwd, ^missing}}} =
             CommandRunner.run("pwd", [], cd: missing)
  end

  test "records timeout metadata and rejects invalid timeouts" do
    assert {:ok, %Receipt{timeout_ms: 25_000}} = CommandRunner.run("pwd", [], timeout: 25_000)

    assert {:error, %Receipt{reason: {:invalid_timeout_ms, 0}}} =
             CommandRunner.run("pwd", [], timeout: 0)
  end

  test "enforces env allowlist" do
    assert {:error, %Receipt{reason: {:env_key_not_allowed, "SECRET_TOKEN"}}} =
             CommandRunner.run("pwd", [],
               env: [{"SECRET_TOKEN", "secret"}],
               env_allowlist: ["SAFE_TOKEN"]
             )
  end

  test "redacts configured secrets from output receipts" do
    assert {:ok, %Receipt{output: output, redacted?: true}} =
             CommandRunner.run("printf", ["token=secret-value"], redact: ["secret-value"])

    assert output == "token=[REDACTED]"
  end

  test "blocks shell metacharacters unless shell mode is explicit" do
    assert {:error, %Receipt{reason: {:blocked_shell_token, "status; rm -rf workspace"}}} =
             CommandRunner.run("git", ["status; rm -rf workspace"])

    assert {:error, %Receipt{reason: :shell_mode_requires_explicit_allowance}} =
             CommandRunner.run("sh", ["-lc", "echo ok"])

    assert {:ok, %Receipt{shell?: true, output: "ok\n"}} =
             CommandRunner.run("sh", ["-lc", "echo ok"], allow_shell: true)
  end
end
