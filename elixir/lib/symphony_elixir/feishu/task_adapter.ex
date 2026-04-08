defmodule SymphonyElixir.Feishu.TaskAdapter do
  @moduledoc """
  Feishu Task-backed tracker adapter.
  """

  @behaviour SymphonyElixir.Tracker
  require Logger

  alias SymphonyElixir.Config
  alias SymphonyElixir.Feishu.{TaskClient, TaskDescription}
  alias SymphonyElixir.Tracker.Item

  @current_plan_field "Current Plan"
  @builder_workpad_field "Builder Workpad"
  @auditor_verdict_field "Auditor Verdict"
  @task_kind_field "Task Kind"
  @task_key_field "Task Key"
  @backlog_stage "Backlog"

  @spec fetch_candidate_issues() :: {:ok, [Item.t()]} | {:error, term()}
  def fetch_candidate_issues do
    tasklist_guid = Config.feishu_tasklist_guid()

    with {:ok, guids} <- TaskClient.list_tasklist_task_guids(tasklist_guid),
         {:ok, context} <- tasklist_context(tasklist_guid) do
      guids
      |> Enum.map(&fetch_and_normalize_task(&1, context))
      |> Enum.reduce_while({:ok, []}, fn
        {:ok, issue}, {:ok, acc} -> {:cont, {:ok, [issue | acc]}}
        {:error, reason}, _acc -> {:halt, {:error, reason}}
      end)
      |> case do
        {:ok, issues} -> {:ok, Enum.reverse(issues)}
        other -> other
      end
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Item.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    wanted =
      state_names
      |> Enum.map(&normalize_state/1)
      |> MapSet.new()

    with {:ok, issues} <- fetch_candidate_issues() do
      {:ok,
       Enum.filter(issues, fn %Item{state: state} ->
         MapSet.member?(wanted, normalize_state(state))
       end)}
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Item.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    tasklist_guid = Config.feishu_tasklist_guid()

    with {:ok, context} <- tasklist_context(tasklist_guid) do
      issue_ids
      |> Enum.uniq()
      |> Enum.reduce_while({:ok, []}, fn
        issue_id, {:ok, acc} ->
          case fetch_and_normalize_task(issue_id, context) do
            {:ok, issue} -> {:cont, {:ok, [issue | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end)
      |> case do
        {:ok, issues} -> {:ok, Enum.reverse(issues)}
        other -> other
      end
    end
  end

  @spec fetch_issue_comments(String.t()) :: {:ok, [map()]} | {:error, term()}
  def fetch_issue_comments(issue_id) when is_binary(issue_id) do
    with {:ok, comments} <- TaskClient.list_comments(issue_id) do
      {:ok, normalize_comments(comments)}
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    TaskClient.create_comment(issue_id, body)
  end

  @spec create_comment(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(issue_id, body, _opts) when is_binary(issue_id) and is_binary(body) do
    create_comment(issue_id, body)
  end

  @spec update_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def update_comment(_comment_id, _body), do: {:error, :unsupported}

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name) when is_binary(issue_id) and is_binary(state_name) do
    with {:ok, task} <- TaskClient.get_task(issue_id),
         tasklist_guid <- selected_tasklist_guid(task),
         {:ok, sections} <- TaskClient.list_sections(tasklist_guid),
         {:ok, section_guid} <- section_guid_for_state(sections, state_name),
         :ok <- TaskClient.move_task_to_section(issue_id, tasklist_guid, section_guid) do
      :ok
    else
      nil -> {:error, :missing_feishu_tasklist_guid}
      other -> other
    end
  end

  @spec update_issue_extra(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_extra(issue_id, extra) when is_binary(issue_id) and is_binary(extra) do
    with {:ok, _task} <- TaskClient.patch_task(issue_id, ["extra"], %{"extra" => extra}) do
      :ok
    end
  end

  @doc false
  @spec normalize_task_payload(map(), [map()], map()) :: Item.t()
  def normalize_task_payload(task, comments, context) when is_map(task) and is_list(comments) and is_map(context) do
    description = TaskDescription.parse(Map.get(task, "description"))
    tasklists = Map.get(task, "tasklists", [])
    selected_tasklist = select_tasklist(tasklists)
    section_guid = Map.get(selected_tasklist || %{}, "section_guid")
    extra = Map.get(task, "extra")
    custom_fields = Map.get(task, "custom_fields", [])
    task_key = custom_field_text(custom_fields, @task_key_field)
    identifier = task_identifier(task, task_key)

    %Item{
      id: Map.get(task, "guid"),
      identifier: identifier,
      task_key: task_key,
      title: Map.get(task, "summary"),
      description: description.raw,
      body: description.body,
      state: stage_name(section_guid, context),
      url: Map.get(task, "url"),
      assignee_id: assignee_id(task),
      tasklist_guid: Map.get(selected_tasklist || %{}, "tasklist_guid"),
      task_section_guid: section_guid,
      task_section_guids_by_name: Map.get(context, :section_guids_by_name, %{}),
      task_custom_field_guids: Map.get(context, :custom_field_guids_by_name, %{}),
      task_status: Map.get(task, "status"),
      extra: extra,
      current_plan: custom_field_text(custom_fields, @current_plan_field),
      builder_workpad: custom_field_text(custom_fields, @builder_workpad_field),
      auditor_verdict: custom_field_text(custom_fields, @auditor_verdict_field),
      task_kind: custom_field_single_select(custom_fields, @task_kind_field, Map.get(context, :task_kind_options_by_guid, %{})),
      comments: normalize_comments(comments),
      tracker_payload: task,
      created_at: parse_unix_ms(Map.get(task, "created_at")),
      updated_at: parse_unix_ms(Map.get(task, "updated_at"))
    }
  end

  defp fetch_and_normalize_task(task_guid, context) do
    with {:ok, task} <- TaskClient.get_task(task_guid),
         {:ok, task} <- maybe_sync_task_key(task, context),
         {:ok, comments} <- TaskClient.list_comments(task_guid) do
      {:ok, normalize_task_payload(task, comments, context)}
    end
  end

  defp tasklist_context(tasklist_guid) when is_binary(tasklist_guid) do
    with {:ok, sections} <- TaskClient.list_sections(tasklist_guid),
         {:ok, custom_fields} <- TaskClient.list_custom_fields(tasklist_guid) do
      {:ok,
       %{
         section_names_by_guid: section_names_by_guid(sections),
         section_guids_by_name: section_guids_by_name(sections),
         default_section_guids: default_section_guids(sections),
         custom_field_guids_by_name: custom_field_guids_by_name(custom_fields),
         task_kind_options_by_guid: task_kind_options_by_guid(custom_fields)
       }}
    end
  end

  defp tasklist_context(_tasklist_guid), do: {:error, :missing_feishu_tasklist_guid}

  defp maybe_sync_task_key(task, context) when is_map(task) and is_map(context) do
    custom_fields = Map.get(task, "custom_fields", [])
    current_task_key = custom_field_text(custom_fields, @task_key_field)
    desired_task_key = desired_task_key(task)
    task_guid = Map.get(task, "guid")
    task_key_field_guid = get_in(context, [:custom_field_guids_by_name, @task_key_field])

    cond do
      is_nil(desired_task_key) ->
        {:ok, task}

      current_task_key == desired_task_key ->
        {:ok, task}

      not is_binary(task_guid) or not is_binary(task_key_field_guid) ->
        {:ok, task}

      true ->
        case TaskClient.patch_task(task_guid, ["custom_fields"], %{
               "custom_fields" => [
                 %{"guid" => task_key_field_guid, "text_value" => desired_task_key}
               ]
             }) do
          {:ok, patched_task} ->
            {:ok, patched_task}

          {:error, reason} ->
            Logger.warning("Failed to sync Task Key for task_guid=#{task_guid} desired_task_key=#{desired_task_key}: #{inspect(reason)}")

            {:ok, task}
        end
    end
  end

  defp assignee_id(%{"members" => members}) when is_list(members) do
    members
    |> Enum.find(fn member -> Map.get(member, "role") == "assignee" end)
    |> case do
      %{} = member -> Map.get(member, "id")
      _ -> nil
    end
  end

  defp assignee_id(_task), do: nil

  defp task_identifier(task, task_key) when is_map(task) do
    task_key || Map.get(task, "task_id") || Map.get(task, "guid")
  end

  defp desired_task_key(task) when is_map(task) do
    case {Config.feishu_task_key_prefix(), Map.get(task, "task_id")} do
      {prefix, task_id} when is_binary(prefix) and is_binary(task_id) ->
        prefix = String.trim(prefix)
        task_id = String.trim(task_id)

        cond do
          prefix == "" -> nil
          task_id == "" -> nil
          true -> "#{prefix}/#{task_id}"
        end

      _ ->
        nil
    end
  end

  defp selected_tasklist_guid(task) when is_map(task) do
    task
    |> Map.get("tasklists", [])
    |> select_tasklist()
    |> case do
      %{} = tasklist -> Map.get(tasklist, "tasklist_guid")
      _ -> Config.feishu_tasklist_guid()
    end
  end

  defp select_tasklist(tasklists) when is_list(tasklists) do
    configured_guid = Config.feishu_tasklist_guid()

    Enum.find(tasklists, fn
      %{"tasklist_guid" => ^configured_guid} when is_binary(configured_guid) -> true
      _ -> false
    end) || List.first(tasklists)
  end

  defp section_guid_for_state(sections, state_name) when is_list(sections) and is_binary(state_name) do
    normalized_state = normalize_state(state_name)

    case Enum.find(sections, fn section -> normalize_state(section_name(section)) == normalized_state end) do
      %{"guid" => guid} when is_binary(guid) ->
        {:ok, guid}

      _ ->
        {:error, {:unknown_feishu_task_section, state_name}}
    end
  end

  defp section_name(section) when is_map(section) do
    cond do
      Map.get(section, "is_default") == true -> @backlog_stage
      true -> Map.get(section, "name") || ""
    end
  end

  defp stage_name(section_guid, context) when is_binary(section_guid) and is_map(context) do
    cond do
      MapSet.member?(Map.get(context, :default_section_guids, MapSet.new()), section_guid) ->
        @backlog_stage

      true ->
        context
        |> Map.get(:section_names_by_guid, %{})
        |> Map.get(section_guid)
        |> blank_to_default_stage()
    end
  end

  defp stage_name(_section_guid, _context), do: Config.default_tracker_stage()

  defp custom_field_text(custom_fields, field_name) do
    custom_fields
    |> Enum.find(fn field -> Map.get(field, "name") == field_name end)
    |> case do
      %{} = field -> blank_to_nil(Map.get(field, "text_value"))
      _ -> nil
    end
  end

  defp custom_field_single_select(custom_fields, field_name, options_by_guid) do
    custom_fields
    |> Enum.find(fn field -> Map.get(field, "name") == field_name end)
    |> case do
      %{} = field ->
        field
        |> Map.get("single_select_value")
        |> case do
          value when is_binary(value) -> Map.get(options_by_guid, value)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp task_kind_options_by_guid(custom_fields) when is_list(custom_fields) do
    custom_fields
    |> Enum.find(fn field -> Map.get(field, "name") == @task_kind_field end)
    |> case do
      %{} = field ->
        field
        |> get_in(["single_select_setting", "options"])
        |> List.wrap()
        |> Map.new(fn option -> {Map.get(option, "guid"), Map.get(option, "name")} end)

      _ ->
        %{}
    end
  end

  defp section_names_by_guid(sections) when is_list(sections) do
    Map.new(sections, fn section -> {Map.get(section, "guid"), section_name(section)} end)
  end

  defp section_guids_by_name(sections) when is_list(sections) do
    Map.new(sections, fn section -> {section_name(section), Map.get(section, "guid")} end)
  end

  defp default_section_guids(sections) when is_list(sections) do
    sections
    |> Enum.filter(&(Map.get(&1, "is_default") == true))
    |> Enum.map(&Map.get(&1, "guid"))
    |> MapSet.new()
  end

  defp custom_field_guids_by_name(custom_fields) when is_list(custom_fields) do
    Map.new(custom_fields, fn field -> {Map.get(field, "name"), Map.get(field, "guid")} end)
  end

  defp normalize_comments(comments) when is_list(comments) do
    comments
    |> Enum.map(fn comment ->
      %{
        id: Map.get(comment, "id"),
        content: Map.get(comment, "content"),
        resource_id: Map.get(comment, "resource_id"),
        resource_type: Map.get(comment, "resource_type"),
        creator_id: get_in(comment, ["creator", "id"]),
        created_at: Map.get(comment, "created_at"),
        updated_at: Map.get(comment, "updated_at")
      }
    end)
    |> Enum.sort_by(fn comment -> {comment.created_at || "", comment.id || ""} end)
  end

  defp parse_unix_ms(value) when is_binary(value) do
    case Integer.parse(value) do
      {milliseconds, ""} ->
        DateTime.from_unix!(milliseconds, :millisecond)

      _ ->
        nil
    end
  rescue
    _error -> nil
  end

  defp parse_unix_ms(_value), do: nil

  defp normalize_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_state(_state_name), do: ""

  defp blank_to_default_stage(nil), do: Config.default_tracker_stage()

  defp blank_to_default_stage(value) when is_binary(value) do
    case String.trim(value) do
      "" -> Config.default_tracker_stage()
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
