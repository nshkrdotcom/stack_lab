defmodule StackLab.GnTenNodeLab.Cookie do
  @moduledoc """
  Redacted local Erlang cookie helpers for node-lab runs.
  """

  @spec generate() :: String.t()
  def generate do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @spec validate(String.t()) :: :ok | {:error, map()}
  def validate(cookie) when is_binary(cookie) do
    valid? =
      byte_size(cookie) in 24..128 and
        cookie
        |> :binary.bin_to_list()
        |> Enum.all?(&safe_cookie_byte?/1)

    if valid?, do: :ok, else: {:error, failure("invalid_cookie")}
  end

  def validate(_cookie), do: {:error, failure("invalid_cookie")}

  @spec posture(String.t()) :: map()
  def posture(cookie) when is_binary(cookie) do
    case validate(cookie) do
      :ok ->
        %{
          "posture" => "generated_redacted",
          "byte_size" => byte_size(cookie),
          "secret_value_present?" => false,
          "distribution_security_claim" => "local_dev_only",
          "production_security_proven?" => false
        }

      {:error, failure} ->
        raise ArgumentError, inspect(failure)
    end
  end

  defp safe_cookie_byte?(byte)
       when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in [?_, ?-],
       do: true

  defp safe_cookie_byte?(_byte), do: false

  defp failure(code), do: %{code: code, message: "cookie must be 24..128 safe printable bytes"}
end
