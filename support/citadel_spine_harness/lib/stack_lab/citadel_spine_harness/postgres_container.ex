defmodule StackLab.CitadelSpineHarness.PostgresContainer do
  @moduledoc false

  @image System.get_env("STACK_LAB_TEST_POSTGRES_IMAGE") || "postgres:16-alpine"
  @database "stack_lab_test"
  @password "postgres"
  @username "postgres"

  @spec start!(String.t()) :: %{container_id: String.t(), port: pos_integer()}
  def start!(label) when is_binary(label) do
    {output, 0} =
      System.cmd(
        "docker",
        [
          "run",
          "--detach",
          "--rm",
          "--label",
          "stack_lab_test=#{label}",
          "--env",
          "POSTGRES_DB=#{@database}",
          "--env",
          "POSTGRES_PASSWORD=#{@password}",
          "--env",
          "POSTGRES_USER=#{@username}",
          "--publish",
          "127.0.0.1::5432",
          @image
        ],
        stderr_to_stdout: true
      )

    container_id = String.trim(output)
    port = host_port!(container_id)

    wait_until_ready!(port)

    %{container_id: container_id, port: port}
  end

  @spec stop!(map()) :: :ok
  def stop!(%{container_id: container_id}) do
    _ = System.cmd("docker", ["rm", "--force", container_id], stderr_to_stdout: true)
    :ok
  end

  @spec repo_config(pos_integer()) :: keyword()
  def repo_config(port) when is_integer(port) do
    [
      hostname: "127.0.0.1",
      port: port,
      database: @database,
      username: @username,
      password: @password,
      pool_size: 4,
      stacktrace: true,
      show_sensitive_data_on_connection_error: true
    ]
  end

  @spec migrations_path() :: String.t()
  def migrations_path do
    Application.app_dir(:outer_brain_persistence, "priv/repo/migrations")
  end

  defp host_port!(container_id) do
    {output, 0} =
      System.cmd("docker", ["port", container_id, "5432/tcp"], stderr_to_stdout: true)

    output
    |> String.trim()
    |> String.split(":")
    |> List.last()
    |> String.to_integer()
  end

  defp wait_until_ready!(port, attempts \\ 40)

  defp wait_until_ready!(_port, 0) do
    raise "dockerized Postgres did not become ready in time"
  end

  defp wait_until_ready!(port, attempts) do
    case System.cmd(
           "psql",
           [
             "--host",
             "127.0.0.1",
             "--port",
             Integer.to_string(port),
             "--username",
             @username,
             "--dbname",
             @database,
             "--command",
             "SELECT 1"
           ],
           env: [{"PGPASSWORD", @password}],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      _other ->
        Process.sleep(250)
        wait_until_ready!(port, attempts - 1)
    end
  end
end
