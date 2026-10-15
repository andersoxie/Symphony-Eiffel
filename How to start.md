Use it as a **local task queue for Codex**:

`issues.json → Symphony → separate workspace per issue → Codex edits and tests files`

[WORKFLOW.md](C:/Users/ander/Documents/ChatGPT/Symphonyh/examples/WORKFLOW.md) defines configuration and agent instructions. [issues.json](C:/Users/ander/Documents/ChatGPT/Symphonyh/examples/issues.json) supplies the tasks.

**1. Start with the included demo**

You already have a compiled executable, and I verified that its example configuration passes validation. From this repository’s PowerShell terminal:

```powershell
$symphony = ".\.build\eiffel\EIFGENs\symphony\W_code\symphony.exe"

# Check configuration without starting Codex
& $symphony --validate .\examples\WORKFLOW.md

# Run one scheduling cycle and wait for its work to finish
& $symphony --once .\examples\WORKFLOW.md
```

The second command starts a real Codex session. The example asks it to create `GREETING.md`, normally under:

```text
%TEMP%\symphony_workspaces\DEMO-1\
```

**One compatibility check first:** your installed Codex is `0.117.0`; the repository documents protocol validation against `0.130.0-alpha.5`. Compatibility with your installed version remains unverified. Configuration validation does not check Codex authentication or protocol compatibility.

To rebuild and run the repository’s checks:

```powershell
.\scripts\build.ps1
.\scripts\test.ps1
.\scripts\integration-test.ps1
```

The integration test uses a mock Codex server.

**2. Configure it for your own project**

Copy the two example files into a configuration directory, then adjust:

- **Workspace root:** choose a dedicated directory for disposable issue workspaces.
- **`after_create` hook:** populate each workspace with your project. Clone into a child folder such as `repo`, and update the prompt and other hooks to work there. Cloning into `.` fails because Symphony places an initialization marker there.
- **Prompt:** specify the project’s build/test commands, acceptance criteria, and expected output.
- **Issues:** supply unique IDs and identifiers, clear descriptions, an active state such as `Todo`, the required `symphony` label, and `dispatchable: true`.

Keep the example’s concurrency of one while establishing this workflow. `branch_name` is only a prompt hint; Symphony does not automatically create that branch.

**3. Review and preserve results before closing an issue**

A practical first workflow is:

1. Run `--once`.
2. Inspect the workspace, diff, tests, and JSONL logs.
3. Set `dispatchable: false` while reviewing.
4. Push or copy the results somewhere outside the disposable workspace.
5. Set the issue’s state to `Done`.

**Marking an issue terminal can cause its workspace to be deleted.** A commit stored only inside that workspace is not sufficient preservation.

When ready, omit `--once` for continuous polling:

```powershell
& $symphony .\examples\WORKFLOW.md
```

Continuous mode can repeatedly run an issue that remains eligible—even after a successful attempt. You or an external process must update the JSON tracker. This implementation does not automatically update GitHub/Linear issues or open PRs, and `max_turns` limits each attempt rather than the issue’s total lifetime.



