defmodule SymphonyElixir.CanonicalRepoTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.CanonicalRepo

  test "returns up_to_date when clean main already matches origin/main" do
    runner = fake_runner(%{
      ["rev-parse", "--is-inside-work-tree"] => {"true\n", 0},
      ["rev-parse", "--abbrev-ref", "HEAD"] => {"main\n", 0},
      ["status", "--short"] => {"", 0},
      ["fetch", "origin", "main", "--quiet"] => {"", 0},
      ["rev-list", "--left-right", "--count", "origin/main...HEAD"] => {"0\t0\n", 0}
    })

    assert {:ok, :up_to_date} = CanonicalRepo.ensure_ready("/tmp/repo", runner: runner)
  end

  test "fast-forwards when local main is safely behind origin/main" do
    runner = fake_runner(%{
      ["rev-parse", "--is-inside-work-tree"] => {"true\n", 0},
      ["rev-parse", "--abbrev-ref", "HEAD"] => {"main\n", 0},
      ["status", "--short"] => {"", 0},
      ["fetch", "origin", "main", "--quiet"] => {"", 0},
      ["rev-list", "--left-right", "--count", "origin/main...HEAD"] => {"2\t0\n", 0},
      ["pull", "--ff-only", "origin", "main"] => {"Updating abc..def\n", 0}
    })

    assert {:ok, :pulled} = CanonicalRepo.ensure_ready("/tmp/repo", runner: runner)
  end

  test "fails when repo is not on main" do
    runner = fake_runner(%{
      ["rev-parse", "--is-inside-work-tree"] => {"true\n", 0},
      ["rev-parse", "--abbrev-ref", "HEAD"] => {"feature/harness\n", 0}
    })

    assert {:error, message} = CanonicalRepo.ensure_ready("/tmp/repo", runner: runner)
    assert message =~ "must be on main"
    assert message =~ "feature/harness"
  end

  test "fails when repo has local changes" do
    runner = fake_runner(%{
      ["rev-parse", "--is-inside-work-tree"] => {"true\n", 0},
      ["rev-parse", "--abbrev-ref", "HEAD"] => {"main\n", 0},
      ["status", "--short"] => {" M PLANNER.md\n", 0}
    })

    assert {:error, message} = CanonicalRepo.ensure_ready("/tmp/repo", runner: runner)
    assert message =~ "has uncommitted changes"
    assert message =~ "PLANNER.md"
  end

  test "fails when repo is ahead of origin/main" do
    runner = fake_runner(%{
      ["rev-parse", "--is-inside-work-tree"] => {"true\n", 0},
      ["rev-parse", "--abbrev-ref", "HEAD"] => {"main\n", 0},
      ["status", "--short"] => {"", 0},
      ["fetch", "origin", "main", "--quiet"] => {"", 0},
      ["rev-list", "--left-right", "--count", "origin/main...HEAD"] => {"0\t3\n", 0}
    })

    assert {:error, message} = CanonicalRepo.ensure_ready("/tmp/repo", runner: runner)
    assert message =~ "is ahead of origin/main"
  end

  test "fails when repo has diverged from origin/main" do
    runner = fake_runner(%{
      ["rev-parse", "--is-inside-work-tree"] => {"true\n", 0},
      ["rev-parse", "--abbrev-ref", "HEAD"] => {"main\n", 0},
      ["status", "--short"] => {"", 0},
      ["fetch", "origin", "main", "--quiet"] => {"", 0},
      ["rev-list", "--left-right", "--count", "origin/main...HEAD"] => {"1\t2\n", 0}
    })

    assert {:error, message} = CanonicalRepo.ensure_ready("/tmp/repo", runner: runner)
    assert message =~ "has diverged from origin/main"
  end

  defp fake_runner(responses) do
    fn _repo_root, args ->
      Map.fetch!(responses, args)
    end
  end
end
