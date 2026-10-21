# How to start with Symphony-Eiffel

Use Symphony as a **task queue for Codex**:

`GitHub Issues or issues.json → Symphony → separate workspace per issue → Codex edits and tests files`

[WORKFLOW.md](examples/WORKFLOW.md) defines configuration and agent instructions. Use the
[local JSON demo](examples/issues.json) for a first run, then the
[GitHub Issues workflow](examples/github/WORKFLOW.md) for repository tasks. Both trackers are
read-only from Symphony's perspective.

## Quick start

### 1. Build and run the local demo

From the repository root in PowerShell:

```powershell
ec -version
codex --version
.\scripts\build.ps1
.\scripts\test.ps1
.\scripts\integration-test.ps1

$symphony = ".\.build\eiffel\EIFGENs\symphony\W_code\symphony.exe"

# Validate configuration without polling, hooks, workspaces, or Codex.
& $symphony --validate .\examples\WORKFLOW.md

# Run one scheduling cycle and wait for its work to finish.
& $symphony --once .\examples\WORKFLOW.md
```

The second Symphony command starts a real Codex session when a demo issue is eligible. It asks
Codex to create `GREETING.md`, normally below `%TEMP%\symphony_workspaces\DEMO-1\`. Inspect the
file, diff, tests, and JSONL logs before accepting the result. The integration test uses a mock
Codex app-server; it does not validate live GitHub access or Codex authentication.

The repository's protocol defaults and fixtures were validated against `codex-cli 0.130.0-alpha.5`.
Check your installed version and follow the
[compatibility guidance](README.md#codex-app-server-compatibility) before changing versions.
Configuration validation does not check Codex authentication or protocol compatibility.

### 2. Select GitHub Issues or a local JSON queue

For GitHub, copy [examples/github/WORKFLOW.md](examples/github/WORKFLOW.md) to a directory for
your own configuration. Replace `YOUR-OWNER/YOUR-REPO` in both the provider and clone hook.
Install GitHub CLI (`gh`) on `PATH` and authenticate it separately:

```powershell
gh --version
gh auth login --hostname github.com
gh auth status --hostname github.com
```

The tracker settings are:

```yaml
tracker:
  kind: github
  provider:
    repository: YOUR-OWNER/YOUR-REPO
    hostname: github.com
    request_timeout_ms: 30000
  required_labels: [symphony]
  active_states: [open]
  terminal_states: [closed]
