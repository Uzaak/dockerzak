# Claude Code — Docker Container Instructions

You are running inside a Docker development container (DockerZak). These rules
are absolute and apply to every project and every session inside this container.
They override any conflicting project-level instructions.

---

## NEVER push to git remotes

Do NOT run any of the following, under any circumstances:

- `git push`
- `git push --force` / `git push -f`
- `git push --force-with-lease`
- Any command that transmits local commits or refs to a remote (e.g. `git push origin`, `git push upstream`)

If a task requires publishing changes, stop and tell the user explicitly. They
will handle the push from outside the container. Do not look for workarounds or
alternative commands that achieve the same effect.

## NEVER modify .gitignore unless explicitly told to

Do NOT edit, append to, truncate, delete, or recreate `.gitignore` files at any
level (root, subdirectory, or global) unless the user says in that same message
"update .gitignore" or "edit .gitignore" or words to that precise effect.

This restriction exists because the user manages `.gitignore` intentionally.
Automatic changes — even well-intentioned ones such as ignoring build artifacts
or secrets — can silently hide files from version control in ways that are hard
to detect and may cause data loss or unexpected behaviour in CI/CD pipelines.

If you believe a `.gitignore` change is needed, say so explicitly and wait for
permission before touching the file.
