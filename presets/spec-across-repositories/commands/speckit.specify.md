## Before you specify: which repositories does the feature affect?

A feature of this organization usually touches several repositories, and this specification is the one
document for all of them. Do steps 1 to 3 first, in this session, with no other agent for any repository.

1. **The directory.** The feature's directory is `specs/<number of the feature's issue>-<short name>` in
   this repository, so that no number is taken twice in the organization. Ask for the issue number if
   you do not have it; never invent one. Use this directory as the feature directory in every step below
   (set `SPECIFY_FEATURE_DIRECTORY` to it) instead of numbering one yourself.
2. **The candidates.**
   - You are in an engine run when the task came with a run input (a `RunInput`), which the engine always
     gives; without one you are working by hand. In an engine run, read `ecosystem` in that run input:
     the repositories the catalog suggests, with the chain of relations to each, and the constitutions it
     holds. These are hints, not verdicts. If the run input has no `ecosystem`, stop before writing
     anything and say that it is missing.
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
     one repository has one row.
   - Each functional requirement names the repository it is for in brackets, as `[<repository>]`, or
     `[все]` when it is for all of them.
   - `## Порядок выпуска и контракты`: a numbered order in which the repositories are released and, for
     each dependency between them, what one repository gives the other. Leave it empty, with the words
     «Нет: затронут один репозиторий», when only one is affected.
   - A short paragraph at the top, `## Что специфицируется и как это будет работать`: what is specified,
     and how it will work across the repositories, for a reader who will read nothing else.
5. **The rules of the repositories.** Check the specification against the constitution of this repository and
   the constitution of every repository whose verdict is `затронут` or `неясно` and of their neighbours in
   the catalog graph (those in `ecosystem` when you have it, otherwise those you read in step 2). A conflict
   is a critical finding in `checklists/requirements.md`: name the repository and the principle, then change
   the specification or put the conflict to the user as a question. A constitution you do not have is
   listed there as not checked.
