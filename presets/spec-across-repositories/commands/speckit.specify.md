## Before you specify: which repositories does the feature affect?

A feature of this organization usually touches several repositories, and this specification is the one
document for all of them. Do steps 0 to 3 first, in this session, with no other agent for any repository.

0. **The task's spec, if there is one.** The task number is `BCKLG-<N>`, where `<N>` is the number of the
   feature's issue in `galax-io/galaxio-sdlc-backlog`: the one number of the task in the organization. Ask
   for the issue number if you do not have it; never invent one. A spec carries its tasks on the line
   `**Задачи**: BCKLG-<N>[, BCKLG-<M>…]` under its title. Look for the spec.md under `specs/` whose line
   names `BCKLG-<N>`; a spec.md without the line counts as the spec of the task its directory is named by
   (`specs/<N>-…` or `specs/BCKLG-<N>-…`). Two such specs: stop and say which; the task may have one.
   One: do not write another. Check it against the task as its issue says now and against the form below;
   if it covers the task and its form holds, change nothing and say why it matches; if not, update it in
   its directory, keep what it says for its other tasks, and use that directory in every step below.
1. **The directory.** A new spec's directory is `specs/BCKLG-<N>-<short name>` in this repository, so that
   the spec is named by the task number and by nothing else. Use the directory as the feature directory in
   every step below (set `SPECIFY_FEATURE_DIRECTORY` to it) instead of numbering one yourself. Under the
   spec's title write the line `**Задачи**: BCKLG-<N>`; a spec that carries several tasks names each,
   its own task first. `plan.md` and `tasks.md` of the spec carry the same line.
2. **The candidates.**
   - You are in an engine run when the file `.sdlc/run-input.json` exists in the working copy: it is the
     run's input (`runInputVersion` 1), which the engine always writes. Read its `ecosystem` field: the
     repositories the catalog suggests, with the chain of relations to each, and the constitutions it
     holds. These are hints, not verdicts. With the file but no `ecosystem`, stop before writing anything
     and say that it is missing. Without the file you are working by hand.
   - By hand, read `catalog-info.yaml` of the repositories the task names, of those that use them
     and of those they use, and their constitutions (`.specify/memory/constitution.md`).
3. **A verdict for each.** Give every repository the task names, every candidate, and any other you find, a
   verdict: `затронут`, `не затронут` or `неясно`, with the reason and the evidence. The evidence is one of
   three kinds, and you say which: a reference to code (`path:line`), the chain of relations from the
   catalog, or a principle of the repository's constitution; if you did not read the code, say so
   (for example «по каталогу, код не читался»). A repository you cannot decide stays in the feature with
   the verdict `неясно`; never drop it. A named repository that does not exist is said so and gets no
   verdict. If nothing is named and nothing is found, ask which repositories the feature affects instead
   of guessing.

Then specify as below, for the repositories with the verdict `затронут` or `неясно`.

{CORE_TEMPLATE}

## After you specify: the repositories, the order and the rules

Add these to the specification you wrote, in its language, keeping the sections above.

4. **Sections.**
   - `## Репозитории`: a table with exactly the columns `Репозиторий`, `Вердикт`, `Что меняется`,
     `Основание`, one row per repository of step 3, the kind of evidence said in `Основание`. A feature of
     one repository has one row. Keep a `не затронут` row to one short line, and say a reason shared by
     several rows once, in the row `остальные репозитории организации`, instead of repeating it in each.
   - Each functional requirement names the repository it is for in brackets, as `[<repository>]`, or
     `[все]` when it is for all of them.
   - `## Порядок выпуска и контракты`: a numbered order in which the repositories are released and, for
     each dependency between them, what one repository gives the other. Leave it empty, with the words
     «Нет: затронут один репозиторий», when only one is affected.
   - At the top, `## Что специфицируется и как это будет работать`: three to five short bullet lines (one
     sentence each, a line break after each, no wall of text) saying what is specified and how it will work
     across the repositories, for a reader who will read nothing else.
5. **The rules of the repositories.** Check the specification against the constitution of this repository and
   the constitution of every repository whose verdict is `затронут` or `неясно` and of their neighbours in
   the catalog graph (those in `ecosystem` when you have it, otherwise those you read in step 2). A conflict
   is a critical finding in `checklists/requirements.md`: name the repository and the principle, then change
   the specification or put the conflict to the user as a question. A constitution you do not have is
   listed there as not checked.
