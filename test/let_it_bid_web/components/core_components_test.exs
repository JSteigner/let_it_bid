defmodule LetItBidWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import LetItBidWeb.CoreComponents
  import Phoenix.Component
  import Phoenix.LiveViewTest

  describe "button/1" do
    test "renders a link when given navigate" do
      assigns = %{}
      html = rendered_to_string(~H|<.button navigate="/auctions">Browse</.button>|)

      assert [link] = find(html, ~s|a.btn[href="/auctions"]|)
      assert LazyHTML.text(link) =~ "Browse"
    end
  end

  describe "input/1" do
    test "renders a hidden input" do
      assigns = %{}
      html = rendered_to_string(~H|<.input type="hidden" id="t" name="token" value="abc" />|)

      assert [_] = find(html, ~s|input[type="hidden"][name="token"][value="abc"]|)
    end

    test "renders a checked checkbox with a false fallback and errors" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.input
          type="checkbox"
          id="agree"
          name="agree"
          label="I agree"
          value="true"
          errors={["must be accepted"]}
        />
        """)

      assert [_] = find(html, ~s|input[type="hidden"][name="agree"][value="false"]|)
      assert [_] = find(html, ~s|input[type="checkbox"][name="agree"][checked]|)
      assert error_text(html) =~ "must be accepted"
    end

    test "renders a select with a prompt and the current value selected" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.input
          type="select"
          id="sort"
          name="sort"
          label="Sort"
          prompt="Pick one"
          options={[{"Ending soon", "ending"}, {"Newest", "newest"}]}
          value="newest"
          errors={["is invalid"]}
        />
        """)

      assert [_] = find(html, ~s|select.select-error[name="sort"]|)
      assert [_] = find(html, ~s|option[value=""]|)
      assert [_] = find(html, ~s|option[value="newest"][selected]|)
      assert error_text(html) =~ "is invalid"
    end

    test "renders a textarea with its value and error class" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.input
          type="textarea"
          id="desc"
          name="description"
          label="Description"
          value="Vintage watch"
          errors={["is too long"]}
        />
        """)

      assert [textarea] = find(html, ~s|textarea.textarea-error[name="description"]|)
      assert LazyHTML.text(textarea) =~ "Vintage watch"
      assert error_text(html) =~ "is too long"
    end
  end

  describe "table/1" do
    test "renders rows from a list, with clickable rows and actions" do
      assigns = %{rows: [%{id: 1, title: "Watch"}, %{id: 2, title: "Lamp"}]}

      html =
        rendered_to_string(~H"""
        <.table id="auctions" rows={@rows} row_id={&"auction-#{&1.id}"} row_click={fn _ -> "open" end}>
          <:col :let={row} label="Title">{row.title}</:col>
          <:action :let={row}><span class="bid">Bid on {row.title}</span></:action>
        </.table>
        """)

      assert [_] = find(html, "th", "Title")
      assert [_] = find(html, "tr#auction-1 td.hover\\:cursor-pointer", "Watch")
      assert [_, _] = find(html, "span.bid")
    end

    # Streamed rows are covered by the auction list LiveView tests: a stream
    # can only be built on a real LiveView socket.
  end

  describe "list/1" do
    test "renders each item's title and content" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.list>
          <:item title="Starting price">$10.00</:item>
          <:item title="Ends">in 5 minutes</:item>
        </.list>
        """)

      assert [_, _] = find(html, "li.list-row")
      assert [_] = find(html, "li.list-row", "Starting price")
    end
  end

  describe "translate_errors/2" do
    test "returns only the given field's errors, translated" do
      errors = [
        title: {"can't be blank", []},
        title: {"should be at most %{count} character(s)", [count: 80]},
        description: {"is invalid", []}
      ]

      assert translate_errors(errors, :title) == [
               "can't be blank",
               "should be at most 80 character(s)"
             ]
    end
  end

  defp find(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.to_list()
  end

  defp find(html, selector, text) do
    html
    |> find(selector)
    |> Enum.filter(&(LazyHTML.text(&1) =~ text))
  end

  defp error_text(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("p.text-error")
    |> LazyHTML.text()
  end
end
