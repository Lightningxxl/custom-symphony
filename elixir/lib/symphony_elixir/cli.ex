defmodule SymphonyElixir.CLI do
  @moduledoc """
  Escript entrypoint for running Symphony against a repository root.
  """

  alias SymphonyElixir.LogFile

  @acknowledgement_switch :i_understand_that_this_will_be_running_without_the_usual_guardrails
  @switches [{@acknowledgement_switch, :boolean}, logs_root: :string, port: :integer]

  @type ensure_started_result :: {:ok, [atom()]} | {:error, term()}
  @type deps :: %{
          dir?: (String.t() -> boolean()),
          file_regular?: (String.t() -> boolean()),
          set_repo_root: (String.t() -> :ok | {:error, term()}),
          set_workflow_file_path: (String.t() -> :ok | {:error, term()}),
          set_logs_root: (String.t() -> :ok | {:error, term()}),
          set_server_port_override: (non_neg_integer() | nil -> :ok | {:error, term()}),
          ensure_all_started: (-> ensure_started_result())
        }

  @spec main([String.t()]) :: no_return()
  def main(args) do
    case evaluate(args) do
      :ok ->
        wait_for_shutdown()

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  @spec evaluate([String.t()], deps()) :: :ok | {:error, String.t()}
  def evaluate(args, deps \\ runtime_deps()) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [], []} ->
        with :ok <- require_guardrails_acknowledgement(opts),
             :ok <- maybe_set_logs_root(opts, deps),
             :ok <- maybe_set_server_port(opts, deps) do
          run(File.cwd!(), deps)
        end

      {opts, [target_path], []} ->
        with :ok <- require_guardrails_acknowledgement(opts),
             :ok <- maybe_set_logs_root(opts, deps),
             :ok <- maybe_set_server_port(opts, deps) do
          run(target_path, deps)
        end

      _ ->
        {:error, usage_message()}
    end
  end

  @spec run(String.t(), deps()) :: :ok | {:error, String.t()}
  def run(target_path, deps) do
    expanded_path = Path.expand(target_path)

    cond do
      deps.dir?.(expanded_path) ->
        config_path = Path.join(expanded_path, "SYMPHONY.yml")
        builder_path = Path.join(expanded_path, "BUILDER.md")
        planner_path = Path.join(expanded_path, "PLANNER.md")
        auditor_path = Path.join(expanded_path, "AUDITOR.md")

        cond do
          !deps.file_regular?.(config_path) ->
            {:error, "Config file not found: #{config_path}"}

          !deps.file_regular?.(builder_path) ->
            {:error, "Builder file not found: #{builder_path}"}

          !deps.file_regular?.(planner_path) ->
            {:error, "Planner file not found: #{planner_path}"}

          !deps.file_regular?.(auditor_path) ->
            {:error, "Auditor file not found: #{auditor_path}"}

          true ->
            :ok = deps.set_repo_root.(expanded_path)
            ensure_started(expanded_path, deps)
        end

      deps.file_regular?.(expanded_path) ->
        config_path = Path.join(Path.dirname(expanded_path), "SYMPHONY.yml")
        planner_path = Path.join(Path.dirname(expanded_path), "PLANNER.md")
        auditor_path = Path.join(Path.dirname(expanded_path), "AUDITOR.md")

        if deps.file_regular?.(config_path) do
          if deps.file_regular?.(planner_path) do
            if deps.file_regular?.(auditor_path) do
              :ok = deps.set_workflow_file_path.(expanded_path)
              ensure_started(expanded_path, deps)
            else
              {:error, "Auditor file not found: #{auditor_path}"}
            end
          else
            {:error, "Planner file not found: #{planner_path}"}
          end
        else
          {:error, "Config file not found: #{config_path}"}
        end

      true ->
        {:error, "Repository or builder file not found: #{expanded_path}"}
    end
  end

  @spec usage_message() :: String.t()
  defp usage_message do
    "Usage: symphony [--logs-root <path>] [--port <port>] [repo-dir-or-path-to-BUILDER.md]"
  end

  @spec runtime_deps() :: deps()
  defp runtime_deps do
    %{
      dir?: &File.dir?/1,
      file_regular?: &File.regular?/1,
      set_repo_root: &SymphonyElixir.Workflow.set_repo_root/1,
      set_workflow_file_path: &SymphonyElixir.Workflow.set_workflow_file_path/1,
      set_logs_root: &set_logs_root/1,
      set_server_port_override: &set_server_port_override/1,
      ensure_all_started: fn -> Application.ensure_all_started(:symphony_elixir) end
    }
  end

  defp ensure_started(target, deps) do
    case deps.ensure_all_started.() do
      {:ok, _started_apps} ->
        :ok

      {:error, reason} ->
        {:error, "Failed to start Symphony with target #{target}: #{inspect(reason)}"}
    end
  end

  defp maybe_set_logs_root(opts, deps) do
    case Keyword.get_values(opts, :logs_root) do
      [] ->
        :ok

      values ->
        logs_root = values |> List.last() |> String.trim()

        if logs_root == "" do
          {:error, usage_message()}
        else
          :ok = deps.set_logs_root.(Path.expand(logs_root))
        end
    end
  end

  defp require_guardrails_acknowledgement(opts) do
    if Keyword.get(opts, @acknowledgement_switch, false) do
      :ok
    else
      {:error, acknowledgement_banner()}
    end
  end

  @spec acknowledgement_banner() :: String.t()
  defp acknowledgement_banner do
    lines = [
      "This Symphony implementation is a low key engineering preview.",
      "Codex will run without any guardrails.",
      "SymphonyElixir is not a supported product and is presented as-is.",
      "To proceed, start with `--i-understand-that-this-will-be-running-without-the-usual-guardrails` CLI argument"
    ]

    width = Enum.max(Enum.map(lines, &String.length/1))
    border = String.duplicate("─", width + 2)
    top = "╭" <> border <> "╮"
    bottom = "╰" <> border <> "╯"
    spacer = "│ " <> String.duplicate(" ", width) <> " │"

    content =
      [
        top,
        spacer
        | Enum.map(lines, fn line ->
            "│ " <> String.pad_trailing(line, width) <> " │"
          end)
      ] ++ [spacer, bottom]

    [
      IO.ANSI.red(),
      IO.ANSI.bright(),
      Enum.join(content, "\n"),
      IO.ANSI.reset()
    ]
    |> IO.iodata_to_binary()
  end

  defp set_logs_root(logs_root) do
    Application.put_env(:symphony_elixir, :log_file, LogFile.default_log_file(logs_root))
    :ok
  end

  defp maybe_set_server_port(opts, deps) do
    case Keyword.get_values(opts, :port) do
      [] ->
        :ok

      values ->
        port = List.last(values)

        if is_integer(port) and port >= 0 do
          :ok = deps.set_server_port_override.(port)
        else
          {:error, usage_message()}
        end
    end
  end

  defp set_server_port_override(port) when is_integer(port) and port >= 0 do
    Application.put_env(:symphony_elixir, :server_port_override, port)
    :ok
  end

  @spec wait_for_shutdown() :: no_return()
  defp wait_for_shutdown do
    case Process.whereis(SymphonyElixir.Supervisor) do
      nil ->
        IO.puts(:stderr, "Symphony supervisor is not running")
        System.halt(1)

      pid ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} ->
            case reason do
              :normal -> System.halt(0)
              _ -> System.halt(1)
            end
        end
    end
  end
end
