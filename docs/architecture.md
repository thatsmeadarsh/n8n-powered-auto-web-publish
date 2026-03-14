# Architecture Documentation

> A seamless integration of n8n workflow automation with GitHub Actions CI/CD -- turning a single `git push` into a live blog post with an AI-crafted LinkedIn announcement, all without manual intervention.

---

## High-Level Architecture

At a glance, the system transforms a markdown file into a published blog post and LinkedIn announcement through two sequential systems working in concert:

```mermaid
graph LR
    A["Author pushes to Hugo repo"] --> C["GitHub Repository"]
    C --> E["GitHub Actions CI/CD"]
    E --> F["Live Website"]
    F -->|"GitHub webhook"| D["n8n Workflow Engine"]
    D --> G["AI Content Generation"]
    G --> H["LinkedIn Post"]

    style A fill:#99ccff,stroke:#333
    style F fill:#99ff99,stroke:#333
    style H fill:#99ff99,stroke:#333
```

| Layer | System | Responsibility |
|---|---|---|
| **Build & Deploy** | GitHub Actions | Hugo build, static site deployment |
| **Event Detection** | GitHub Webhook | Notifies n8n when the Pages repo receives deployed content |
| **AI & Social** | n8n + Hugging Face + LinkedIn | Fetch post, AI summary generation, social publishing |

**The key insight**: GitHub webhooks act as the **event bridge** -- the Pages repo push (deployment complete) triggers n8n to fetch the post content, generate an AI summary, and publish to LinkedIn. The LinkedIn post only goes out after the site is live.

---

## High-Level System Flow

```
                    ┌─────────────────────────────────────────────┐
                    │            AUTHOR'S MACHINE                  │
                    │                                              │
                    │   1. Write markdown post                     │
                    │   2. git add + commit + push                 │
                    │                                              │
                    └──────────────────┬───────────────────────────┘
                                       │
                              git push │
                                       │
                    ┌──────────────────▼───────────────────────────┐
                    │          GITHUB CLOUD                         │
                    │                                               │
                    │   ┌─────────────────────┐                     │
                    │   │  GitHub Actions      │                    │
                    │   │  Hugo Build + Deploy │                    │
                    │   └──────────┬──────────┘                     │
                    │              │                                 │
                    │     push to Pages repo                        │
                    │              │                                 │
                    │   ┌──────────▼──────────┐                     │
                    │   │  GitHub Pages        │──── Website Live    │
                    │   └──────────┬──────────┘                     │
                    │              │                                 │
                    │     webhook fires                             │
                    │              │                                 │
                    └──────────────┼────────────────────────────────┘
                                   │
                    ┌──────────────▼────────────────────────────────┐
                    │          n8n (Docker + Tunnel)                 │
                    │                                               │
                    │   Detect new posts → Fetch markdown           │
                    │   → AI summary → LinkedIn publish             │
                    │                                               │
                    └──────────────┬────────────────────────────────┘
                                   │
                    ┌──────────────▼──────────┐
                    │     LinkedIn Feed        │
                    │     (AI-Generated Post)  │
                    └─────────────────────────┘
```

---

## Low-Level Architecture

### Complete System Component Diagram

