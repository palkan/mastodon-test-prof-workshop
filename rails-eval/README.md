# Designing evals

This branch contains the following changes compared to the upstream:

- **Docker/Dip setup** enough to run tests (run `dip provision`, then `dip rspec` — all should work)
- A few commits **spoiling** tests performance a bit. Most of the changes are reversions of the optimizations the Mastodon team shipped over the years.

This branch acts as a starting point for agents working on the test optimization task(s).

## Task format

This is not the final lemans task format, it's a proposal:

- `instruction.md` is a proposed format for multistep tasks (with the `---` delimiter)
- `instruction.N.md` is the stripped instruction for each step with a shared preamble (for miniswen usage)
- `verification-plan.md` is the verification plan in prose (to be encoded as `verification_test.rb` or similar)
- `runs.md` manual runs results and insights obtained so far.

## How to use it with miniswen

Before adding a task to a lemans bench suite, we recommend manually verifying it using miniswen:

- Create a new branch (say, `run/<agent-name>-<task>`)
- Run a Rails Docker container with no outside network access: `dip runner:isolated`. Obtain its ID and make it available to the env:

```sh
export DOCKER=$(docker ps | grep mastodon-workshop-rails-isolated-run | awk '{ printf $1 }')
```

- Run miniswen attached to this container (so the agent could only run commands within a sandbox):

```sh
miniswen -p ./rails-eval/mastodon-test-optimization/instruction.1.md --docker $DOCKER --exec-timeout=300 --results-path ./rails-eval/runs/gpt-5.6-luna/mastodon-test-optimization/results.1.json --atif-path ./rails-eval/gpt-5.6-luna/mastodon-test-optimization/trajectory.1.json
```

Repeat for every task (or step in the task), analyze the results, tune your prompt, repeat for a few agents, and so on.

## Instruction tuning

Models can overoptimize during the first step and identify all the bottlenecks right away. We should either:

- Restrain them: for example, explicitly prohibited modifying factories before the dedicated step (add a verify step to halt the execution if factories were touched)
- Instruct them to skip this step with "aleady completed". In this case, the shared prompt must be explicit about keeping the plan/intermediate results in a document as well as capturing all the baseline metrics during the first step
