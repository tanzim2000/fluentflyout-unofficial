# FluentFlyout Unofficial — Pipeline Flowchart

One diagram per job in `.github/workflows/FluentFlyout Unofficial Publication Script.yml`, in the order they run. Steps flow left to right within each job; the jobs themselves follow top to bottom down this page.

Wherever the maintainer gets a phone notification, it's drawn as a **📱 Notify** step (these all go out through ntfy).

## 1. Check for a new version

Decides whether there's anything new worth building at all.

```mermaid
flowchart LR
    A(["Runs every 6 hours,<br/>or when started by hand"]) --> B["Ask FluentFlyout for its<br/>newest official version"]
    B --> C["Check the newest version<br/>this project already built"]
    C --> D{"Is there a newer one,<br/>or was a rebuild<br/>forced by hand?"}
    D -- "No" --> Stop(["Stop — nothing<br/>new to do"])
    D -- "Yes" --> E{"Is this a brand-new<br/>version (not a<br/>forced repeat)?"}
    E -- "Yes" --> F["📱 Notify:<br/>new version found"]
    E -- "No" --> G
    F --> G(["Start building"])
```

## 2. Build the app

Runs twice at the same time — once for regular PCs, once for ARM devices.

```mermaid
flowchart LR
    A["Download FluentFlyout's<br/>source code<br/>at that version"] --> B["Stamp it with this<br/>project's own identity"]
    B --> C["Add a credit note on the<br/>app's About screen"]
    C --> D{"Did the credit note<br/>get added?"}
    D -- "No" --> Fail(["Stop everything!"])
    D -- "Yes" --> E["Compile the app"]
    E --> F(["Hand the finished<br/>app to the next step"])
```

## 3. Sign the app

Signing is what lets Windows trust the app came from this project unmodified.

```mermaid
flowchart LR
    A["Collect both versions<br/>(regular PC + ARM)"] --> B["Sign each version<br/>separately"]
    B --> C["Record a fingerprint<br/>for every file"]
    C --> D["Note which source code<br/>this was built from"]
    D --> E(["Hand the signed<br/>app onward"])
```

## 4. Build the easy installer

The one-click `.exe` most people will actually download.

```mermaid
flowchart LR
    A["Set up the<br/>installer tool"] --> B["Build the one-click<br/>installer"]
    B --> C(["Hand the installer<br/>onward"])
```

## 5. Test that it actually installs

The most important job — this decides whether anything gets released, and in what form.

```mermaid
flowchart LR
    A["Collect the signed app<br/>and the installer"] --> B["Install the app itself<br/>on a real test PC"]
    B --> C{"Did the app<br/>install cleanly?"}
    C -- "No" --> Fail["📱 Notify:<br/>tests failed"]
    Fail --> FailEnd(["Cancel the<br/>whole release"])
    C -- "Yes" --> D["Run the one-click<br/>installer on a test PC"]
    D --> E["📱 Notify:<br/>test results"]
    E --> F(["Hand off to<br/>publishing"])
```

## 6. Publish to GitHub

```mermaid
flowchart LR
    A["Collect the<br/>signed app"] --> B{"Did the one-click<br/>installer pass<br/>its test?"}
    B -- "Yes" --> C["Include the<br/>installer too"]
    B -- "No" --> D["Leave the<br/>installer out"]
    C --> E["Publish the release<br/>on GitHub"]
    D --> E
    E --> F{"Was the installer<br/>included?"}
    F -- "Yes" --> G(["Full public release"])
    F -- "No" --> H(["Early-access release<br/>(app only)"])
```

## 7. Publish to Chocolatey

Chocolatey is the auto-updating install option. This job only runs if the one-click installer passed *and* Chocolatey publishing was turned on.

```mermaid
flowchart LR
    A["Work out the<br/>version number<br/>to publish"] --> B["Bundle it for<br/>Chocolatey"]
    B --> C["Upload it to<br/>Chocolatey"]
    C --> D{"Was the upload<br/>accepted?"}
    D -- "No" --> Fail(["Hand the failure<br/>to the final report"])
    D -- "Yes" --> E["Keep checking until it<br/>actually appears<br/>(up to 3 minutes)"]
    E --> F{"Did it show up<br/>in time?"}
    F -- "Yes" --> G(["Confirmed live"])
    F -- "No" --> H(["Hand the failure<br/>to the final report"])
```

## 8. Send the final report

Always runs last, whatever happened, and sends the maintainer one summary notification.

```mermaid
flowchart LR
    A{"Did the app fail<br/>its install test?"} -- "Yes" --> R1["📱 Release cancelled"]
    A -- "No" --> B{"Did the GitHub<br/>release work?"}
    B -- "No" --> R2["📱 GitHub<br/>publish failed"]
    B -- "Yes" --> C{"Was Chocolatey<br/>publishing<br/>turned on?"}
    C -- "No" --> R3["📱 Published<br/>(Chocolatey skipped)"]
    C -- "Yes" --> D{"Did Chocolatey<br/>confirm it's live?"}
    D -- "Yes" --> R4["📱 Published &<br/>confirmed live"]
    D -- "No" --> R5["📱 Chocolatey<br/>publish failed"]
```