```

Create or select an open issue with the `symphony` label, a clear description, and acceptance
criteria. Review the workflow's hooks and prompt, then run it with `--validate` followed by
`--once`. Validation is local; the first poll checks authentication and repository access.
GitHub tasks in this profile are issues; Projects board statuses and task-list checkbox
synchronization are not supported.

For a local queue, copy [examples/WORKFLOW.md](examples/WORKFLOW.md) and
[examples/issues.json](examples/issues.json) together. Each issue needs unique IDs and
identifiers, an active state such as `Todo`, the `symphony` label, and `dispatchable: true`.

For either tracker, choose a dedicated root for disposable issue workspaces. Populate each new
workspace with an `after_create` hook. Clone into a child directory such as `repository`, then
use `git -C repository ...` in hooks and tell the agent to work there. Cloning into `.` fails
because Symphony places an initialization marker in the new workspace. Start with one agent
and a prompt containing the project's build/test commands and expected output.

See the [GitHub tracker reference](README.md#github-tracker) for pagination, issue mapping,
authentication, timeout, response limits, and error handling. Keep tokens out of workflows,
issue fields, and command strings. Symphony removes the four documented GitHub token environment
variables from Codex's child environment, including names declared before workflow reloads;
the host's existing `gh` credential-store access remains available under host access controls.

### 3. Review and preserve results before closing an issue

After `--once` finishes:

1. Stop further dispatch while reviewing: remove the `symphony` label from an open GitHub issue,
   or set a JSON issue to `"state": "Review"` and `"dispatchable": false`.
2. Inspect the workspace, diff, test results, and logs.
3. Push or copy the results somewhere outside the disposable workspace.
4. Close the GitHub issue, or set the JSON issue's state to `Done`, only after preserving the result.

**Marking an issue terminal can cause its workspace to be deleted.** A commit stored only inside
that workspace is not sufficient preservation. An open GitHub issue without the required label
is suitable for review without making it terminal.

When ready, omit `--once` to poll continuously. An issue that remains eligible can run repeatedly,
even after a successful attempt. `max_turns` limits one worker attempt, not the issue's total
lifetime. Symphony does not automatically change issue states, post comments, or publish PRs.
Handle those actions manually or through a separately configured workflow.

## Svensk arbetsguide

### 1. Vad Symphony gör

Använd Symphony-Eiffel som en arbetsledare för Codex: du beskriver avgränsade utvecklingsuppgifter,
Symphony sköter körningarna och du granskar resultatet.

| Del | Så fungerar det |
| --- | --- |
| Uppdragslista | GitHub Issues via `tracker.kind: github`, en lokal `issues.json` via `json_file`, eller en minnesadapter för tester. |
| Arbetsinstruktioner | `WORKFLOW.md` innehåller körinställningar och instruktionen som Codex får tillsammans med ärendet. |
| Arbetskatalog | Varje ärende får en separat, tillfällig arbetskatalog. En hook kan klona projektets Git-repo i en underkatalog. |
| Utförande | Symphony startar en separat installerad och autentiserad Codex CLI genom `codex app-server` och hanterar samtidighet och återförsök. |
| Uppföljning | Strukturerade JSONL-loggar visar körningarna. Du eller en extern integration sköter ärendestatus, kommentarer och PR-publicering. |

Eiffel är orkestratorns implementationsspråk. Uppdragen kan även gälla exempelvis C#/.NET eller
Python, om projektets bygg- och testverktyg finns på kördatorn. Jira och Linear har ännu inga
inbyggda adaptrar. GitHub-kopplingen läser ärenden; den synkroniserar inte GitHub Projects eller
kryssrutor i uppgiftslistor.

### 2. Börja med ett tydligt uppdrag och en agent

Behåll vanlig Codex-dialog för problemlösning och uppgifter som fortfarande behöver diskuteras.
Använd Symphony när uppgiften har tydliga gränser och acceptanskriterier. Ett lämpligt första
uppdrag är:

> Lägg till tester för felaktiga indata i den angivna komponenten. Ändra inte komponentens
> publika gränssnitt. Kör projektets befintliga testkommando. Redovisa ändrade filer,
> faktiskt utförda kontroller och eventuella kvarstående problem.

Börja med ett projekt, en agent åt gången och manuell granskning efter varje engångskörning.
Du bestämmer uppgiften och acceptanskriterierna, Symphony driver körningen och Codex ändrar och
kontrollerar filerna. En lyckad körning innebär inte automatiskt att resultatet är godkänt.

### 3. Bygg och prova den lokala demonstrationen

Kör kommandona i den engelska snabbstarten ovan från repots rot. Kör dem stegvis och åtgärda
bygg- eller testfel innan du fortsätter. Körmiljön behöver EiffelStudio med C-verktyg, PowerShell,
Bash och en autentiserad Codex CLI; se [kraven i README](README.md#requirements).

`--validate` kontrollerar konfigurationen utan att skapa eller ta bort arbetskataloger, köra
hooks, kontakta GitHub eller starta Codex. `--once` gör däremot en riktig körning om ett ärende
är körbart. Demonstrationen använder en lokal JSON-fil och skapar ett tomt Git-repo, så den
arbetar inte i ditt befintliga projekt. Kontrollera att `GREETING.md` skapats och motsvarar
uppdraget.

Det dokumenterade app-server-schemat är verifierat mot `codex-cli 0.130.0-alpha.5`, vilket inte
innebär att alla CLI-versioner fungerar. Följ [versionskontrollen i README](README.md#codex-app-server-compatibility)
när Codex uppgraderas. Mocktestet kontrollerar klientprotokollet utan riktiga konton; en lokal
validering eller ett mocktest bekräftar inte åtkomst till GitHub.

### 4. Koppla flödet till ett riktigt projekt

För GitHub Issues: kopiera [GitHub-exemplet](examples/github/WORKFLOW.md) till exempelvis
`pilot/WORKFLOW.md`. Byt båda förekomsterna av `YOUR-OWNER/YOUR-REPO` till ditt repo. Kontrollera
`gh --version`, logga in med `gh auth login --hostname github.com` och kontrollera med
`gh auth status --hostname github.com`. Inga tokenvärden ska läggas i konfigurationen.

Exemplet använder `open` som aktiv status, `closed` som terminal status och kräver etiketten
`symphony`. Lägg etiketten på ett öppet ärende som du vill köra. GitHub-adaptern läser alla sidor
och både öppna och stängda ärenden vid uppdateringar, så den kan upptäcka avslutade ärenden och
borttagna etiketter. Pull requests som GitHub returnerar från ärende-API:et ignoreras. Etiketter
filtreras lokalt. Fullständiga begränsningar finns i [referensen](README.md#github-tracker).

För en lokal kö: kopiera i stället [JSON-flödet](examples/WORKFLOW.md) och
[issues.json](examples/issues.json) till `pilot`. Ett avgränsat uppdrag kan se ut så här:

```json
{
  "issues": [
    {
      "id": "pilot-001",
      "identifier": "PILOT-1",
      "title": "Dokumentera kontroll efter installation",
      "description": "Skapa docs/SMOKE_TEST.md med en kort installationskontroll. Utgå från README.md och befintliga scripts. Beskriv validering och en engångskörning. Arbeta i underkatalogen repository. Ändra inga befintliga filer. Kontrollera filnamn och kommandon mot repot. Skilj mellan kontroller du kört och kontroller som bara beskrivs.",
      "state": "Todo",
      "labels": ["symphony"],
      "dispatchable": true
    }
  ]
}
```

Om JSON-flödet ska arbeta på ett riktigt projekt, ersätt dess `git init` med en kloningshook.
Följande Windows-exempel klonar Symphony-repot i en underkatalog:

```yaml
workspace:
  root: C:/SymphonyWorkspaces/pilot

