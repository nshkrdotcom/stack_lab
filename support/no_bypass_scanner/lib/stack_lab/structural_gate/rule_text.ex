defmodule StackLab.StructuralGate.RuleText do
  @moduledoc """
  Text token helpers for structural scanner rules.
  """

  def contains_any?(content, tokens), do: Enum.any?(tokens, &String.contains?(content, &1))

  def first_present(content, tokens), do: Enum.find(tokens, &String.contains?(content, &1))

  def token_sort(nil), do: ""
  def token_sort(token), do: to_string(token)

  def line_contains_token?(line_content, token) do
    token = to_string(token)

    if token_has_separator?(token) do
      String.contains?(line_content, token)
    else
      token_at_boundary?(line_content, token)
    end
  end

  defp token_at_boundary?(line_content, token) do
    line_content
    |> token_windows(byte_size(token))
    |> Enum.any?(fn {before_token, candidate, after_token} ->
      candidate == token and token_boundary?(before_token) and token_boundary?(after_token)
    end)
  end

  defp token_has_separator?(token) do
    token
    |> String.to_charlist()
    |> Enum.any?(&(not ascii_alnum?(&1)))
  end

  defp token_windows(line_content, token_size) do
    max_start = byte_size(line_content) - token_size

    if max_start < 0 do
      []
    else
      Enum.map(0..max_start, &token_window(line_content, token_size, &1))
    end
  end

  defp token_window(line_content, token_size, start) do
    {
      byte_before(line_content, start),
      binary_part(line_content, start, token_size),
      byte_at(line_content, start + token_size)
    }
  end

  defp byte_before(_line_content, 0), do: nil
  defp byte_before(line_content, start), do: :binary.at(line_content, start - 1)

  defp byte_at(line_content, index) do
    if index >= byte_size(line_content), do: nil, else: :binary.at(line_content, index)
  end

  defp token_boundary?(nil), do: true
  defp token_boundary?(byte), do: not ascii_alnum?(byte) and byte != ?_

  defp ascii_alnum?(byte), do: byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9
end
