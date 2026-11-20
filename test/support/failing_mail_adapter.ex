defmodule LetItBid.FailingMailAdapter do
  @moduledoc """
  A Swoosh adapter for tests that fails every delivery, so tests can cover
  what happens when an email can't be sent.
  """

  use Swoosh.Adapter

  @impl true
  def deliver(_email, _config), do: {:error, :mail_server_unavailable}
end
