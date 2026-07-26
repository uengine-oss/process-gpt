# Scenario 9 — Prompt Chaining Agentic Pattern Demo: Market Insight Chain

Demonstrates the "Prompt Chaining" agentic pattern — breaking a complex task into
several steps and passing each step's output as the next step's input — as a
single BPMN process running for real on ProcessGPT. ProcessGPT has no dedicated
"chaining" primitive — **the BPMN sequence itself is the expression of chaining**:
each step runs unattended with `orchestration: "deepagents"` (the deepagent type),
and the later step's `inputData` references the earlier step's form field.

Target process, "Market Insight Chain" (3 steps, all with skills assigned →
`agentMode: "complete"` + `orchestration: "deepagents"`):

1. **Summarize market research report** — the only human touchpoint: a person
   submits the raw market research report text. Skill: summarization. Output
   field (example) `report_summary`.
2. **Identify key trends** — runs unattended via deepagents. `inputData:
   ["<step-1 form_id>.report_summary"]`. Skill: trend identification (top 3
   trends + supporting evidence points). Output field (example)
   `trend_analysis`.
3. **Draft marketing team email** — runs unattended via deepagents. `inputData:
   ["<step-2 form_id>.trend_analysis"]`. Skill: email drafting. Output field
   (example) `email_draft`.

A single agent role ("Marketing Insight Assistant") owns all 3 skills and
handles all 3 activities (same role×skill mapping as
`skills/bpmn-process-generation-skill/references/05-agents.md` — identical
mechanism to Scenario 2, just a different domain).

Prerequisite: must be logged in with the fixed account from
[demo-account.md](demo-account.md).

## 1. Creation — explicitly request the chaining structure

⚠️ Same lesson learned in Scenario 1: simply saying "create a
summarize→trend→email process" can silently drop the automation/chaining
intent. Explicitly request **unattended sequential processing and reference
to the prior step's output**, as below.

In `/definition-map`:
```
Create a process that analyzes a market research report and sends an insight
email to the marketing team. Step 1: the person in charge enters the market
research report text. Steps 2 (identify key trends) and 3 (draft the marketing
team email) must be processed automatically, in order, by the deepagent with
no human involvement. Each step must reference the previous step's output —
this must work as a chaining flow. Step 3 must not just summarize; it must
write the email based on the specific trends identified in step 2.
```

The rest follows the same pattern as Scenario 2 (review the draft → confirm
chip + "Submit response" → pick 3 skills (summarization / trend identification
/ email drafting) and 1 agent from the `skills_batch`/`agents_batch` question →
save):

```sql
select status, draft_status from todolist where id='<workitem_id>';
select definition::text from proc_def where id='<proc_def_id>';
```

**Consistency checklist** (verify right after saving):
- All 3 activities have `activities[].orchestration = "deepagents"` and
  `agentMode = "complete"`.
- Step 2's `inputData` contains step 1's summary field, and step 3's
  `inputData` contains step 2's trend field (per the
  `08-reference-info.md` rule — only predecessor-step form fields may be
  referenced).
- The `skills` array has all 3 skills, and 1 agent is correctly linked to each
  activity.

## 2. Execution — only the first activity is submitted by a human; steps 2–3 chain unattended

As in Scenarios 1/2, call the `/completion/complete` API directly with a JWT
(reuse the Playwright login + JWT extraction snippet from demo-account.md).
Submit the market research report text to the first activity (report
summarization):

```bash
curl -X POST "http://localhost:8088/completion/complete" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"input": {
    "process_definition_id": "<proc_def_id>",
    "process_instance_id": "<proc_def_id>.<uuid>",
    "activity_id": "<step-1 activity_id>",
    "email": "demo@localhost",
    "user_id": "<auth_uid>",
    "username": "demo",
    "form_values": { "<step-1 form_id>": { "market_report": "<market research report text>" } }
  }}'
```

Right after submission, poll to confirm steps 2–3 transition automatically
with no human involvement:
```sql
select activity_id, status, agent_mode, agent_orch, start_date, end_date
from todolist where proc_inst_id='<inst_id>' order by start_date;
```
- Both step 2 (`Identify key trends`) and step 3 (`Draft marketing team email`)
  show `agent_mode='COMPLETE'`, `agent_orch='deepagents'`, and reach `DONE` in
  order within seconds to tens of seconds after the step-1 submission —
  demonstrate this with 2–3 `/todolist` screen captures (the cards move on
  their own).

## 3. Demo talking points — ground the slide's 4 characteristics in measured evidence

1. **Sequential dependency**: confirm that step 3's final output (the email
   draft) actually cites the **specific trend names/evidence** identified in
   step 2 (not generalities — the presence of values that exist only in step
   2's output is the proof of chaining). Cross-check each activity's `output`
   field in `todolist` directly.
2. **Task decomposition**: show, via each skill's SKILL.md, that a single
   giant "analyze the report" prompt was instead split into 3 narrow skills —
   summarization / trend identification / email drafting.
3. **Per-step optimization**: show, by comparing the skill files, that each
   activity has its own dedicated skill (3 skill files, each with a different
   `procedure`), so output quality is optimized for that step's specific
   purpose.
4. **Clear observability**: show on screen that `/todolist` and the workitem
   detail's "Delegate to Agent" tab (AgentMonitor) expose each step's execution
   card, timestamps, and `agent_orch=deepagents` as-is — proving intermediate
   results can be monitored/debugged in real time.

## 4. Known pitfalls

- If the chat prompt doesn't explicitly state "unattended automatic
  processing" and "reference the previous step," some activities may be
  generated with `agentMode: draft` or human assignment (the same class of
  problem as the missing branch in Scenario 1) — always run the Section 1
  consistency checklist right after saving.
- As in Scenario 2, the assigned role ("Marketing Insight Assistant") must be
  linked to a real agent uuid in `roles[].endpoint` for steps 2–3 to go
  straight to the agent with no human assignment — only the first activity
  needs to be overridden to the demo account (same reasoning as Scenario 2's
  Section 3).
- If you doubt whether the skill was actually used, apply Scenario 2's "3 ways
  to confirm a skill was actually used" (compare output content / `docker logs
  deepagents` / check the skill file inside the sandbox) as-is.

## 5. Verified end-to-end path (update with measured values on reproduction)

```
Summarize market research report (DONE, human-submitted)
→ Identify key trends (DONE, deepagents+skill, unattended, references step-1 output)
→ Draft marketing team email (DONE, deepagents+skill, unattended, references step-2 output)
→ bpm_proc_inst.status = COMPLETED
```

## Post-demo report

- The created proc_def id, the 3 skill slugs, the agent name/uuid
- The started proc_inst id
- SUBMITTED→DONE timestamps for steps 2–3 (evidence of unattended chaining)
- Evidence that step 3's output actually referenced step 2's output (text
  cross-check result)
- The final `bpm_proc_inst.status`
- The final recording's path/length, whether narration was used, and which
  voice (same as recording-and-narration.md item 6)
