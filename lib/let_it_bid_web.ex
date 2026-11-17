defmodule LetItBidWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use LetItBidWeb, :controller
      use LetItBidWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  @doc "Paths under `priv/static` served as static files and allowed in `~p`."
  @spec static_paths() :: [String.t()]
  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  @doc "Code injected by `use LetItBidWeb, :router`."
  @spec router() :: Macro.t()
  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  @doc "Code injected by `use LetItBidWeb, :channel`."
  @spec channel() :: Macro.t()
  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  @doc "Code injected by `use LetItBidWeb, :controller`."
  @spec controller() :: Macro.t()
  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: LetItBidWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  @doc "Code injected by `use LetItBidWeb, :live_view`."
  @spec live_view() :: Macro.t()
  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  @doc "Code injected by `use LetItBidWeb, :live_component`."
  @spec live_component() :: Macro.t()
  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  @doc "Code injected by `use LetItBidWeb, :html` (function components and HTML modules)."
  @spec html() :: Macro.t()
  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  @doc "Code injected by `use LetItBidWeb, :verified_routes`; enables the `~p` sigil."
  @spec verified_routes() :: Macro.t()
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: LetItBidWeb.Endpoint,
        router: LetItBidWeb.Router,
        statics: LetItBidWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end

  defp html_helpers do
    quote do
      # Translation
      use Gettext, backend: LetItBidWeb.Gettext

      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import LetItBidWeb.CoreComponents

      # Common modules used in templates
      alias Phoenix.LiveView.JS

      alias LetItBidWeb.Layouts

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end
end