hooks:
  timeout_ms: 60000
  after_create: |-
    git clone https://github.com/andersoxie/Symphony-Eiffel.git repository
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  before_run: |-
    git -C repository status --short
  after_run: |-
    git -C repository status --short
```

Kloning direkt i `.` fungerar inte eftersom Symphony lägger en initieringsmarkör där. Ange även
i prompten att agenten ska göra ändringar och köra kontroller i `repository`. `after_create`
körs bara när arbetskatalogen skapas; projektet klonas inte på nytt inför varje försök. Hooks
körs på värddatorn utanför Codex-sandboxen, så granska dem som körbar kod.

Behåll en samtidig agent och `max_turns: 1` under piloten. Lägg exempelvis till följande i
Markdown-prompten:

> Läs projektets AGENTS.md om den finns. Arbeta i underkatalogen repository. Genomför endast
> det angivna uppdraget. Lämna ändringarna för manuell granskning. Gör ingen commit, push,
> merge, driftsättning, GitHub-kommentar eller ärendestängning. Skriv en kort RESULTAT.md i
> repository med ändrade filer, faktiskt utförda kontroller och eventuella hinder.

Kör sedan:

```powershell
& $symphony --validate .\pilot\WORKFLOW.md
& $symphony --once .\pilot\WORKFLOW.md
```

### 5. Överlämna till granskning innan ärendet avslutas

Båda produktionsadaptrarna är skrivskyddade ur Symphonys perspektiv. En avslutad Codex-körning
ändrar inte ärendets status. I kontinuerlig drift kan ett ärende som fortfarande är valbart
köras igen, även efter ett lyckat försök. `max_turns` begränsar ett enskilt arbetsförsök.

| Källa | Stoppa fortsatt körning för granskning | Avsluta efter att resultatet säkrats |
| --- | --- | --- |
| GitHub Issues | Ta bort etiketten `symphony` och behåll ärendet öppet. | Stäng ärendet, vilket gör det terminalt enligt exemplet. |
| Lokal JSON | Sätt `"state": "Review"` och `"dispatchable": false`. | Sätt status till `Done`, som är terminal i JSON-exemplet. |

Gör granskningsändringen efter att `--once` avslutats och före nästa körning. Granska diff,
kontroller och loggar, och spara sedan resultatet utanför den tillfälliga arbetskatalogen.

**Stäng inte GitHub-ärendet och sätt inte `Done` innan resultatet är säkrat.** Terminala ärenden
kan få sin arbetskatalog borttagen vid avstämning, även vid uppstart. En lokal commit som bara
finns i arbetskatalogen räcker inte; kopiera resultatet eller pusha det till ett beständigt repo.

### 6. Bygg vidare från den fungerande kedjan

GitHub Issues kan nu vara den direkta uppdragskällan. Nästa integrationssteg kan vara en separat,
uttryckligt konfigurerad återrapportering som bevarar resultat, länkar en PR till rätt ärende och
stoppar fortsatt körning under granskning. Den inbyggda adaptern skriver inte kommentarer,
ändrar inte status och publicerar inte PR:er.

För Jira behövs fortfarande en separat adapter eller en integration som exporterar ärenden till
JSON-kön. En sådan integration behöver även hantera överlämning till granskning och säkra
resultatet innan terminal städning. Börja med dokumentation och tester, gå vidare till mindre
felrättningar och utöka parallelliteten när hela kedjan från uppdrag till granskning fungerar.
