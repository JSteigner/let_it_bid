defmodule LetItBidWeb.FormatTest do
  use ExUnit.Case, async: true

  alias LetItBidWeb.Format

  describe "money/1" do
    test "formats cents as dollars with two decimals" do
      assert Format.money(1_250) == "$12.50"
      assert Format.money(100) == "$1.00"
    end

    test "pads amounts under a dollar" do
      assert Format.money(0) == "$0.00"
      assert Format.money(5) == "$0.05"
      assert Format.money(50) == "$0.50"
    end

    test "adds thousands separators" do
      assert Format.money(100_000) == "$1,000.00"
      assert Format.money(123_456_789) == "$1,234,567.89"
    end
  end
end
