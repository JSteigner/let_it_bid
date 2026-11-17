defmodule LetItBid.Mailer do
  @moduledoc """
  Sends email through the Swoosh adapter configured for the environment.
  """

  use Swoosh.Mailer, otp_app: :let_it_bid
end
