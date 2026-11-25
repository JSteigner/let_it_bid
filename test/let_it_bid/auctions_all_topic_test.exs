defmodule LetItBid.AuctionsAllTopicTest do
  # Not async: broadcasting on the shared all-auctions topic reaches every
  # subscriber, including home page LiveViews mounted by async tests.
  use LetItBid.DataCase, async: false

  alias LetItBid.Auctions

  describe "broadcast/2" do
    test "reaches subscribers of every auction" do
      :ok = Auctions.subscribe_all()
      :ok = Auctions.broadcast(42, :hello)

      assert_receive :hello
    end
  end
end
