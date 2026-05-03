defmodule StackLab.GnTen.TextRules do
  @moduledoc false

  def safe_slug?(slug) when is_binary(slug) and byte_size(slug) > 0 do
    [first | rest] = :binary.bin_to_list(slug)

    (lower_ascii?(first) or digit?(first)) and Enum.all?(rest, &slug_tail?/1)
  end

  def safe_slug?(_slug), do: false

  def lower_hex?(value, size) when is_binary(value) and byte_size(value) == size do
    value
    |> :binary.bin_to_list()
    |> Enum.all?(fn byte -> digit?(byte) or byte in ?a..?f end)
  end

  def lower_hex?(_value, _size), do: false

  def line_item?(line, key) do
    line
    |> String.trim_leading()
    |> String.starts_with?("- #{key}:")
  end

  def scalar(content, key) do
    content
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      line
      |> String.trim_leading()
      |> scalar_from_line(key)
    end)
  end

  def list_blocks(content, key) do
    content
    |> String.split("\n")
    |> Enum.reduce([], fn line, blocks ->
      cond do
        line_item?(line, key) ->
          [[line] | blocks]

        blocks == [] ->
          blocks

        true ->
          [current | rest] = blocks
          [[line | current] | rest]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(&Enum.reverse/1)
    |> Enum.map(&Enum.join(&1, "\n"))
  end

  def block_scalar(block, key) do
    block
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      trimmed = String.trim_leading(line)

      if String.starts_with?(trimmed, "- #{key}:") do
        trimmed
        |> String.replace_prefix("-", "")
        |> String.trim_leading()
        |> scalar_from_line(key)
      else
        scalar_from_line(trimmed, key)
      end
    end)
  end

  def block_list(block, key) do
    lines = String.split(block, "\n")

    case Enum.find_index(lines, fn line ->
           line |> String.trim_leading() |> String.starts_with?("#{key}:")
         end) do
      nil ->
        []

      index ->
        lines
        |> Enum.drop(index + 1)
        |> Enum.take_while(fn line ->
          trimmed = String.trim_leading(line)
          String.starts_with?(trimmed, "- ")
        end)
        |> Enum.map(fn line ->
          line
          |> String.trim()
          |> String.replace_prefix("- ", "")
          |> normalize_scalar()
        end)
        |> Enum.reject(&empty?/1)
    end
  end

  def list_items_after(content, key) do
    lines = String.split(content, "\n")

    case Enum.find_index(lines, fn line -> String.trim(line) == "#{key}:" end) do
      nil ->
        []

      index ->
        lines
        |> Enum.drop(index + 1)
        |> Enum.take_while(fn line ->
          trimmed = String.trim_leading(line)
          String.starts_with?(trimmed, "- ")
        end)
        |> Enum.map(fn line ->
          line
          |> String.trim()
          |> String.replace_prefix("- ", "")
          |> normalize_scalar()
        end)
        |> Enum.reject(&empty?/1)
    end
  end

  def normalize_scalar(nil), do: nil

  def normalize_scalar(value) do
    value
    |> String.trim()
    |> normalize_trimmed_scalar()
  end

  defp normalize_trimmed_scalar(""), do: nil
  defp normalize_trimmed_scalar("null"), do: nil

  defp normalize_trimmed_scalar(value) do
    value
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  def empty?(nil), do: true
  def empty?(""), do: true
  def empty?(_value), do: false

  defp scalar_from_line(line, key) do
    prefix = "#{key}:"

    if String.starts_with?(line, prefix) do
      line
      |> String.replace_prefix(prefix, "")
      |> normalize_scalar()
    end
  end

  defp slug_tail?(byte), do: lower_ascii?(byte) or digit?(byte) or byte == ?-
  defp lower_ascii?(byte), do: byte in ?a..?z
  defp digit?(byte), do: byte in ?0..?9
end
