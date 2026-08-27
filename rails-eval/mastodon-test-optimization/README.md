# Mastodon test suite run time optimization

This task evaluates a model's capability in profiling and optimizing a test suite in a large Rails application, Mastodon.

The primary task design considerations:

- We use a fork of the Mastodon codebase with some test optimizations (made by the team in the past) reverted and new performance issues synthesized. There are also some problems still present in the upstream that are known to us. Thus, we have a good mix of planted, historical and novel problems to fix.

- This is a multi-step challenge: three separate instructions (with a shared preamble) on optimizing different parts of the test suite.

- We intentionally limit observed optimizations to two test folders, `spec/models` and `spec/requests`, to reduce the experiment time (running the whole test suite takes more than 10min).

- We use granular grading: measure the overall test speed improvement as well as require particular fixes to be implemented. Intermediate steps require minimal speed improvements and halt otherwise.

## Rationale

A slow test suite is a common problem of many Rails applications (especially those not sticking to the Minitest/Fixtures paradigm). Profiling and optimizing tests is a rather routine task for a human—a perfect fit for an agent.

Here are the arguments in favour of a multistep eval (versus a one-shot):

- The setup repeats the workflow we've executed many times on real projects: split the optimization into steps, ship independently (many small PRs vs. one huge one), individual optimization instrumentation.

- Performing such a task within a single session would require a lot of steps (turns) and a decent amount of context, which could lead to quality degradation.

- We want to evaluate _strategic capabilities_ of a model: how it keeps its log, plans future work, etc. (This, again, mimics human work).

This task also goes beyond the framework itself and covers the Ruby/Rails ecosystem: RSpec, Sidekiq, Faker, factories, etc. We cannot tell if a model works great for Rails without touching the framework's surroundings.

## Grading

The first two steps have binary grading: pass (reached the required speed improvement) or fail. If a model fails, we stop with a zero reward and do not run the subsequent steps.

The final step is the whole task result and graded differently:

- Speed: A model can get up to 0.6 of the reward by reaching the target speed improvement (we use a progressive scale)
- Features: A model can get up to 0.6 of the reward by fixing most of the issues known to us (verified using deterministic tests)

The final reward is calculated as: `MIN(Speed + Features, 1.0)`. Thus, it's not necessary to fix all the known problems to score 1.0. A model can compensate by improving the test suite run time by a larger factor than the minimum required.

There are also hard gates applied after each step:

- The target test groups (models and requests) must stay green.
- The test examples and application code diff must stay small (the actual borderline/LOC TBD).

## Observations

In addition to grades, we can also collect the following observations about each model (using a frontier LLM):

- Task-specific:
  - Did the agent create and maintain the test optimization doc?
  - What are the other bottlenecks identified by a model (not included into our list)? Are they truly impactful?
  - Did the model run fabrication specs (`spec/fabrication`) after modifying factories?
  - Did the model overwork: ignored the step scope (spec/models or spec/requests), tried to run the whole test suite?
  - Mastodon recall: did the model know that this is a Mastodon codebase just looking at the structure? ("This looks like Mastodon")

- General:
  - How often did a model reach out to gem contents for more information? (E.g., `$ cd /app && gem contents test-prof ...`)
  - What is the blast radius of each step run? (The number of files the model wanted to read before introducing changes)
  - Did the model use RuboCop to lint/format updated files?

- Recall:
  - TestProf: usage of profilers and recipes (`FPROF`, `before_all`, `EVENT_PROF` + monitor, etc.); prior knowledge of test-prof ("Let me check if test-prof or other profiling gems are available")
  - Profilers: did the model use Stackprof or other low-level Ruby profiling tools?
  - RSpec: did the model use `RUBYOPT="-rtest-prof"` (or similar) or `rspec -rtest-prof` (better)? Did the model use tags/contexts or edit examples directly (e.g., `Sidekiq::Testing.inline {...}`)?
  - How often does a generated Ruby helper script fail with NoMethodError, NameError, etc.?
