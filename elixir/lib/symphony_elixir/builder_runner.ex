defmodule SymphonyElixir.BuilderRunner do
  @moduledoc """
  Builder lane wrapper around the multi-turn AgentRunner.
  """

  alias SymphonyElixir.{AgentRunner, Feishu.TaskState}

  @spec run(map(), pid() | nil, keyword()) :: :ok | no_return()
  def run(%{id: issue_id} = issue, codex_update_recipient \\ nil, opts \\ []) when is_binary(issue_id) do
    opts =
      opts
      |> Keyword.put(:mode, builder_mode(issue))
      |> Keyword.put(:ticket, TaskState.prompt_context(issue))

    AgentRunner.run(issue, codex_update_recipient, opts)
  end

  defp builder_mode(%{state: state_name} = issue) when is_binary(state_name) do
    case String.downcase(String.trim(state_name)) do
      "todo" -> "pickup"
      "merging" -> "merge"
      "in progress" -> if(TaskState.builder_rework_requested?(issue), do: "rework", else: "execute")
      _ -> "execute"
    end
  end

  defp builder_mode(_issue), do: "execute"
end
