defmodule SymphonyElixir.PlannerRunner do
  @moduledoc """
  Single-turn planner lane that reuses a persistent per-issue Codex session.
  """

  require Logger

  alias SymphonyElixir.{Feishu.TaskState, PlannerSessions, PromptBuilder}

  @spec run(map(), pid() | nil, keyword()) :: :ok | no_return()
  def run(%{id: issue_id} = issue, codex_update_recipient \\ nil, opts \\ []) when is_binary(issue_id) do
    mode = planner_mode(issue.state, issue.current_plan)

    prompt =
      PromptBuilder.build_planner_prompt(
        issue,
        attempt: Keyword.get(opts, :attempt),
        max_turns: 1,
        mode: mode,
        turn_number: 1,
        turn_phase: "single_turn",
        ticket:
          issue
          |> TaskState.prompt_context()
          |> Map.put(:mode, mode)
          |> Map.put(:turn_phase, "single_turn")
          |> Map.put(:turn_number, 1)
          |> Map.put(:max_turns, 1)
          |> maybe_put_attempt(Keyword.get(opts, :attempt))
      )

    case PlannerSessions.run_turn(
           issue,
           prompt,
           on_message: codex_message_handler(codex_update_recipient, issue)
         ) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Logger.error("Planner run failed issue_id=#{issue.id} issue_identifier=#{issue.identifier}: #{inspect(reason)}")
        raise RuntimeError, "Planner run failed issue_id=#{issue.id} issue_identifier=#{issue.identifier}: #{inspect(reason)}"
    end
  end

  defp planner_mode(state_name, current_plan) when is_binary(state_name) do
    case String.downcase(String.trim(state_name)) do
      "in review" -> "review"
      _ -> if blank?(current_plan), do: "planning", else: "replanning"
    end
  end

  defp planner_mode(_state_name, current_plan), do: if(blank?(current_plan), do: "planning", else: "replanning")

  defp maybe_put_attempt(ticket, attempt) when is_integer(attempt), do: Map.put(ticket, :attempt, attempt)
  defp maybe_put_attempt(ticket, _attempt), do: ticket

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false

  defp codex_message_handler(recipient, %{id: issue_id}) when is_pid(recipient) and is_binary(issue_id) do
    fn message ->
      send(recipient, {:codex_worker_update, issue_id, message})
      :ok
    end
  end

  defp codex_message_handler(_recipient, _issue), do: fn _message -> :ok end
end