```mermaid
graph TB
    subgraph GitHub["GitHub Cloud"]
        subgraph HugoRepo["whataboutadarsh repo"]
            SRC[content/posts/*.md]
            GA[GitHub Actions Workflow<br/>hugo.yml]
        end
        subgraph PagesRepo["thatsmeadarsh.github.io repo"]
            HTML[Static HTML files]
            PA[GitHub Pages Action<br/>Deploy to Pages]
            GWH[GitHub Webhook<br/>push event]
        end
    end

    subgraph Tunnel["Tunnel (ngrok / Cloudflare)"]
        TN[HTTPS Tunnel<br/>Public URL → localhost:5678]
    end

    subgraph Docker["Docker Container"]
        subgraph n8n["n8n v2.11.4"]
            GT[GitHub Push Trigger<br/>Listens for push events]
            ES[Extract New Post Slugs<br/>Parse commit file list]
            FM[Fetch Post Markdown<br/>GET raw from source repo]
            PF[Parse Frontmatter<br/>Extract metadata]
            DC{Draft Check}
            PR[Prepare HF Request<br/>Build AI prompt]
            HF[HTTP Request<br/>HuggingFace API]
            FL[Format LinkedIn Post<br/>Extract AI text]
            GL[HTTP Request<br/>LinkedIn Profile]
            PL[Prepare LinkedIn Post<br/>Build UGC body]
            LI[HTTP Request<br/>LinkedIn Publish]
            SK[Skip - Draft]
        end
    end

    subgraph APIs["External APIs"]
        HFA[Hugging Face Router<br/>SambaNova Provider<br/>Meta-Llama-3.1-8B]
        LIA[LinkedIn API<br/>OAuth2 + UGC Posts]
    end

    subgraph Output["Published Outputs"]
        WEB["thatsmeadarsh.github.io<br/>Live Blog Post"]
        LIP["LinkedIn Feed<br/>AI-Generated Announcement"]
    end

    SRC -->|triggers| GA
    GA -->|hugo build + push| HTML
    HTML -->|triggers| PA --> WEB
    PA -->|push event| GWH
    GWH -->|webhook POST| TN --> GT
    GT --> ES --> FM
    FM -->|GET raw markdown| SRC
    FM --> PF --> DC
    DC -->|not draft| PR --> HF
    DC -->|draft| SK
    HF -->|API call| HFA
    HFA -->|response| FL
    FL --> GL -->|fetch profile| LIA
    GL --> PL --> LI -->|publish| LIA
    LIA --> LIP

    style GitHub fill:#f0f0f0,stroke:#333
    style Tunnel fill:#ffe6cc,stroke:#e8a020
    style Docker fill:#fff3e6,stroke:#e8a020
    style APIs fill:#e6ffe6,stroke:#4a9e4a
    style Output fill:#ffe6f0,stroke:#c84a86
```

---

### Low-Level: GitHub Actions Pipeline

The `whataboutadarsh` repo contains a GitHub Actions workflow that triggers on every push to `main`. This is the **build and deploy** engine.

```mermaid
graph TD
    subgraph Trigger["Trigger"]
        T[Push to main branch]
    end

    subgraph Build["Build Phase"]
        CO[Checkout code<br/>with submodules]
        HS[Setup Hugo<br/>latest extended]
        DL[Download Contentful JSON<br/>services data]
        CD[Commit data folder]
        PD[Push data changes]
        RC[Delete Hugo cache<br/>resources/_gen]
        HB[Run: hugo<br/>Generate static site]
        CP[Commit public folder]
        PP[Push public changes]
    end

    subgraph Deploy["Deploy Phase"]
        CL[Clone thatsmeadarsh.github.io]
        RM[Clear target repo]
        CY[Copy public/* to target]
        CM[Commit site content]
        PS[Push to GitHub Pages repo]
    end

    subgraph Live["Auto-Triggered"]
        PA[GitHub Pages Action<br/>in thatsmeadarsh.github.io]
        WB[Website Goes Live]
        WH[GitHub Webhook fires<br/>push event to n8n]
    end

    T --> CO --> HS --> DL --> CD --> PD
    PD --> RC --> HB --> CP --> PP
    PP --> CL --> RM --> CY --> CM --> PS
    PS -->|push triggers| PA --> WB
    PA -->|push event| WH

    style Trigger fill:#ff9999,stroke:#333
    style Build fill:#99ccff,stroke:#333
    style Deploy fill:#ffcc66,stroke:#333
    style Live fill:#99ff99,stroke:#333
```

**Key Details**:

| Step | Action | Purpose |
|---|---|---|
| Checkout | `actions/checkout@v3` with submodules | Fetches Hugo theme as git submodule |
| Contentful | `curl` to Contentful CDN | Downloads latest services data for the Services page |
| Hugo Build | `hugo` command | Compiles markdown + Ananke theme into static HTML |
| Cross-Repo Push | `git push` with PAT | Pushes built HTML to the GitHub Pages repository |
| Authentication | `PERSONAL_ACCESS_TOKEN` secret | Enables cross-repository push access |
| Webhook | GitHub webhook on Pages repo | Notifies n8n that deployment is complete |

### Low-Level: n8n Workflow Pipeline

The n8n workflow handles everything after deployment -- detecting new posts, fetching content, AI generation, and social media publishing.

