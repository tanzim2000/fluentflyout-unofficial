# FluentFlyout Unofficial — Pipeline Flowchart

One diagram per job in `.github/workflows/FluentFlyout Unofficial Publication Script.yml`, in the order they run. Steps flow left to right within each job; the jobs themselves follow top to bottom down this page.

Wherever the maintainer gets a phone notification, it's drawn as a **📱 Notify** step (these all go out through ntfy).

## 1. Check for a new version

Decides whether there's anything new worth building at all.

```mermaid
flowchart LR
    A(["Runs every 6 hours, or when started manually"]) --> B["Ask FluentFlyout for its newest official version"]
    B --> C["Check the newest version this project already built"]
    C --> D{"Is there a newer one, or was a rebuild forced by hand?"}
    D -- "No" --> Stop(["Stop! Nothing new to do."])
    D -- "Yes" --> E{"Is this a brand-new version (not a forced repeat)?"}
    E -- "Yes" --> F["📱 Notify: new version found"]
    E -- "No" --> G
    F --> G(["Start building"])
```

## 2. Build the app

Runs twice at the same time — once for regular PCs, once for ARM devices.

```mermaid
flowchart LR
    A["Download FluentFlyout's source code at that version"] --> B["Stamp it with this project's own identity"]
    B --> C{"Did the credit note get added?"}
    C -- "No" --> Fail(["Stop everything!"])
    C -- "Yes" --> D["Compile the app"]
    D --> E(["Hand the finished app to the next step"])
```

## 3. Sign the app

Signing is what lets Windows trust the app came from this project unmodified.

```mermaid
flowchart LR
    A["Collect both versions (x64 + arm64)"] --> B["Sign each version separately"]
    B --> C["Record a fingerprint for every file"]
    C --> D["Note which source code this was built from"]
    D --> E(["Hand the signed app onward"])
```

## 4. Build the easy installer

The one-click `.exe` most people will actually download.

```mermaid
flowchart LR
    A["Set up the installer tool"] --> B["Build the one-click installer"]
    B --> C(["Hand the installer onward"])
```

## 5. Test that it actually installs

The most important job — this decides whether anything gets released, and in what form.

```mermaid
flowchart LR
    A["Collect the signed app and the installer"] --> B["Install the app itself on a real test PC"]
    B --> C{"Did the app install cleanly?"}
    C -- "No" --> Fail["📱 Notify: tests failed"]
    Fail --> FailEnd(["Cancel the whole release"])
    C -- "Yes" --> D["Run the one-click installer on a test PC"]
    D --> E["📱 Notify: test results"]
    E --> F(["Hand off to publishing"])
```

## 6. Publish to GitHub

```mermaid
flowchart LR
    A["Collect the signed app"] --> B{"Did the one-click installer pass its test?"}
    B -- "Yes" --> C["Include the installer too"]
    B -- "No" --> D["Leave the installer out"]
    C --> E["Publish the release on GitHub"]
    D --> E
    E --> F{"Was the installer included?"}
    F -- "Yes" --> G(["Full public release"])
    F -- "No" --> H(["Early-access release (app only)"])
```

## 7. Publish to Chocolatey

Chocolatey is the auto-updating install option. This job only runs if the one-click installer passed *and* Chocolatey publishing was turned on.

```mermaid
flowchart LR
    A["Work out the version number to publish"] --> B["Bundle it for Chocolatey"]
    B --> C["Upload it to Chocolatey"]
    C --> D{"Was the upload accepted?"}
    D -- "No" --> Fail(["Hand the failure to the final report"])
    D -- "Yes" --> E["Keep checking until it actually appears (up to 3 minutes)"]
    E --> F{"Did it show up in time?"}
    F -- "Yes" --> G(["Confirmed live"])
    F -- "No" --> H(["Hand the failure to the final report"])
```

## 8. Send the final report

Always runs last, whatever happened, and sends the maintainer one summary notification.

```mermaid
flowchart LR
    A{"Did the app fail its install test?"} -- "Yes" --> R1["📱 Release cancelled"]
    A -- "No" --> B{"Did the GitHub release work?"}
    B -- "No" --> R2["📱 GitHub publish failed"]
    B -- "Yes" --> C{"Was Chocolatey publishing turned on?"}
    C -- "No" --> R3["📱 Published (Chocolatey skipped)"]
    C -- "Yes" --> D{"Did Chocolatey confirm it's live?"}
    D -- "Yes" --> R4["📱 Published & confirmed live"]
    D -- "No" --> R5["📱 Chocolatey publish failed"]
```
