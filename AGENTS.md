If I ask you a question, answer it, it doesn't mean do something. If I want you to do something, I will tell you directly to do it.

ALWAYS use gpt-5.5 or better for sub agents workers, 5.4 mini is acceptable for exploration searches, but not for analysis search

After executing every implementation task inside an approved plan, run build and install so the user can test the finished work from PATH.

NEVER run build, tests, or install for plan-only requests, research-only requests, questions, or documentation-only edits unless the user explicitly asks for verification commands.

-----

Grok SWIFT

Swift library for Grok.com

Grok CLI 

Optimized for clean human readability 

Grok Docker

OpenAI-compatible API for Grok.com

The proxy service is a Vapor HTTP API service that exposes OpenAI-compatible endpoints backed by Grok, including /v1/chat/completions and /v1/models

------

## Plan Mode

When the user asks to plan, make the plan itself the deliverable. Do not jump straight into implementation unless the user explicitly asks for execution after the plan is written.

Plan mode requires a deep dive before writing the plan:

- Inspect the relevant code, tests, scripts, docs, PRs, issues, and runtime behavior needed to understand the work.
- Use sub agents for independent investigation threads whenever the plan needs more than one line of inquiry.
- Manage up to 6 sub agents at a time.
- Give each sub agent a clean, specific task with only the context it needs.
- Never fork full history into sub agents.
- Close completed sub agents before launching more.
- Synthesize sub agent findings yourself; do not paste raw agent output as the final plan.

Create a plan spec file for every plan-mode request:

- Save the plan spec under the `plans/` folder.
- Use a descriptive Markdown filename, for example `plans/2026-05-13-streaming-fixes-plan.md`.
- If the `plans/` folder does not exist, create it.
- The plan spec must be detailed enough that another agent can execute it without redoing the discovery work.

The plan spec must include:

- Objective and success criteria.
- Current-state findings with file paths and relevant commands.
- Workstreams divided so they can be executed by up to 6 parallel agents.
- Clear ownership boundaries for each workstream.
- Markdown todo checklists for every task.
- Dependencies between workstreams.
- Concrete implementation steps.
- Test and verification gates.
- Risks, edge cases, and rollback notes.
- A final completion checklist mapping each user requirement to evidence.

Use Markdown todos to track the work:

- `- [ ]` for pending tasks.
- `- [x]` for completed discovery tasks.
- Keep tasks grouped by workstream.
- Include enough detail in each todo that it can be assigned directly to an agent.

When presenting the plan to the user, summarize the plan spec briefly and link to the saved file. Do not claim the plan has been executed unless implementation and verification have actually happened.
