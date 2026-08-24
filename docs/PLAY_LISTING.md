# Google Play listing — AI Boxing Coach

Draft copy + the Data Safety answers, grounded in what the app actually does.
Character limits are Play's; counts are approximate — check in the Console.

Package: `com.aiboxingcoach.boxing_coach` · Website: https://aicornerman.com
Privacy: https://aicornerman.com/privacy.html

---

## App title (max 30)
```
AI Boxing Coach
```

## Short description (max 80)
```
Record a round. AI reads your technique and tells you exactly what to fix.
```

## Full description (max 4000)
```
Train alone. Get feedback like someone was watching.

AI Boxing Coach turns your phone into a technique coach. Prop it up, box a round,
and the app reads your movement and tells you — in plain language — what to fix.
No gym, no rig, no wearables.

WHAT IT SEES
• Guard — hands dropping after the cross, a lazy return, gaps that leave you open
• Stance & balance — foot position, width and weight, so your base works for you
• Punch mechanics — extension, hip rotation and how the hand recovers
• Movement — head movement and body positioning through the whole round
• Progress — whether the habits you're grooving are actually improving over time

HOW IT WORKS
1. Record — front camera, no mic, no setup. Just train.
2. Analyse — pose estimation runs ON YOUR DEVICE and flags the technical issues.
3. Improve — get a specific correction and take it straight into the next round.

BUILT FOR REAL TRAINING
Works shadowboxing in the living room, on the heavy bag in the garage, or outside
in the park. Pick your stance, guard style and the school you train toward, and
every round is judged in that game.

FREE TO START
The free tier includes 3 detailed AI analyses per week, plus core technique
feedback and session tracking. No account setup hoops — sign in and train.

PRIVATE BY DESIGN
Your round video is analysed on your device and isn't uploaded — it stays on your
phone. You can delete your account and all your data any time, right in the app.

A NOTE ON SAFETY
AI Boxing Coach gives informational technique feedback — it isn't a substitute
for a qualified coach or medical advice. Boxing carries a risk of injury; warm up,
train within your ability, and consult a professional before starting a new
programme.

More feedback. More often. Your next round should teach you something.
```

## What's new (release notes, max 500)
```
First release. Record a round and get AI technique feedback on your guard,
stance, punch mechanics and footwork — plus progress tracking over time. 3 free
detailed analyses a week. Thanks for testing — tell us what the coach gets right
and wrong.
```

---

## Categorisation
- Category: **Health & Fitness** (alt: Sports)
- Tags: boxing, training, technique, fitness, coaching
- Contact email: phisoluciones.es@gmail.com
- Website: https://aicornerman.com
- Privacy policy: https://aicornerman.com/privacy.html

## Store assets still needed (you provide)
- **App icon** 512×512 (have `ic_launcher` in-app; export a 512 version)
- **Feature graphic** 1024×500 (can adapt `website/assets/og.svg` styling)
- **Phone screenshots** ≥2 (min 320px; use the real in-app screens — recording,
  a round's feedback, the progress/trends view)
- Short promo video (optional but strong — a 15–30s record→feedback loop)

---

## Data Safety form — answers

Declare truthfully; the app collects the following.

**Data collected & why**
| Data type | Collected | Shared* | Purpose | Optional? |
|-----------|-----------|---------|---------|-----------|
| Email address | Yes | No | Account management, app functionality | Required (account) |
| Photos/Videos (keyframe images of the user) | Yes | **Yes** | App functionality (AI coaching) | Required for AI modes |
| App activity (analyses, in-app actions) | Yes | No | App functionality, analytics | Required |
| App info & performance (diagnostics) | Optional | No | Debugging | Optional |

\* **Shared = Yes** for the keyframe images because the AI coaching modes send
frames to a third-party model provider (Google, Gemini) to generate feedback.
The round **video** itself is processed on-device and is NOT collected/uploaded —
don't declare it as collected.

**Security answers**
- Is data encrypted in transit? **Yes** (HTTPS/TLS).
- Can users request data deletion? **Yes** — in-app (Profile → Account → Delete
  account & data) and via https://aicornerman.com/delete-account.html.
- Do you follow the Families policy? N/A (not directed at children; 16+).

**Also required in Console**
- Content rating questionnaire (IARC) — no objectionable content; it's a fitness
  app. Expect Everyone / PEGI 3.
- App access: if reviewers need a login, provide a test account, or note that
  core recording works signed-out and AI needs sign-in.
- Target audience: adults / 18+ or 16+ (matches the Terms age gate).

## Closed testing note (personal account)
This account needs **12 testers opted in for 14 continuous days** before you can
apply for production. Recruit via the beta waitlist + boxing communities; each
tester must accept the invite and install under the matching Google account.
```