```mermaid
graph TD
    subgraph Detection["1. Detection"]
        GT[GitHub Push Trigger<br/>Receives push webhook from Pages repo]
        ES[Extract New Post Slugs<br/>Filter commits for new posts/*]
    end

    subgraph Fetch["2. Content Fetch"]
        FM[Fetch Post Markdown<br/>GET raw .md from Hugo source repo]
        PF[Parse Frontmatter<br/>Regex extracts TOML metadata]
    end

    subgraph Validation["3. Validation"]
        DC{draft === false?}
        SK[Skip Node<br/>No LinkedIn for drafts]
    end

    subgraph AIGeneration["4. AI Content Generation"]
        PR[Prepare HF Request<br/>Builds chat prompt with:<br/>- title, tags, excerpt<br/>- formatting instructions]
        HF[HuggingFace API Call<br/>POST router.huggingface.co<br/>SambaNova / Llama 3.1]
        FL[Format Response<br/>Extract text from choices<br/>Fallback if AI fails]
    end

    subgraph LinkedInPublish["5. LinkedIn Publishing"]
        GL[Get Profile<br/>GET /v2/userinfo<br/>Returns person URN]
        PL[Prepare Post Body<br/>Build UGC schema with:<br/>- author URN<br/>- AI commentary<br/>- article link + title]
        LI[Publish Post<br/>POST /v2/ugcPosts<br/>Public visibility]
    end

    GT --> ES --> FM --> PF --> DC
    DC -->|true| PR
    DC -->|false| SK
    PR --> HF --> FL
    FL --> GL --> PL --> LI

    style Detection fill:#e6f3ff,stroke:#4a86c8
    style Fetch fill:#f0f0e6,stroke:#999
    style Validation fill:#fff3e6,stroke:#e8a020
    style AIGeneration fill:#e6ffe6,stroke:#4a9e4a
    style LinkedInPublish fill:#ffe6f0,stroke:#c84a86
```

---

## System Flow Diagram (PlantUML)

```plantuml
@startuml
!theme plain
skinparam backgroundColor #FFFFFF
skinparam sequenceMessageAlign center
skinparam responseMessageBelowArrow true

title End-to-End Auto-Publish System Flow

actor Author as author
participant "Git CLI" as git
participant "GitHub\nwhataboutadarsh" as hugorepo
participant "GitHub Actions\nCI/CD" as actions
participant "GitHub\nthatsmeadarsh.github.io" as pagesrepo
participant "GitHub Pages\nCDN" as cdn
participant "GitHub\nWebhook" as ghwh
participant "ngrok\nTunnel" as tunnel
participant "n8n\nGitHub Trigger" as trigger
participant "n8n\nFetch & Parse" as parse
participant "HuggingFace\nSambaNova" as hf
participant "n8n\nFormat Post" as format
participant "LinkedIn\nAPI" as linkedin

== Author Pushes ==
author -> git : git add + commit + push
git -> hugorepo : push to main branch
note right of hugorepo : Push triggers\nGitHub Actions

== Pipeline 1: Build & Deploy ==
hugorepo -> actions : Workflow triggered
activate actions
actions -> actions : Checkout + setup Hugo
actions -> actions : Download Contentful data
actions -> actions : Run hugo build
actions -> pagesrepo : Push built HTML
deactivate actions
pagesrepo -> cdn : GitHub Pages deploys
note right of cdn : Website is live

== Pipeline 2: n8n Detection & Social ==
pagesrepo -> ghwh : Push event fires
ghwh -> tunnel : POST webhook payload
tunnel -> trigger : Forward to localhost:5678
activate trigger
trigger -> parse : Extract new post slugs
parse -> hugorepo : GET raw markdown via GitHub API
hugorepo --> parse : Markdown file content
parse -> parse : Parse frontmatter\nCheck draft status

alt draft = false
    parse -> hf : POST /sambanova/v1/chat/completions\n{system prompt + article context}
    activate hf
    hf --> parse : AI-generated LinkedIn post text
    deactivate hf
    parse -> format : Format response
    format -> linkedin : GET /v2/userinfo
    linkedin --> format : Person URN
    format -> linkedin : POST /v2/ugcPosts\n{author, commentary, article URL}
    linkedin --> format : Post published
    note right of linkedin : LinkedIn post is live\nwith article link preview
else draft = true
    parse -> parse : Skip (no LinkedIn post)
end
deactivate trigger

@enduml
```

---

## Detailed Activity Diagram (PlantUML)

