defmodule LetItBidWebTest do
  use ExUnit.Case, async: true

  test "static_paths/0 lists the directories served from priv/static" do
    assert "assets" in LetItBidWeb.static_paths()
  end

  # These run at compile time through `use LetItBidWeb, which`; calling them
  # directly checks each one still returns code to inject.
  for which <- [
        :router,
        :channel,
        :controller,
        :live_view,
        :live_component,
        :html,
        :verified_routes
      ] do
    test "#{which}/0 returns quoted code" do
      assert Macro.validate(apply(LetItBidWeb, unquote(which), [])) == :ok
    end
  end
end
