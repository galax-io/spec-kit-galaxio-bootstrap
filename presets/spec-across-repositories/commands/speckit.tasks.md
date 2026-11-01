## Before you tasks: how coarse are the tasks?

In an engine run one call of `speckit-implement` does a whole user story, test first for each task it names, and the
engine commits. So the tasks you write are the units of that work, not its steps. Read the rules below first: they
change what the base command says of the phases, of the tests and of the size of a task.

{CORE_TEMPLATE}

## After you tasks: coarse tasks, no commit tasks

- **A story's work is a few coarse tasks.** Do not split a user story finely. One task is a piece of the story that
  can be judged on its own, in one repository (`[repo:<name>]`): a story of one repository is usually one to three
  tasks, not one per file or per function.
- **No task that only commits.** Never write a task to commit, push, tag, open a pull request or merge: the engine
  commits, and the maintainer opens and merges.
- **No separate «tests first» and «implementation» tasks for the same change.** A task is test first inside itself: its
  description says what behaviour it tests and what it implements, and whoever does it writes the failing test, then
  the code. This replaces what the base command says of test tasks before implementation tasks. Keep a task of its
  own only for a test that covers no change of this story (a contract or an integration check of its own).
- **Keep the rest of the format**: the checkbox, the task id, `[P]`, the story label, `[repo:<name>]`, the tier and the
  tasks line under the title, and the phases.