```plantuml
@startuml
!theme plain
skinparam backgroundColor #FFFFFF

title Detailed Activity Flow -- Auto-Publish Pipeline

start

partition "Author Action" {
    :Author writes markdown post;
    :git add + commit + push to main;
}

partition "GitHub Actions Pipeline" #LightBlue {
    :Push triggers GitHub Actions workflow;
    :Checkout repository with submodules;
    :Setup Hugo (latest extended);
    :Download Contentful services.json;
    :Commit data folder;
    :Push data changes;
    :Delete Hugo cache (resources/_gen);
    :Run **hugo** build;
    :Commit public folder;
    :Push public changes;
    :Clone thatsmeadarsh.github.io;
    :Clear target repo;
    :Copy public/* to target;
    :Commit and push to Pages repo;
    note right
        Push triggers GitHub Pages
        deployment workflow
    end note
    :GitHub Pages deploys static files;
    :**Website goes live**;
}

partition "GitHub Webhook" #LightYellow {
    :Push to Pages repo fires webhook;
    :Webhook POST sent to n8n via tunnel;
}

partition "n8n: Detection" #LightGreen {
    :GitHub Push Trigger receives event;
    :Extract commit file list;
    if (New files in posts/*?) then (yes)
        :Extract post slug(s);
    else (no)
        stop
    endif
}

partition "n8n: Content Fetch" #LightGreen {
    :GET raw markdown from Hugo source repo;
    :Parse TOML frontmatter;
    :Extract title, date, tags, slug;
    :Build post URL from slug;
    :Take first 500 words as excerpt;
}

if (draft = false?) then (yes)
    partition "n8n: AI Generation" #LightYellow {
        :Build chat prompt with title, tags, excerpt;
        :POST to HuggingFace SambaNova API;
        :Model: Meta-Llama-3.1-8B-Instruct;
        :Receive AI-generated LinkedIn text;
        if (AI response valid?) then (yes)
            :Extract choices[0].message.content;
        else (no)
            :Use fallback: title + URL + hashtags;
        endif
    }

    partition "n8n: LinkedIn Publishing" #Pink {
        :GET /v2/userinfo (fetch person URN);
        :Build UGC post body with:
        - Author URN
        - AI commentary text
        - Article URL as media
        - Public visibility;
        :POST /v2/ugcPosts;
        :**LinkedIn post published**;
    }
else (draft)
    :Skip (no LinkedIn post for drafts);
endif

stop

@enduml
```

---

## Integration Highlight: n8n + GitHub Actions

> **How we bridged workflow automation with CI/CD to create a zero-touch publishing pipeline**

The power of this architecture lies in how **n8n and GitHub Actions complement each other** without overlap or duplication:

```mermaid
graph TB
    subgraph Bridge["The Bridge: GitHub Webhook"]
        FW["Push to Pages repo triggers n8n<br/>Site is live before LinkedIn post"]
    end

    subgraph GitHubActions["GitHub Actions -- Build & Deploy"]
        direction TB
        GA1["Triggered by: git push to Hugo repo"]
        GA2["Builds Hugo static site"]
        GA3["Deploys to GitHub Pages"]
        GA4["Output: Live website"]
        GA1 --> GA2 --> GA3 --> GA4
    end

    subgraph n8nWorkflow["n8n -- Detection, AI & Social Media"]
        direction TB
        N1["Triggered by: GitHub webhook (push to Pages repo)"]
        N2["Fetches and parses blog content"]
        N3["AI generates LinkedIn summary"]
        N4["Posts to LinkedIn with article link"]
        N1 --> N2 --> N3 --> N4
    end

    GitHubActions -->|"push to Pages repo"| Bridge
    Bridge -->|"webhook POST"| n8nWorkflow

    style Bridge fill:#ffcc66,stroke:#333
    style GitHubActions fill:#e6f3ff,stroke:#4a86c8
    style n8nWorkflow fill:#e6ffe6,stroke:#4a9e4a
```

### Why This Integration Works

| Principle | Implementation |
|---|---|
| **Separation of concerns** | GitHub Actions handles what it's best at (CI/CD, building, deploying). n8n handles what it's best at (API orchestration, AI integration, conditional logic). |
| **No duplication** | Build and deploy happen only in GitHub Actions. AI and social happen only in n8n. Neither system repeats the other's work. |
| **Sequential guarantee** | n8n only fires after the Pages repo receives the deployed content, ensuring the site is live before the LinkedIn post goes out. |
| **Event-driven** | GitHub webhooks provide real-time notification -- no polling, no file watchers, no host dependencies. |
| **Fault isolation** | If LinkedIn posting fails, the website is still live. If GitHub Actions fails, n8n never fires (no premature LinkedIn post). |
| **Zero manual steps** | From pushing a markdown file to a live website + LinkedIn announcement -- no human intervention required. |
| **No host dependencies** | No file watcher, no cron jobs, no background processes on the author's machine. Just `git push`. |

