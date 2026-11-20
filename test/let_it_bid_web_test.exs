defmodule LetItBidWebTest do
  use ExUnit.Case, async: true

  test "static_paths/0 lists the directories served from priv/static" do
    assert "assets" in LetItBidWeb.static_paths()
  end
end
