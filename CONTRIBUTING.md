# Contributing

Open an issue first for bigger changes. One pull request is one change. Keep the diff minimal and fix the root cause. Follow the existing style. Write everything in English: code, comments, docs, commits, and pull request text.

Pull requests are squash-merged. The pull request title and description become the commit message, so use an imperative title such as "Add …" or "Fix …".

CI must pass: the app linter, ShellCheck and script tests, and the image builds. Run the script tests locally with `tests/run-all.sh`.

For a user-visible change, bump the version in `grokbot_client/config.yaml` and add a matching `## x.y.z` section with a short bullet in `grokbot_client/CHANGELOG.md`.