### The Integration Pattern

```
                    ┌─────────────────┐
                    │  Single Event   │
                    │  (git push)     │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  GitHub Actions  │
                    │  Build + Deploy  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  GitHub Webhook  │
                    │  (push to Pages) │
                    └────────┬────────┘
                             │
                    ┌────────▼────────────────┐
                    │  n8n Workflow             │
                    │  ──────────────────       │
                    │  Detect new posts         │
                    │  Fetch markdown content   │
                    │  AI text generation       │
                    │  LinkedIn publishing      │
                    └────────┬─────────────────┘
                             │
                    ┌────────▼────────────────┐
                    │  LINKEDIN POST           │
                    │  AI-crafted summary      │
                    │  with article link       │
                    └─────────────────────────┘
```

This pattern is **reusable** -- the same webhook-driven approach can integrate any CI/CD pipeline with any workflow automation tool, enabling scenarios like:
- Auto-posting to Twitter/X, Mastodon, or other platforms
- Sending email newsletters for new posts
- Triggering SEO indexing via Google Search Console API
- Cross-posting to Medium or Dev.to

---

## Security Architecture

```mermaid
graph LR
    subgraph Secrets["Credential Storage"]
        GS["GitHub Secrets<br/>PERSONAL_ACCESS_TOKEN"]
        NC["n8n Credential Store<br/>GitHub API Token<br/>LinkedIn OAuth2<br/>HuggingFace Header Auth"]
    end

    subgraph Access["Access Scope"]
        GS --> GHA["GitHub: repo + workflow scope"]
        NC --> GTA["GitHub: repo + admin:repo_hook"]
        NC --> LIA["LinkedIn: w_member_social only"]
        NC --> HFA["HuggingFace: Inference only"]
    end

    style Secrets fill:#fff3e6,stroke:#333
    style Access fill:#e6ffe6,stroke:#333
```

| Secret | Location | Scope | Expiry |
|---|---|---|---|
| GitHub PAT (Actions) | GitHub repo secret (`PERSONAL_ACCESS_TOKEN`) | `repo` + `workflow` | Configurable (90 days recommended) |
| GitHub PAT (n8n) | n8n credential store | `repo` + `admin:repo_hook` | Configurable |
| HuggingFace token | n8n credential store | Inference Providers only | No expiry |
| LinkedIn OAuth2 | n8n credential store (encrypted) | `w_member_social` | 2 months (auto-refreshed by n8n) |

### Security Boundaries

- **n8n** runs in Docker locally, exposed only via tunnel for webhook delivery
- **Tunnel** can be restricted to GitHub webhook IPs for additional security
- **n8n** runs with `NODE_TLS_REJECT_UNAUTHORIZED=0` (container-scoped, not host)
- **GitHub PAT** is stored in GitHub's encrypted secrets and n8n's encrypted credential store
- **Webhook secret** can be configured in n8n's GitHub Trigger for payload verification

---

## Design Decisions

| Decision | Rationale |
|---|---|
| **GitHub webhook over file watcher** | Eliminates host dependencies (fswatch, background scripts). Works from any machine that can `git push`. Guarantees site is deployed before LinkedIn post. |
| **Watch Pages repo, not Hugo repo** | Ensures the website is actually live before announcing on LinkedIn. The push to the Pages repo is the last step of deployment. |
| **Fetch markdown from source repo** | The Pages repo only has built HTML. The source repo has the original markdown with frontmatter for AI context. |
| **Tunnel for local n8n** | GitHub webhooks need a public URL. ngrok/Cloudflare Tunnel bridges local n8n to the internet with minimal setup. |
| **GitHub Actions for build/deploy** | Already configured and tested; Hugo + cross-repo push is complex to replicate elsewhere |
| **n8n for detection + AI + social** | Keeps n8n focused on what it excels at: event detection, API orchestration, and conditional logic |
| **HTTP Request nodes over LinkedIn node** | Built-in LinkedIn node doesn't support "Ignore SSL Issues" needed in Docker |
| **Code nodes for JSON construction** | Blog content contains special characters that break inline JSON templates |
| **SambaNova via HuggingFace Router** | Free tier, fast inference, OpenAI-compatible API format |
| **Draft check in n8n** | Allows deploying draft posts to test site rendering without triggering LinkedIn |

---

*Last Updated: 2026-03-14*
*Project: n8n-Powered Auto Web Publish*
