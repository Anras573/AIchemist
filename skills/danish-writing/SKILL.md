---
name: danish-writing
description: |
  Use this whenever text must be written, translated, or polished in Danish, including emails, messages, documentation, posts, and replies. It makes the agent compose directly in Danish and then check the result against a list of common English-to-Danish translation tells. Exact trigger phrases: "write in Danish", "in Danish", "skriv på dansk", "på dansk", "translate to Danish", "oversæt til dansk", "Danish email", "dansk mail", "dansk tekst", "ret mit danske", "make this sound more Danish", "lyder som en oversættelse".
version: 1.0.0
---

# Danish Writing Skill

Danish written by a model often reads like a translation. The facts and the reasoning come out in English shapes: English sentence structure, idioms translated word for word, English typography, and an English tone. This skill changes the process. Think and draft in Danish from the start, then check the text against the patterns that give translations away.

## Read vs Write Operations

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | Read `references/checklist.md` and `references/examples.md` | Automatic, no confirmation needed |
| **Write** | Save the finished text to a file | Only when the user asks |

## Workflow

### 1. Load the references

Read both files before writing anything:

- `references/examples.md`: before/after pairs from the user's own edits. **These take priority over everything else in this skill.** If an example conflicts with the checklist, follow the example.
- `references/checklist.md`: the generic list of translation tells.

### 2. Settle the register

Find out who the reader is and what the channel is. Ask one short question only if you can't infer it:

- **Address:** *du* (default for almost everything), *I* (a group), or *De* (very formal, rare; use it only if asked).
- **Tone:** Danish professional writing is understated and direct. Tone down English enthusiasm: no *Vi er så glade for at…* and no exclamation marks in business text.
- **Channel:** a Slack message, an email, documentation, and a public post each have their own conventions. Match them.

### 3. Plan in Danish, not in English

- Write the key points as short Danish notes, not English sentences.
- If the source material is English (a ticket, a spec, an English draft), take the **meaning** from it, not the sentences. Don't keep the English paragraph structure, sentence order, or metaphors. Ask: "How would a Dane explain this to a colleague?"
- Use Danish terms where Danes use them, and keep English loanwords where Danes actually use them (*deploy*, *pull request*, *backlog* are fine in a Danish dev team). Don't invent Danish words nobody uses.

### 4. Write directly in Danish

- Prefer short main clauses, active voice, and verbs over nouns (*vurdere*, not *foretage en vurdering af*).
- Put the point first. Danish texts get to the point faster than English ones and use less padding before and after it.
- Keep the structure light. Not everything needs bullet points and headings.

### 5. Revision pass

Go through `references/checklist.md` section by section and fix every hit. When something sounds translated, **rewrite the whole sentence**. Swapping single words leaves the English skeleton in place.

Finish with a read-aloud test: read each sentence as if speaking to a Danish colleague. If nobody would say it like that, rewrite it.

### 6. Deliver

- Return only the Danish text. Don't add an English version or back-translation unless asked.
- Don't explain the edits unless the user asks. When polishing the user's own text, briefly list the substantive changes (not every comma).

## Adding examples

The user grows `references/examples.md` over time with real before/after pairs. When the user corrects Danish you wrote in a session, offer to add the pair to that file.