Anders, **du bör använda Symphony-Eiffel som en arbetsledare för Codex: du lägger fram tydliga utvecklingsuppgifter, Symphony sköter körningarna och du granskar resultatet.** Du går alltså från att styra varje Codex-session till att styra *vilket arbete som ska göras och vad som krävs för att det ska godkännas*. Det är också grundidén i OpenAI:s Symphony. [OpenAI](https://openai.com/index/open-source-codex-orchestration-symphony/?utm_source=chatgpt.com)

Jag har nu läst dokumentationen, exemplen och delar av körlogiken i `andersoxie/Symphony-Eiffel`. Nedan utgår jag från den version som ligger på `main`; jag har inte provkört din lokala installation.

## 1. Vad din implementation faktiskt kan användas till

Din version har redan de centrala delarna för att köra lokala Codex-uppdrag, men den har ett enklare operatörsgränssnitt än den ärendetavla som visas i OpenAI:s demonstration:

| Del | Så fungerar det i din implementation |
|---|---|
| **Uppdragslista** | Uppgifterna läses från en lokal `issues.json`. Det finns ännu ingen direkt adapter för Jira, GitHub Issues eller Linear. |
| **Arbetsinstruktioner** | `WORKFLOW.md` innehåller både körinställningar och instruktionen som Codex får tillsammans med ärendet. |
| **Arbetskatalog** | Varje ärende får en separat arbetskatalog. En konfigurerad startåtgärd, en *hook*, kan exempelvis klona projektets Git-repo dit. |
| **Utförande** | Symphony startar lokalt installerad Codex genom `codex app-server` och hanterar bland annat samtidighet och återförsök. |
| **Uppföljning** | Du får strukturerade loggar. Statusändringar i ärenden och återrapportering av PR-länkar måste skötas separat. |

Detta framgår av ditt repos dokumenterade profil och begränsningar. 

**Att Symphony är skrivet i Eiffel betyder inte att uppdragen måste gälla Eiffel.** Det är orkestratorns implementationsspråk. Utifrån hur din version startar Codex i en arbetskatalog kan den även användas för exempelvis C#/.NET och Python, förutsatt att projektets bygg- och testverktyg finns tillgängliga där körningen sker. 

## 2. Så skulle jag använda det i ditt dagliga arbete

Min rekommendation är att behålla vanlig Codex-dialog för problemlösning, arkitektur och uppgifter som fortfarande behöver diskuteras. Använd Symphony när uppgiften är tillräckligt tydlig för att kunna lämnas över.

Ett lämpligt uppdrag är exempelvis:

> Lägg till tester för felaktiga indata i den angivna komponenten.  
> Ändra inte komponentens publika gränssnitt.  
> Kör projektets befintliga testkommando.  
> Redovisa vilka tester som tillkommit, vilka kontroller som körts och eventuella kvarstående problem.

Ett mindre lämpligt första uppdrag är:

> Förbättra hela systemets arkitektur och säkerhet.

Jag skulle börja med **ett projekt, en agent åt gången och manuell granskning efter varje körning**. Först när det fungerar stabilt skulle jag lägga upp en större kö eller öka parallelliteten.

Arbetsfördelningen blir då:

**Du bestämmer uppgiften och acceptanskriterierna → Symphony driver körningen → Codex ändrar och kontrollerar → du godkänner resultatet.**

En överlämning till mänsklig granskning är helt förenlig med OpenAI:s specifikation; en lyckad körning behöver inte betyda att ärendet automatiskt ska bli `Done`. 

## 3. Börja med den provkörning som redan finns i ditt repo

Ditt repo innehåller redan ett lämpligt första test. Uppgiften `DEMO-1` ber Codex skapa `GREETING.md` med en välkomsttext och kontrollera innehållet. Exempelflödet skapar ett tomt Git-repo i ärendets arbetskatalog. **Det arbetar alltså inte på ditt befintliga projekt.** 

### Bygg och kontrollera miljön

För Windows/PowerShell, från roten i `Symphony-Eiffel`, finns följande dokumenterade kommandon:

```powershell
ec -version
codex --version

# Behövs om du inte redan har en aktuell byggd version.
.\scripts\build.ps1
.\scripts\test.ps1
.\scripts\integration-test.ps1
```

Kör dem stegvis och gå inte vidare med ett bygg- eller testfel. Körmiljön behöver även Bash och en installerad, autentiserad Codex CLI. På Windows nämner ditt repo Git for Windows som vanlig källa till Bash. 

### Validera först, kör därefter ett uppdrag

```powershell
$symphony = ".\.build\eiffel\EIFGENs\symphony\W_code\symphony.exe"

# Kontrollerar konfigurationen utan att starta Codex.
& $symphony --validate .\examples\WORKFLOW.md

# Gör en urvals-/startomgång och inväntar arbetet som startades.
& $symphony --once .\examples\WORKFLOW.md
```

`--validate` skapar inga arbetskataloger och kör inga hooks eller Codex-sessioner. **`--once` är däremot en riktig Codex-körning**, när det finns ett körbart ärende. 

Kontrollera därefter att `GREETING.md` faktiskt skapades och att innehållet motsvarar uppdraget. Ett normalt programavslut är inte i sig ett godkännande av arbetsresultatet.

**En viktig versionsdetalj:** din README anger att app-server-schemat verifierats mot `codex-cli 0.130.0-alpha.5`, och säger uttryckligen att alla Codex-versioner inte garanteras fungera. Kontrollera därför protokollkompatibiliteten vid uppgradering, snarare än att förutsätta att senaste CLI alltid passar den byggda klienten. 

## 4. Koppla sedan flödet till ett riktigt projekt

Det viktigaste steget efter demonstrationen är att **låta arbetskatalogen innehålla projektets riktiga kod**.

Gör en egen konfigurationskatalog, exempelvis `pilot`, och kopiera dit `examples/WORKFLOW.md` och `examples/issues.json`. Då kan du behålla originalexemplen oförändrade.

### Hämta projektets kod i startåtgärden

I kopian av `WORKFLOW.md` ersätter du `git init` i `hooks.after_create` med kloning av det projekt som uppgifterna gäller.

För en första pilot kan Symphony arbeta på en separat kopia av sitt eget repo. Följande är ett **föreslaget Windows-exempel**, inte en ändring jag har gjort i ditt repo:

```yaml
workspace:
  root: C:/SymphonyWorkspaces/pilot

hooks:
  timeout_ms: 60000

  after_create: |-
    git clone https://github.com/andersoxie/Symphony-Eiffel.git .
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  before_run: |-
    git status --short

  after_run: |-
    git status --short
```

Behåll tills vidare exempelfilens övriga inställningar, särskilt en samtidig agent, `max_turns: 1` och sandbox-inställningarna. Din implementation kör `after_create` endast för en ny arbetskatalog; den klonar därför inte om projektet inför varje försök. Hooks körs dessutom på värddatorn, separat från Codex-sandboxen, så granska alltid deras innehåll. 

### Lägg in ett avgränsat uppdrag

Ersätt innehållet i pilotens `issues.json` med exempelvis:

```json
{
  "issues": [
    {
      "id": "pilot-001",
      "identifier": "PILOT-1",
      "title": "Dokumentera kontroll efter installation",
      "description": "Skapa docs/SMOKE_TEST.md med en kort instruktion för att kontrollera en installation av Symphony-Eiffel. Utgå från README.md och befintliga scripts. Beskriv validering och en engångskörning. Ändra inga befintliga filer. Läs tillbaka dokumentet och kontrollera att filnamn och kommandon stämmer med repot. Skilj tydligt mellan kontroller du faktiskt har kört och kontroller som bara beskrivs.",
      "state": "Todo",
      "labels": ["symphony"],
      "dispatchable": true
    }
  ]
}
```

Formatet följer din JSON-adapter. Kombinationen av aktiv status, rätt etikett och `dispatchable: true` gör ärendet valbart i exempelflödet. 

I Markdown-delen av `WORKFLOW.md` skulle jag också lägga till denna instruktion för piloten:

> Läs projektets AGENTS.md om den finns. Genomför endast det angivna uppdraget. Gör ingen commit, push, merge eller driftsättning. Lämna ändringarna för manuell granskning. Skriv en kort RESULTAT.md med ändrade filer, faktiskt utförda kontroller och eventuella hinder.

Kör sedan:

```powershell
& $symphony --validate .\pilot\WORKFLOW.md
& $symphony --once .\pilot\WORKFLOW.md
```

Det ger dig ett första verkligt uppdrag mot ett befintligt projekt, utan att automatiskt publicera förändringar.

## 5. Den viktigaste driftsfrågan: när ska Symphony sluta arbeta?

**I din nuvarande implementation betyder ”Codex är färdig med en körning” inte att ärendet automatiskt får en ny status.**

JSON-adaptern är skrivskyddad ur Symphonys perspektiv. I kontinuerlig drift schemalägger körlogiken dessutom en fortsättning efter en lyckad körning, och kan starta igen om ärendet fortfarande är aktivt och körbart. `max_turns: 1` begränsar alltså inte det totala antalet körningar för ett ärende under tjänstens livstid. 

Jag föreslår därför följande enkla statusmodell:

| Status | Avsikt | Körbart? |
|---|---|---|
| `Backlog` | Uppgiften behöver förtydligas eller prioriteras. | Nej |
| `Todo` | Du har godkänt uppgiften för bearbetning. | Ja |
| `In Progress` | Arbetet pågår eller behöver fortsätta. | Ja |
| `Review` | Resultatet väntar på din granskning. | Nej |
| `Done` | Resultatet är godkänt och säkrat. | Nej; arbetskatalogen kan städas bort. |

Detta är mitt föreslagna arbetssätt. Statusövergångarna är **inte automatiskt implementerade** genom att du använder dessa namn. Exempelflödet har redan `Todo` och `In Progress` som aktiva statusar, medan `Done` är terminal. 

Under piloten gör du därför följande manuellt efter att `--once` avslutats:

Ändra ärendet till `"state": "Review"` och `"dispatchable": false` innan nästa körning. Granska därefter ändringarna och kontrollresultaten.

**Sätt inte `Done` innan resultatet är sparat utanför den tillfälliga arbetskatalogen eller incheckat och säkrat i Git.** Din kod har uttrycklig städning av arbetskataloger för terminala ärenden, bland annat vid uppstart. En lokal commit som bara finns i den arbetskatalogen är inte tillräckligt skydd mot att katalogen tas bort. 

## 6. Hur jag skulle bygga vidare för dig

Eftersom du redan arbetar med Jira, GitHub och Jenkins skulle jag på sikt sikta på detta arbetsflöde:

**Jira-ärende → Symphony/Codex → ändringsförslag och tester → GitHub-PR → din granskning → godkänd integration.**

Men jag skulle **inte börja med att bygga om Symphony-kärnan**. Din nuvarande JSON-adapter ger en möjlig första integrationspunkt. Min rekommendation är en liten separat integrationsdel som hämtar godkända Jira-ärenden, skriver dem till `issues.json` och återrapporterar resultatet.

Det behöver vara en koppling i båda riktningarna: enbart export från Jira till JSON löser inte överlämningen till granskning. Den delen måste också veta när arbetet ska stoppas, hur resultatet sparas och vilket ärende en PR tillhör. Din README beskriver både extern uppdatering av JSON-filen och att nätverksadaptrar och skrivverktyg ännu saknas. 

För den fortsatta användningen skulle jag börja med dokumentation och tester i ett av dina utvecklingsprojekt. Därefter mindre felrättningar. Automatisk merge, driftsättning och ändringar med stora följdverkningar skulle jag hålla utanför den första fasen.

**Mitt konkreta råd är alltså: kör först `DEMO-1` med `--once`, därefter ett riktigt men litet ärende mot en klon av projektet. När du har fått hela kedjan — uppdrag, körning, resultat och granskning — att fungera, är nästa värdefulla steg statusåterrapportering och Jira-koppling, inte fler parallella agenter.**
