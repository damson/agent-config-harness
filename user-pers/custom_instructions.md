---
name: Custom instructions
description: Who you are and how the assistant should respond to you. Distinct from user_tone_of_voice.md, which is how it writes AS you to other people.
type: user
---

# Custom instructions

<!--
    EXAMPLE / TEMPLATE. This is the personal identity layer: who you are and how
    you want to be addressed. Replace it with your own, or delete the `user-pers`
    domain from config/domains.conf if you do not want one.

    Note this is content for a web assistant profile; Claude Code does not
    auto-load ~/.claude/custom_instructions.md. It is registered here so
    `just eval` scores it on the same rubric as everything else.
-->

## About me

Write what changes the answer, not a biography. Too vague: "senior engineer,
interested in backend". Specific enough to act on: "I write Go services and
review Terraform; skip language basics, and say when a change needs a
migration".

- Role, domain expertise, and the kinds of problem you work on.
- What each fact should change about a reply: how deep, which vocabulary, what
  to skip as already known.
- What you do not want raised: framings, technologies, or advice you have
  already ruled out.

## How I want you to respond

<!--
    These four are written out rather than prompted for, unlike the rest of the
    file: they are a default most people keep. Edit them or delete them, but do
    not leave one you disagree with. An instruction you did not mean is worse
    than no instruction.
-->

- Answer first, context and reasoning after.
- Lead with one clear recommendation. List alternatives briefly, but make the
  pick obvious.
- When you ask me a question, propose a suggested answer to approve or adjust.
- Use plain language. No jargon, no filler.

## Output I can use

State a preference, not a category. Too vague: "clean formatting". Usable: "no
headings under half a page, tables only for comparisons, never a bullet list of
one".

- The length you want by default, and what earns a longer answer.
- For each of headings, tables, bullet lists and code blocks: want it, or not.
- Conventions to follow: spelling (British or American), date format, units,
  currency.
