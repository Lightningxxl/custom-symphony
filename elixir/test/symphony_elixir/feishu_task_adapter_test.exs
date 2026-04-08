defmodule SymphonyElixir.FeishuTaskAdapterTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Feishu.TaskAdapter

  test "normalize_task_payload reads stage from section and canonical fields from task custom fields" do
    task = %{
      "guid" => "task-1",
      "task_id" => "t100001",
      "summary" => "Align Symphony to Feishu task fields",
      "description" => "The task description is the human-authored body.",
      "status" => "todo",
      "url" => "https://example.test/task-1",
      "extra" => "{\"schema_version\":1,\"meta\":{}}",
      "tasklists" => [
        %{
          "tasklist_guid" => "tasklist-1",
          "section_guid" => "default-section"
        }
      ],
      "custom_fields" => [
        %{"name" => "Current Plan", "type" => "text", "text_value" => "### Current Plan\nUse task comments for discussion."},
        %{"name" => "Builder Workpad", "type" => "text", "text_value" => "`host:path@sha`\n\n### Plan\n- [ ] Implement"},
        %{"name" => "Auditor Verdict", "type" => "text", "text_value" => "### Verdict\nPending"},
        %{"name" => "Task Kind", "type" => "single_select", "single_select_value" => "opt-improvement"}
      ]
    }

    comments = [
      %{"id" => "c1", "content" => "Human: comments should drive planner replanning.", "created_at" => "1", "updated_at" => "1"}
    ]

    context = %{
      section_names_by_guid: %{"default-section" => "Backlog"},
      section_guids_by_name: %{"Backlog" => "default-section"},
      default_section_guids: MapSet.new(["default-section"]),
      custom_field_guids_by_name: %{
        "Current Plan" => "field-plan",
        "Builder Workpad" => "field-workpad",
        "Auditor Verdict" => "field-audit",
        "Task Kind" => "field-kind"
      },
      task_kind_options_by_guid: %{"opt-improvement" => "improvement"}
    }

    issue = TaskAdapter.normalize_task_payload(task, comments, context)

    assert issue.state == "Backlog"
    assert issue.body == "The task description is the human-authored body."
    assert issue.current_plan =~ "Current Plan"
    assert issue.builder_workpad =~ "### Plan"
    assert issue.auditor_verdict =~ "### Verdict"
    assert issue.task_kind == "improvement"
    assert issue.task_custom_field_guids["Current Plan"] == "field-plan"
    assert issue.task_section_guids_by_name["Backlog"] == "default-section"
    assert Enum.map(issue.comments, & &1.id) == ["c1"]
  end

  test "normalize_task_payload uses named non-default sections directly" do
    task = %{
      "guid" => "task-2",
      "summary" => "Review implementation",
      "description" => "Review body",
      "tasklists" => [
        %{
          "tasklist_guid" => "tasklist-1",
          "section_guid" => "in-review-section"
        }
      ],
      "custom_fields" => []
    }

    context = %{
      section_names_by_guid: %{"in-review-section" => "In Review"},
      section_guids_by_name: %{"In Review" => "in-review-section"},
      default_section_guids: MapSet.new(),
      custom_field_guids_by_name: %{},
      task_kind_options_by_guid: %{}
    }

    issue = TaskAdapter.normalize_task_payload(task, [], context)

    assert issue.state == "In Review"
  end
end
