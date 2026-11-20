defmodule LetItBid.ApplicationTest do
  use ExUnit.Case, async: true

  test "config_change/3 passes the change to the endpoint" do
    assert LetItBid.Application.config_change([], [], []) == :ok
  end
end
