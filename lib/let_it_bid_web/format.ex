defmodule LetItBidWeb.Format do
  @moduledoc """
  Display formatting for values stored in their exact form, like money in
  integer cents.
  """

  @doc """
  Formats integer cents as dollars, with thousands separators.
  """
  @spec money(non_neg_integer()) :: String.t()
  def money(cents) when is_integer(cents) and cents >= 0 do
    dollars =
      cents
      |> div(100)
      |> Integer.to_string()
      |> group_thousands()

    remainder =
      cents
      |> rem(100)
      |> Integer.to_string()
      |> String.pad_leading(2, "0")

    "$#{dollars}.#{remainder}"
  end

  defp group_thousands(digits) do
    digits
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
