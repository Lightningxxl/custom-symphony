defmodule SymphonyElixir.PlannerSession do
  @moduledoc """
  Long-lived planner Codex session bound to a single tracker item.
  """

  use GenServer

  alias SymphonyElixir.Codex.AppServer

  defstruct [:issue_id, :workspace, :session]

  @type t :: %__MODULE__{
          issue_id: String.t(),
          workspace: Path.t(),
          session: map()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    issue_id = Keyword.fetch!(opts, :issue_id)
    workspace = Keyword.fetch!(opts, :workspace)
    GenServer.start_link(__MODULE__, {issue_id, workspace}, name: name)
  end

  @spec run_turn(GenServer.server(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(server, prompt, issue, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    GenServer.call(server, {:run_turn, prompt, issue, opts}, timeout)
  end

  @impl true
  def init({issue_id, workspace}) do
    case AppServer.start_session(workspace, allow_repo_root: true) do
      {:ok, session} ->
        {:ok, %__MODULE__{issue_id: issue_id, workspace: workspace, session: session}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:run_turn, prompt, issue, opts}, _from, %__MODULE__{session: session} = state) do
    run_opts = Keyword.drop(opts, [:timeout])
    {:reply, AppServer.run_turn(session, prompt, issue, run_opts), state}
  end

  @impl true
  def handle_info({_port, {:data, _payload}}, state) do
    {:noreply, state}
  end

  def handle_info({_port, {:exit_status, _status}}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %__MODULE__{session: session}) do
    AppServer.stop_session(session)
    :ok
  end
end
