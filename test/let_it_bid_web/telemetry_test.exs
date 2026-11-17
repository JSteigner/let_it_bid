defmodule LetItBidWeb.TelemetryTest do
  use ExUnit.Case, async: true

  alias LetItBidWeb.Telemetry

  test "metrics/0 lists the metrics for LiveDashboard" do
    metrics = Telemetry.metrics()

    assert [_ | _] = metrics
    assert Enum.any?(metrics, &(&1.name == [:phoenix, :endpoint, :stop, :duration]))
  end
end
