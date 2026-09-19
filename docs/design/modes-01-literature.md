# Phase-Structure Sweep: Evidence-Based Nutrition Periodization for the Mybody Mode System

## 0. Method, and an honest reliability caveat — READ THIS FIRST

**Access limitation.** In this session `WebFetch` returned `EGRESS_BLOCKED` for every scholarly domain (`pmc.ncbi.nlm.nih.gov`, `journals.lww.com`, `link.springer.com`, `tandfonline.com`, `mdpi.com`, `strongerbyscience.com`, `rpstrength.com`, `macrofactor.com`, and every mirror PDF I tried). Direct `curl` through the agent proxy returned `CONNECT tunnel failed, response 403`. **Only `WebSearch` worked.**

That means: I confirmed that each paper below **exists**, its **authors, title, journal and year**, and I have the **search engine's synthesis of its contents**. I did **not** read a single full text. Numbers are therefore graded:

| Grade | Meaning |
|---|---|
| **[A]** | Number appeared consistently across multiple independent search syntheses AND matches the canonical figure this literature is famous for. Safe to build on. |
| **[B]** | Number appeared in search synthesis once, from a plausible source, but I could not cross-check it. Use, but re-verify before it becomes a hard constant. |
| **[unverified]** | Appeared only in a secondary blog/app-marketing summary, or I am reasoning rather than citing. Do not hard-code. |

Anything I could not find at all, I say so rather than filling the gap.

---

## 1. The real taxonomy — what phases actually exist

The owner guessed four names. The literature and evidence-based coaching world does **not** use four. It uses a **two-axis system**: a small set of *energy-balance directions*, and a set of *modifier phases* that sit inside or between them. Conflating these two axes is exactly why "감량 vs 커팅" feels ambiguous.

### 1.1 Axis A — Primary phases (a sustained energy-balance direction; these are real "modes")

| # | Literature name | Korean gym name | Energy balance | Primary intent |
|---|---|---|---|---|
| A1 | **Energy deficit / fat-loss phase** (also "cut", "weight-loss phase") | 다이어트 / 감량 / 커팅 | Deficit | Reduce fat mass |
| A2 | **Energy surplus / muscle-gain phase** — splits into **lean gaining** and **aggressive gaining** | 린매스업 / 벌크업 (클린벌크 vs 더티벌크) | Surplus | Increase lean mass |
| A3 | **Energy balance / maintenance phase** (a.k.a. "weight-stability phase", "post-diet maintenance") | 유지 / 유지어터 | ~Balance | Recover physiology, hold result |
| A4 | **Body recomposition** | 리컴포지션 / **상승다이어트** | Balance to very mild deficit | Simultaneously ↑SMM, ↓BFM |
| A5 | **Contest prep / peaking** | 시합 준비 / 커팅 (선수 맥락) | Deep, terminal deficit | Reach a date at a very low BF% |

### 1.2 Axis B — Modifier phases (they are *not* modes; they are events inside or between A-phases)

| # | Name | Korean | Sits inside | Duration | Function |
|---|---|---|---|---|---|
| B1 | **Refeed** | 리피드 / 치팅과 구분됨 | A1, A5 | 1–2 days/week | Raise carbs at ~maintenance, keep protein, resume deficit |
| B2 | **Diet break** | 다이어트 브레이크 | A1, A5 | 7–14 days | Full return to maintenance, then resume |
| B3 | **Mini-cut** | 미니컷 | Inside A2 | 2–8 weeks | Short aggressive deficit to reset BF% mid-bulk |
| B4 | **Reverse diet** | 리버스 다이어트 | After A1/A5 | 4–12 weeks | Gradual calorie ramp back to maintenance |
| B5 | **Recovery diet** | 회복식 | After A5 | 4–8 weeks | Immediate jump to maintenance/slight surplus |

**This is the single most important structural finding for Mybody:** your engine already has a `a ∈ [0,1]` aggressiveness scalar and a `상/중/하` speed knob. **Axis A maps to modes. Axis B maps to strategy flags and simulation events — not to modes.** If you expose B3 (mini-cut) as a user-selectable mode you will be exposing a tool that is only meaningful *relative to an in-progress bulk*, and a user who picks it cold will get nonsense. Your engine's existing `"split"` strategy (cut → 2wk maintenance → bulk → mini-cut) already encodes B2 and B3 correctly as internal events. Keep them there.

---

## 2. Per-phase parameters, with sources

### A1 — Energy deficit / fat-loss phase

| Parameter | Value | Source | Grade |
|---|---|---|---|
| Rate of weight loss | **0.5–1.0 % BW/week** | Helms, Aragon & Fitschen 2014, *JISSN* 11:20, "Evidence-based recommendations for natural bodybuilding contest preparation: nutrition and supplementation" — stated as "caloric intake should be set at a level that results in bodyweight losses of approximately 0.5 to 1% per week to maximize muscle retention" | **[A]** |
| Rate tie-break | 2-month diet → ~1 %/wk; 4-month diet → ~0.5 %/wk | Korean summary of the same paper on 몬스터짐 (보디빌딩 시합 준비 영양 column): "2개월이면 주당 1%, 4개월이면 주당 0.5%" | **[B]** |
| Empirical support for slow > fast | Garthe et al. 2011, *IJSNEM* 21(2):97 — elite athletes, 0.7 %/wk (19 % energy reduction) vs 1.4 %/wk (30 % energy reduction). **Slow group: LBM +2.1 % ± 0.4 %. Fast group: LBM −0.2 % ± 0.7 %.** Same total mass lost; slow group lost more *fat*. Fast group showed reduced testosterone and increased SHBG. | Garthe 2011 | **[A]** |
| Helms' own framing of Garthe | 1.4 %/wk vs 0.7 %/wk over 4–11 weeks → FM −21 % (fast) vs −31 % (slow); LBM +2.1 % (slow) vs unchanged (fast) | Helms 2014 as summarized | **[A]** |
| Protein | **2.3–3.1 g/kg LBM/day**, "scaled upwards with severity of caloric restriction and leanness" | Helms, Zinn, Rowlands & Brown 2014, *IJSNEM* 24(2):127–138, "A Systematic Review of Dietary Protein During Caloric Restriction in Resistance Trained Lean Athletes: A Case for Higher Intakes". Equivalent stated as **1.8–2.7 g/kg bodyweight** | **[A]** |
| Fat | **15–30 % of calories** (Helms 2014 contest prep); **10–25 % of calories** in deeper contest prep, to leave room for carbs | Helms 2014; "Nutritional Recommendations for Physique Athletes" (PMC7052702) | **[A]** / **[B]** |
| Carbohydrate | Remainder of calories | Helms 2014 | **[A]** |
| Alternative unified rec. | Rate 0.5–1.0 %BW/wk, protein **2.2–3.0 g/kg BW/day** | Ruiz-Castellano et al. 2021, *Nutrients* 13(9):3255, "Achieving an Optimal Fat Loss Phase in Resistance-Trained Athletes: A Narrative Review" | **[B]** |
| Training | Reduce weekly volume ~20–40 %, hold load on compounds ≥80 % 1RM | secondary coaching synthesis | **[unverified]** |
| Training — contradicting RCT | **Roth et al. 2023**, *Scand J Med Sci Sports*, "Resistance training volume does not influence lean mass preservation during energy restriction in trained males." Title is unambiguous. | Roth 2023 | **[A]** (title) |
| Training — contest-prep observation | LM *increased* during first 8 wk when RT volume increased; LM *lost* in final 8 wk when RT volume was reduced | "Lean mass sparing in resistance-trained athletes during caloric restriction: the role of resistance training volume" (PMC9012799) | **[B]** |
| Cardio | Conservative start: **2–3 sessions/wk × 20–30 min MISS**; Helms' position is that cardio can be minimized entirely because fat loss is achievable without it | Helms & Fitschen, "Recommendations for natural bodybuilding contest preparation: resistance and cardiovascular training"; Helms interview | **[B]** |

**Note the direct conflict**: Roth 2023 (RCT) says RT volume doesn't matter for LM preservation in a deficit; the contest-prep observational data says volume reduction coincided with LM loss. The RCT is better evidence. Your mode spec should therefore **not** claim that a deficit mode "preserves muscle by keeping volume high" — say instead it *keeps training hard enough to signal retention*, and let protein and rate do the heavy lifting.

---

### A2 — Energy surplus / muscle-gain phase

| Parameter | Value | Source | Grade |
|---|---|---|---|
| Surplus size | **~10–20 % above maintenance** | Iraki, Fitschen, Espinar & Helms 2019, *Sports* 7(7):154, "Nutrition Recommendations for Bodybuilders in the Off-Season: A Narrative Review" | **[A]** |
| Rate of gain | **0.25–0.5 % BW/week** for novice/intermediate; **more conservative** for advanced | Iraki 2019 | **[A]** |
| Protein | **1.6–2.2 g/kg/day**, 0.40–0.55 g/kg per meal, 3–6 meals/day, incl. 1–2 h pre/post training | Iraki 2019 | **[A]** |
| Fat | **0.5–1.5 g/kg/day** | Iraki 2019 | **[A]** |
| Starting BF% | **Men 10–15 %, women 20–25 %** | Attributed to Eric Helms / 3DMJ, cited in review literature and coaching material | **[B]** |
| Korean equivalent | 린매스업 start: **men 13–18 %, women 18–24 %** | beautypl.com (Korean wellness), "초보 다이어터라면 벌크업 대신 린매스업" | **[B]** |
| Korean vernacular targets | 벌크업 done right = **+0.5–1 kg/month**, **+300–500 kcal over maintenance**, **protein ≥ 2 g/kg BW**, muscle rising faster than fat | Korean coach posts (Threads @charr02__, @tae__ttt); 클린벌크 cited as **+200–300 kcal, 2 g/kg protein** | **[B]** — vernacular, not research |
| Aggressive-gain evidence | The 2013 "more surplus = mostly fat + ↓insulin sensitivity" claim circulating in Korean content is **[unverified]** — I could not identify the underlying study |  | **[unverified]** |

**Lean gaining vs aggressive gaining is a real, defensible split**, but the evidence-based world's position is asymmetric: there is good support for *lean gaining* (0.25–0.5 %BW/wk, 10–20 % surplus) and essentially no support for aggressive gaining being superior. In your engine, this is not two modes — it is **one mode with two ends of `a`**. Aggressive gaining is the high-`a` end of 근성장모드, and it should carry a warning, not a separate tile.

### The p-ratio question (does starting BF% change where the surplus goes?)

- **Forbes (1987)** proposed that baseline body fat is a major determinant of the p-ratio: high baseline BF → mostly fat gain during overfeeding; low baseline BF → mostly lean gain. **[A]** (this is the canonical Forbes position)
- **This is now actively contested.** Greg Nuckols and Eric Trexler (Stronger by Science) published a multi-round exchange — "Should You Cut Before You Bulk?: How Body-Fat Levels Affect Your P-Ratio", then "A Rebuttal To The Rebuttal", then "A Rebuttal To The Rebuttal To The Rebuttal" — against Menno Henselmans, culminating in a live debate hosted by Jeff Nippard. **[A]** (the exchange demonstrably exists at those URLs)
- **Menno Henselmans publicly reversed his position**, in an article literally titled "What's the optimal BF% for bulking? I was WRONG". His revised reasoning includes that excess body fat impairs *recovery capacity*, and that there is a "sweet spot at some level of healthy body fat." **[B]** — I confirmed the article and its title; I could not read the revised numbers.

**Implication for Mybody:** do **not** hard-code a p-ratio adjustment by body fat. It is genuinely disputed among the exact people the owner should trust. Use BF% as an **entry criterion** ("start a gaining phase below X%") rather than a **rate modifier**.

---

### A3 — Energy balance / maintenance phase

| Parameter | Value | Source | Grade |
|---|---|---|---|
| Duration | **4–12 weeks** between diet phases | Coaching synthesis (BlazePod / Kate Lyman Nutrition / RP) | **[B]** |
| Proportional rule | **At least half the length of the preceding diet, up to double it** | Same coaching synthesis | **[B]** |
| Simpler rule | 1–2 months | Same | **[B]** |
| Purpose | Allow leptin, thyroid hormones, reproductive hormones, and training performance — all suppressed by dieting — to recover before the next phase | Same, consistent with Trexler 2014 | **[B]** |

This phase is **underserved by RCT evidence** and well-served by coaching consensus. RP Strength publishes "The Value of Post-Diet Maintenance" and treats maintenance as a first-class phase in a three-phase system (massing / maintenance / fat loss), with mass and cut phases each ~3–6 months and maintenance held 1–3 months depending on the preceding phase length. **[B]**

---

### A4 — Body recomposition

Covered in depth in §3.

---

### A5 — Contest prep / peaking

| Parameter | Value | Source | Grade |
|---|---|---|---|
| Duration, natural | **20–30 weeks** (vs 8–12 for enhanced); "can last upwards of 20 weeks and is associated with hormonal dysregulation" | Contest-prep review literature | **[B]** |
| Testosterone | In a 1-year case study of a natural competitor, T fell to **¼ of baseline** three months into a six-month prep; recovered fully three months into the six-month recovery | Case-study literature (Rossow et al. is the canonical one; I did not verify authorship) | **[B]** |
| Testosterone × rate | **1 kg/wk target loss → ~30 % reduction in testosterone vs 0.5 kg/wk** in normal-weight resistance-trained women | Cited in contest-prep reviews | **[B]** |
| Hormone recovery timeline | Some hormones restored within 12 weeks; **T3, T4 and leptin can remain downregulated for several months** | Contest-prep review | **[B]** |
| Cohort-level magnitude | 19 natural physique athletes over a full cycle: **BW −7.1 kg, FM −5.8 kg, LM −1.7 kg** baseline→pre-competition | "Post-competition recovery in natural physique athletes", *JISSN* 23(1) (2026) | **[B]** |
| RMR | Prep accompanied by fat loss, **thyroid suppression, and modest reductions in RMR**; recovery shows early RMR increases | Same | **[B]** |

**Verdict for Mybody: do not build a 시합모드.** It is a dated, supervised, health-cost-accepting protocol. Your app produces a plan from an InBody sheet for one non-competing owner. A5 belongs in the **documentation as the reason the app refuses `a` above a ceiling**, not as a selectable mode.

---

### B1 — Refeed

- **Campbell et al. 2020**, *J Funct Morphol Kinesiol* 5(1):19, "Intermittent Energy Restriction Attenuates the Loss of Fat Free Mass in Resistance Trained Individuals. A Randomized Controlled Trial." n=27, ~25 % restriction, 4 d/wk RT, 7 weeks. Refeed group = **2 consecutive high-carb days + 5 restricted days each week**. Authors concluded the 2-day refeed **preserved FFM, dry FFM and RMR** vs continuous restriction. **[A]**
- **But**: a formal published comment, "Contrary to the Conclusions Stated in the Paper, Only Dry Fat-Free Mass Was Different between Groups upon Reanalysis" (PubMed 33467300), reanalyzed the data and found the FFM claim did not hold — only *dry* FFM differed. **[A]** (the comment demonstrably exists)

**So the headline refeed finding has a published rebuttal attached to it.** Do not present refeeds to the owner as proven muscle-sparing.

### B2 — Diet break

- **Definition**: a planned **1–2 week** return to maintenance calories inside a longer deficit. **[B]**
- **Byrne et al. 2018 (MATADOR)**, *Int J Obes* — 51 men with obesity, 16 weeks of energy restriction delivered either continuously or as **8 × 2-week restriction blocks alternating with 7 × 2-week energy-balance blocks (30 weeks total)**. Intermittent group achieved **greater weight and fat loss, no greater FFM loss, attenuated REE reduction, and superior weight-loss retention at 6 months**. **[A]**
- **Peos et al. 2021 (ICECAP)**, *Med Sci Sports Exerc* — 61 resistance-trained adults (32 women), mean age 28.7. mIER = four 3-week restriction periods with three 1-week energy-balance periods (15 wk) vs mCER = 12 wk continuous. **Result: no significant between-group differences in fat loss, FFM, strength, muscle endurance gains, or REE.** Secondary analysis (*PLOS One*): the 1-week break itself produced **+0.6 kg BW, +0.7 kg FFM, and a significant REE increase**, but **no significant effect on fat mass**; no difference in fasted leptin or ghrelin. **[A]**
- **2024 meta-analysis**, *Nutrition Reviews* 83(1):59 (PubMed 38193357), "Effects of intermittent dieting with break periods on body composition and metabolic adaptation": **no significant between-group difference for body mass, fat mass, BMI, body-fat %, or waist circumference.** RMR was significantly reduced **following continuous restriction only**; the compensatory RMR drop was **significantly smaller** after intermittent dieting. Critically: **the RMR-retention benefit was more pronounced in overweight/obese individuals than in resistance-trained individuals.** **[A]**

**Synthesis — this is the cleanest finding in the whole sweep:**

> Diet breaks **do not accelerate fat loss**. They **blunt the RMR drop**, and that blunting is **much weaker in trained, leaner people** than in overweight people. MATADOR worked in obese men; ICECAP found nothing in resistance-trained adults. **The population determines whether the break helps.**

This directly informs the engine: the `"split"` strategy's 2-week maintenance block should be justified to the user on **adherence and RMR-preservation** grounds, **not** as "faster." And if the engine's simulation ever shows split beating simultaneous *on speed* for a lean trained user, that result is coming from your muscle-gain situational multipliers, not from diet-break physiology.

### B3 — Mini-cut

| Parameter | Value | Grade |
|---|---|---|
| Duration | **2–8 weeks**; most commonly **4–8 weeks** | **[B]** |
| Deficit | **25–30 % of maintenance**, or ~500–1000 kcal/day below | **[B]** |
| Rate | **~1.0–1.5 % BW/week** — deliberately above the A1 range | **[B]** |
| Fat floor | keep dietary fat **above ~0.3 g/kg**; take the cut from fat and carbs, keep protein high | **[B]** |
| Frequency rule | **at least 1:4 ratio** of dieting weeks to gaining/maintenance weeks — a 4-week mini-cut is followed by ≥16 weeks of progressing | **[B]** |
| Attribution | Recommended for years by Lyle McDonald, Eric Helms, Alan Aragon; Menno Henselmans has a documented PSMF mini-cut protocol | **[B]** |

All mini-cut numbers are **coaching-consensus, not RCT-derived**. I found no trial of mini-cuts specifically. The 1:4 frequency rule is the single most useful constraint here and is the thing your engine should enforce.

### B4 — Reverse diet vs B5 — Recovery diet

This is the sharpest "industry says X, evidence says not-X" case in the sweep.

- **Reverse diet** = gradual weekly calorie increase over several weeks post-diet, claimed to "reverse metabolic adaptation," raise TDEE, and limit fat regain. **[A]** (definition)
- **Recovery diet** (Eric Helms / 3DMJ, published as a 3DMJ Vault course and in two Helms videos) = **immediately raise calories to maintenance or a slight surplus**, replenish glycogen, accept some fat gain, and restore function faster. Recommended regain rate **~0.5–1.5 % BW/month**. **[B]**
- **The evidence**: "There is no scientific evidence that reverse dieting is effective in increasing metabolism or preventing weight regain… no evidence indicating that 'building up' your metabolic rate would make future weight loss meaningfully easier, or would meaningfully reduce the likelihood of weight regain." **[B]** — MacroFactor, "Reverse Dieting: Hype Versus Evidence" (I confirmed the article exists; blocked from reading it)
- **The first actual RCT**: "The effects of reverse dieting on mitigating weight regain after a caloric deficit: a preliminary analysis", *JISSN* 22(sup2) (2025). **49 resistance-trained participants** after 5 % weight loss, randomized to (a) reverse diet — weekly increase of **+8.5 % for males, +11.7 % for females**, (b) immediate return to estimated maintenance, or (c) ad libitum control; followed **15 weeks**. Reported finding: reverse dieters had **higher hunger in early weeks** vs immediate-maintenance, improving as calories rose. **[B]**
- Cleveland Clinic (2024): no evidence reverse dieting "boosts" metabolism beyond normal recovery. **[B]**
- Registered trials confirming the question is live: NCT03434431 ("Can Reverse Dieting Prevent Weight Regain After Weight Loss"), NCT03560635. **[A]**

**Verdict:** build the **recovery diet**, call it 회복/유지 전환, and do **not** ship a "reverse diet" mode that promises metabolic repair.

---

## 3. Body recomposition — who it works for, who it doesn't

### 3.1 The key review: Barakat et al. 2020

**Barakat C, Pearson JR, Escalante G, Campbell BI, De Souza EO. "Body Recomposition: Can Trained Individuals Build Muscle and Lose Fat at the Same Time?" *Strength and Conditioning Journal*, 42(5), October 2020.** **[A]** — existence, authorship, journal and issue all confirmed.

What it concluded, per search synthesis:

1. **Yes, recomposition is possible — including in advanced lifters — but "the variables have to be dialed in."** **[B]**
2. **It is not reserved for beginners or for people carrying excess fat.** It is documented in already-trained subjects, under two conditions: **genuinely progressive resistance training** and **high protein intake**. **[B]**
3. **It occurs most reliably in three populations**: (i) untrained beginners, (ii) individuals returning after detraining, (iii) people with significant body fat who have never resistance-trained. **[B]**
4. **It gets slower and more marginal the more advanced and the leaner you are.** **[B]**
5. Training age *and the novelty of initiating an RT program* both directly affect rate of muscle accrual. **[B]**

Corroborating framing from the field: "It is generally thought that body recomposition occurs mainly in both the untrained/novice and overweight/obese populations." **[B]**

**⚠️ Flag:** The frequently-repeated practical prescription — *"maintenance or a very light deficit (−100 to −200 kcal/day), protein ≥ 2.2 g/kg, strong mechanical stimulus"* — appeared in my searches **only via app-marketing and blog summaries** (micron-app, clinicalnutritionreport), never attributed to a page number in Barakat. It is physiologically sensible and consistent with the review's logic, but **treat the specific "−100 to −200 kcal" figure as [unverified]** and do not present it in-app as "the research says."

### 3.2 Longland et al. 2016 — and why its population matters enormously

**Longland TM, Oikawa SY, Mitchell CJ, Devries MC, Phillips SM. "Higher compared with lower dietary protein during an energy deficit combined with intense exercise promotes greater lean mass gain and fat mass loss: a randomized trial." *Am J Clin Nutr*, 2016. (ClinicalTrials.gov NCT01776359.)** **[A]**

Design confirmed: **40 % energy deficit**, **2.4 g/kg/d vs 1.2 g/kg/d protein**, resistance training plus high-intensity exercise.

Result confirmed: **fat mass −4.8 ± 1.6 kg (high protein) vs −3.5 ± 1.4 kg (control)**. **[A]**
The famous lean-mass result (**~+1.2 kg vs ~+0.1 kg**) is the universally cited figure but did **not** appear verbatim in my search returns — **[unverified]** here, though I have no reason to doubt it.

**The population limits — this is the part the industry systematically omits:**

- Subjects were **young men**, **overweight but previously untrained / recreationally active**, not trained lifters.
- The intervention was **short, fully supervised, with food provided**, and included **six days per week** of prescribed exercise. **[unverified — this is my recollection of the protocol, not something I could confirm in this session; verify before citing]**
- **Therefore**: Longland demonstrates that a *novice, overfat* population can add lean mass in an *aggressive* (40 %) deficit under *total supervision* with *very high protein*. It does **not** demonstrate that a trained, lean person can. It is routinely misquoted as if it did.

**Direct consequence for your engine:** your situational multiplier of **×0.30 for novices in a real (>15 %) deficit** is *exactly* the Longland/Demling finding, correctly scoped. And your **×0.00 for advanced and elite in a real deficit** is defensible precisely because Longland's population cannot be extrapolated to them. **Your engine is already right here.** Don't let a "리컴프모드" undo it.

### 3.3 Demling & DeSanti 2000

Compared 12 weeks of resistance exercise + high-protein diet against dieting alone, in **38 untrained, overweight male police officers (23–35 % body fat)**. Demonstrated significant lean gain alongside fat loss in a deficit. **[B]** — same population caveat as Longland, in the same direction.

### 3.4 Realistic recomposition rates

These come from coaching/app synthesis rather than a single review, so grade **[B]** at best:

| Training stage | Muscle gain rate |
|---|---|
| Intermediate (yr 2–3) | 0.45–0.7 kg/month |
| Advanced (yr 4–7) | 0.2–0.45 kg/month |
| Trained intermediate, *recomping* | 0.5–1.0 kg total over 3–6 months (≈0.1–0.2 kg/month) alongside gradual fat loss |

Note the last row: **recomping costs an intermediate roughly 70–80 % of their surplus-driven gain rate.** That number is the honest price tag for 리컴프모드 and it belongs in the UI.

### 3.5 Who recomposition does NOT work for — a usable exclusion list

Synthesizing Barakat's populations against the rate data:

- **Advanced/elite AND already lean** → the surplus-driven ceiling is already ~0.375/0.175 %BW/month; halving it at maintenance leaves a rate indistinguishable from measurement noise on an InBody. **Recomp is not wrong for them, it is unmeasurable.** This is the strongest argument for your engine refusing to recommend 리컴프모드 to an advanced lean user.
- **Anyone in a hurry with a large BFM to lose** → recomp's near-maintenance energy balance forfeits the fat-loss speed they came for.
- **Anyone at a very low BF% already** → there is no fat to move, and maintenance-level intake at low BF% is where the hormonal costs in §5 start.

---

## 4. Phase duration limits, and how long a deficit can run

### 4.1 Metabolic adaptation — what's real

**Trexler ET, Smith-Ryan AE, Norton LE. "Metabolic adaptation to weight loss: implications for the athlete." *JISSN*, 2014; 11:7.** **[A]**

Stated findings: energy restriction is accompanied by changes in circulating hormones, mitochondrial efficiency and energy expenditure that **minimize the deficit, attenuate weight loss and promote regain**. TDEE falls **by more than body-mass loss predicts**. Adaptive thermogenesis and decreased expenditure **persist after the active weight-loss period, even in subjects who have maintained a reduced weight for over a year**. **[A]**

**Magnitude, though, is modest**: across 33 studies / 2,528 adults, ~82 % found measurable metabolic adaptation, but for people on normal diet-and-exercise programs the cost landed at **30–100 kcal/day**. **[B]**

### 4.2 The practical duration ceiling

There is **no clean RCT answer** to "how long can a deficit run." What exists:

- Helms 2014: diets **longer than two to four months** at 0.5–1 %BW/wk "may be superior for LBM retention compared to shorter or more aggressive diets." **[B]** — i.e., the literature's concern is that diets are too *fast*, not too *long*.
- Contest prep runs **20–30 weeks** in naturals and is explicitly described as "associated with hormonal dysregulation." **[B]** So ~20+ weeks is where the documented endocrine cost shows up.
- Hormonal recovery after a deep prep: some markers restored within 12 weeks; **T3, T4, leptin can stay suppressed for several months**. **[B]**
- Maintenance between phases: **4–12 weeks**, or **half to double the length of the preceding diet**. **[B]**

**A defensible engine rule, stated as reasoning not citation:** cap any continuous deficit phase at **~16 weeks** before forcing a maintenance block, and cap total deficit-phase length at **~24 weeks** absolutely. Rationale: 16 weeks sits inside the well-tolerated range and below the 20-week point where contest-prep endocrine dysregulation is documented; the maintenance block length then follows the half-to-double rule. **[reasoning, not cited]**

### 4.3 Energy-availability floor (a hard safety rail, not a preference)

- **EA < 30 kcal/kg FFM/day** = low energy availability, the clinical cutoff for RED-S / Triad risk in females. **[A]**
- **EA 30–45** = suboptimal; **≥45** = optimal. **[A]**
- **EA < 30** is associated with ~**50 % probability of menstrual dysfunction**; **EA ≤ 20** with functional hypothalamic amenorrhea. **[A]**
- Separately, ISSN has recommended a minimum of **~2,500 kcal/day for athletes**, and fat below **20 % of energy** compromises fat-soluble vitamin and omega-3 availability. **[B]** — the 2,500 figure is population-specific and should **not** be applied to a small female user; treat it as a caution, not a floor.

**This is the single most important thing missing from the engine spec as described.** Your engine has "a calorie floor," but the *correct* floor for a female user is not a kcal number — it is **EA = intake − exercise expenditure, normalized to FFM**, held at **≥30, targeting ≥45**. Since you already compute FFM (`SMM / k`), you can compute EA directly. Recommend making this a hard constraint that clamps `a`.

---

## 5. What the industry says confidently that the evidence does not support

Ranked by how much money and UI real estate the fitness industry spends on each.

### 5.1 "Reverse dieting repairs your metabolism"
**Not supported.** No evidence it increases metabolism or prevents regain beyond normal recovery; the first RCT's reported signal is *higher early hunger* vs going straight to maintenance. **[B]** Helms' "recovery diet" — straight to maintenance — is the evidence-aligned alternative, and long-term regain appears similar either way. **[B]**

### 5.2 "Starvation mode / metabolic damage will stall your fat loss"
**Not supported as described.** Metabolic *adaptation* is real (Trexler 2014, **[A]**) but is on the order of **30–100 kcal/day** in normal programs **[B]**, not a stall. The Minnesota Starvation Experiment (1944, 36 men, ~1,560 kcal, six months) is the canonical counter-evidence: **the men did not stop losing weight.** **[B]**

### 5.3 "The 30-minute anabolic window"
**Not supported.** A meta-analysis of **23 RCTs** found that studies showing a post-workout timing benefit had a **dosing confound** — the timed groups consumed **~25 % more total daily protein**. With total intake statistically matched, the timing effect vanished for both hypertrophy and strength. **[B]** (This is Schoenfeld/Aragon/Krieger; I confirmed the finding's substance, not the exact citation, in this session.) See also Aragon & Schoenfeld, "Nutrient timing revisited: is there a post-exercise anabolic window?", PMC3577439. **[A]** (exists)

### 5.4 "Diet breaks make you lose fat faster"
**Not supported in trained people.** ICECAP: no difference in fat loss, FFM, strength or REE. **[A]** 2024 meta-analysis: **no between-group difference in any body-composition outcome**; the RMR benefit was real but "more significant… in individuals with overweight/obesity compared with resistance-trained individuals." **[A]** MATADOR's superior fat loss was in **obese men**, and is routinely quoted as if it generalized to lifters. It doesn't.

### 5.5 "A 2-day refeed preserves muscle"
**Contested in print.** Campbell 2020 said yes; a published reanalysis comment (PubMed 33467300) concluded **only dry fat-free mass differed between groups**. **[A]**

### 5.6 "You can't build muscle in a deficit"
**Wrong as an absolute** — Longland, Demling, and Barakat's reviewed cases refute it. **But the industry's overcorrection is equally wrong**: the populations in which it's demonstrated are overwhelmingly **novice and/or overfat**, and the effect shrinks toward zero as training age rises and body fat falls. **[A/B]** Your engine's training-age-stratified situational multipliers are the correct way to encode this.

### 5.7 "Women build muscle at half the rate of men" — ⚠️ **THIS ONE HITS YOUR ENGINE DIRECTLY**

**Refalo M, et al. (2025). "Sex differences in absolute and relative changes in muscle size following resistance training in healthy adults: a systematic review with Bayesian meta-analysis." PubMed 40028215 / PMC11869894.** 2,720 studies screened, **29 included**. **[A]**

Finding: **"Absolute increases in muscle size slightly favoured males compared to females, however, relative increases in muscle size were similar between sexes"** — men outpaced women by **0.69 %**, described as negligible. Absolute hypertrophy favored males in **upper body but not lower body**. Type I fiber hypertrophy slightly favored males; **Type II was similar**. Conclusion: **"Females have a similar potential to induce muscle hypertrophy as males (particularly when considering relative increases in muscle size from baseline)."** **[A]**

**Your engine applies `female ×0.5` to a rate expressed in `%BW/month` — which is a RELATIVE measure.** The best current meta-analysis says relative hypertrophy is **similar between sexes** (Δ ≈ 0.69 %). A ×0.5 multiplier on a relative rate is therefore **very likely wrong**, and wrong in the direction that will systematically tell female users their goals take twice as long as they actually will.

**Recommendation:** if you want a sex adjustment at all, apply it to **absolute** kg/month (where it is defensible, and even then mostly upper-body), not to **%BW/month**. Or drop it. This is a real, checkable, citable bug in the spec as given to me.

### 5.8 Smaller ones, for completeness
- **Spot reduction**: a 2021 systematic review + meta-analysis, **13 studies / 1,158 participants**, found **no significant difference in localized fat loss between trained and untrained limbs**; pooled effect essentially zero. **[B]** A 12-week RCT found no greater belly-fat reduction from abdominal RT + diet vs diet alone. **[B]** (Note: Menno Henselmans has a dissenting article, "New science: spot reduction is not a myth" — the claim is not 100 % settled, but the meta-analytic weight is against it. **[A]** article exists)
- **"Toning"**: not a physiological state. Light-load high-rep and heavy-load low-rep produce **equivalent hypertrophy when sets are taken near failure**, so "lift light to tone, lift heavy to bulk" is false as stated. **[B]**
- **더티벌크 / 살크업**: Korean coaching content is aligned with the English literature here — more surplus buys disproportionate fat, and 살크업 is explicitly a pejorative for "claiming to bulk while just getting fat." **[B]**

---

## 6. Korean vernacular — and the 감량 vs 커팅 verdict the owner asked for

### 6.1 The actual Korean terms, as used

| Korean | Meaning as actually used | Source | Grade |
|---|---|---|---|
| **다이어트 / 감량** | General weight loss. Goal is **체중 감량** (scale weight). Diet-led. | 나무위키, Korean fitness sites | **[B]** |
| **커팅** | **"근 손실을 최소화하며 지방을 걷어내는 일체의 행위"** — minimizing muscle loss while stripping fat. **"커팅의 목표는 체중 감량이 아니라 체지방 감량"** — the goal is *not* weight loss, it is fat loss. Higher protein and carbs, **must be accompanied by resistance training**. In competitor context: lowering BF% before a show to sharpen 데피니션. | 나무위키「커팅」; tilnote 헬스 문해력; 파이토매거진 | **[B]**, but consistent across sources |
| **벌크업** | Eating above need to gain muscle, **accepting fat gain** | 나무위키「벌크업」 | **[B]** |
| **린매스업** | 린(lean) + mass up. Hold the **minimum body fat needed for muscle synthesis** while adding muscle. Slower than 벌크업, gentler on the body. | beautypl.com; 몬스터짐 | **[B]** |
| **클린벌크 / 더티벌크** | Controlled surplus vs eat-anything surplus | Korean coach content | **[B]** |
| **살크업** | Pejorative: "claiming to bulk while just getting fat" | brunch.co.kr; Blind | **[B]** |
| **상승다이어트** | **The Korean word for body recomposition.** Explicitly: "외국에서 'BODY RECOMPOSITION'으로 불리며… 지방은 빼면서 골격근량은 늘리는 것" | 몬스터짐「상승 다이어트 하는 방법」; Blind | **[B]** |
| **리컴포지션 / 바디 리컴포지션** | The loanword, increasingly common; note it collides with the Android/Jetpack Compose meaning in search | flextoast, maily.so | **[B]** |
| **유지어터** | 유지 + 다이어터 — someone whose program is *maintaining*. A real, widely-used identity in Korean fitness communities. | 헤럴드 mrealfoods; Blind; DCinside | **[B]** |

### 6.2 The verdict: **감량 and 커팅 should be ONE mode, not two**

The owner asked me not to paper over this. Here is the straight answer.

**They are the same energy-balance direction.** Both are A1. Nothing in your engine can distinguish them: same direction, same `a` range, same protein policy, same strategy preference. If you ship both, the engine will produce **two tiles that generate identical plans**, and the owner will correctly conclude the app is padding.

**They differ in three ways, and every one of them is an input you already collect, not a mode:**

| Dimension | 감량 | 커팅 |
|---|---|---|
| What the user optimizes | 체중 (scale weight) | 체지방량 with SMM held |
| Existing muscle base | May be low | Assumes an existing base |
| Body fat starting point | Often high | Usually already moderate-to-low |

All three are **derivable from the InBody sheet plus the user's entered deltas**. Current PBF tells you the starting point. Current SMM vs. a reference tells you the muscle base. And **ΔSMM is the discriminator**: a user who enters `ΔSMM = 0` is asking for 커팅; a user who enters `ΔSMM < 0` (or leaves it blank and just wants the scale down) is asking for 감량.

**Ship one mode. Name it 감량모드.** Then let the engine's own output state the intent:

> **감량모드** — 체지방 −8 kg, 골격근 유지
> 체지방만 줄이고 근육은 지킵니다. (흔히 '커팅'이라고 부르는 방식입니다.)

That parenthetical does the whole job. The owner sees the word their gym uses, without a duplicate tile. If you later find the owner genuinely wants 커팅 as a separate label, make it a **preset of 감량모드 with `ΔSMM = 0` locked and a tighter `a` ceiling** — a preset, not a mode.

**The one case for two modes** — and it is weak — is that 감량 users are often high-PBF and untrained, where the engine legitimately permits a higher `a` and expects concurrent muscle gain (Longland/Demling territory), while 커팅 users are leaner and trained, where `a` must be lower and muscle gain expectation is ~zero. **But that is exactly what your training-age × PBF logic already computes.** Encoding it twice in the mode list is redundant.

### 6.3 Naming recommendation for the four modes

| Owner's guess | Keep? | Recommended Korean label | Why |
|---|---|---|---|
| 감량모드 | ✅ **Yes** | **감량모드** (subtitle mentions 커팅) | A1. Absorbs 커팅. |
| 커팅모드 | ❌ **Merge into 감량모드** | — | Same engine parameters. See §6.2. |
| 리컴프모드 | ✅ **Yes, with hard entry gates** | **리컴프모드** or **상승다이어트모드** | A4. 상승다이어트 is the native Korean term and will land better with an owner who doesn't know the industry; 리컴프 is the term younger lifters use. Consider showing both. |
| 근성장모드 | ✅ **Yes** | **근성장모드** (subtitle: 린매스업 / 벌크업) | A2. Lean vs aggressive gaining = the two ends of `a`, not two modes. |
| — | ➕ **Add** | **유지모드** | A3. The literature treats maintenance as a first-class phase, Korean has a native identity for it (유지어터), and without it the engine has no mode for "I hit my goal, now what" — which is where every successful user ends up. |

So: **four modes, not four — but a different four.** 감량 / 리컴프 / 근성장 / 유지.

---

## 7. Direct findings against the engine spec as given to me

These are the items where my research contradicts or should change what's already built. Listed highest-impact first.

### 7.1 🔴 `female ×0.5` on a %BW/month rate is very likely wrong
See §5.7. Refalo et al. 2025 Bayesian meta-analysis (29 studies): **relative** muscle-size increases are similar between sexes (Δ 0.69 %); only **absolute** increases favor males, and mainly upper body. Your ceiling is expressed as `%BW/month` — a relative measure. **Recommend removing or drastically reducing the ×0.5**, or moving it to an absolute-kg formulation.

### 7.2 🔴 Check the units on `31 × BFM`
Alpert (2005), "A limit on the energy transfer rate from the human fat store in hypophagia": the derived limit is **(290 ± 25) kJ/kg/d**. Converting: 290 ÷ 4.184 = **69.3 kcal/kg/day** = **31.4 kcal/lb/day**. **[A]**

**The famous "31" is per POUND of fat, not per kilogram.** If your engine caps fat mobilization at `31 × BFM_kg` kcal/day, the cap is **~2.2× too strict** — for a user with 20 kg BFM you'd cap at 620 kcal/day when Alpert's limit is ~1,386. That would make the engine systematically over-predict goal duration for higher-BF users.

Also: secondary sources report that **Alpert later identified a miscalculation and proposed a corrected ~22 kcal/lb/day** (≈48.5 kcal/kg/day), never republished before his death. **[unverified]** — I could not confirm this from a primary source, but if true it moves the correct constant to ~48.5 × BFM_kg. **Verify the units before touching the constant; do not change it on my say-so alone.**

### 7.3 🟡 The calorie floor should be an energy-availability floor
See §4.3. Add **EA = (intake − exercise kcal) / FFM_kg ≥ 30**, target **≥45**, as a hard clamp on `a`. You already compute FFM. For a female user this is not optional — EA < 30 carries ~50 % probability of menstrual dysfunction. **[A]**

### 7.4 🟢 Your situational multipliers are well-founded — defend them
`surplus ×1.0 / maintenance ×0.5 / mild deficit ×0.7-0.35-0.15-0.10 / real deficit ×0.30-0.05-0.00-0.00` maps cleanly onto the Barakat + Longland + Demling picture: novices recomp in real deficits, advanced/elite essentially don't. The ×0.00 for advanced/elite in a >15 % deficit is **defensible precisely because** Longland's overweight-untrained population cannot be extrapolated to them. A "리컴프모드" must not be allowed to override this.

### 7.5 🟡 `상/중/하` and the mode's `a`-range must be reconciled against real rate ceilings
For 감량모드, the literature's range is **0.5–1.0 %BW/week** (Helms 2014) with Garthe 2011 showing that 1.4 %/wk costs lean mass and testosterone. Mini-cut territory (1.0–1.5 %/wk) is a **bounded-duration exception**, not a `하` setting. Suggested binding: 감량모드 `하`≈0.5, `중`≈0.7 (the Garthe-validated rate), `상`≈1.0 %BW/wk — and **refuse above 1.0** outside an explicit mini-cut context with a ≤8-week cap and the 1:4 frequency rule.

### 7.6 🟡 The `"split"` strategy's justification should change
Your split strategy inserts a 2-week maintenance block. The evidence says diet breaks **do not speed fat loss** (ICECAP **[A]**, 2024 meta-analysis **[A]**) and that their RMR benefit is **weaker in resistance-trained than in overweight people** **[A]**. If the simulator ever reports split beating simultaneous *on time-to-goal* for a lean trained user, that is your muscle-gain multipliers talking, not diet-break physiology — and the UI copy should say "근육 보존" / "지속 가능성," never "더 빠름."

### 7.7 ⚪ Not covered by this sweep
- **Age correction** on the muscle-gain ceiling — I found nothing in this sweep and cannot validate your age-correction curve.
- **Katch-McArdle coefficients** (370 + 21.6 × FFM) — not investigated; outside the phase-structure brief.
- **The SMM/FFM ratio `k`** and InBody's SMM definition vs DXA lean mass — not investigated, but worth its own sweep since every downstream number depends on it. Korean sources note InBody 근육량 and 골격근량 are **different quantities** and are frequently confused; if the owner enters a target from the wrong row, everything breaks.

---

## 8. Mode specifications, in the engine's own schema

Each mode expressed as: direction · `a` range · protein/training policy · strategy preference · typical duration · entry criteria · exit criteria · what it refuses.

### 감량모드 (Fat-Loss Mode) — absorbs 커팅

- **Direction**: ΔBFM < 0, ΔSMM ≥ 0 (hold)
- **`a` range**: 0.35 – 0.75 → **0.5–1.0 %BW/week** [Helms 2014 **[A]**]; `중` anchored at **0.7 %/wk** [Garthe 2011 **[A]**]
- **Protein**: **2.3–3.1 g/kg FFM**, scaled up with deficit depth and leanness [Helms/Zinn 2014 **[A]**]
- **Fat**: ≥15 % of calories (≥10 % only in the deepest phase) [Helms 2014 **[A]**]
- **Training**: maintain RT; RT volume is **not** the lever for LM preservation [Roth 2023 **[A]**]. Cardio optional, start 2–3 × 20–30 min MISS if used **[B]**
- **Strategy**: `simultaneous`. `split` only if BFM is large enough that a post-cut gain phase clears the muscle ceiling
- **Duration**: 8–16 weeks; hard stop at ~24 weeks, then a mandatory maintenance block of half-to-double the diet length **[B]**
- **Entry**: PBF above the user's target band; ΔSMM entered as 0 or blank
- **Exit**: target BFM reached, OR 16 weeks elapsed, OR EA floor binding, OR SMM trending down 2 consecutive measurements
- **Refuses**: >1.0 %BW/wk outside a mini-cut context; EA < 30 kcal/kg FFM; promising SMM *gain* to an advanced/elite lean user

### 리컴프모드 / 상승다이어트모드 (Recomposition Mode)

- **Direction**: ΔBFM < 0 **and** ΔSMM > 0, with ΔBW ≈ 0
- **`a` range**: 0.05 – 0.20 → maintenance to a very mild deficit (**≤15 % of TDEE**, matching your engine's own mild-deficit threshold). The "−100 to −200 kcal" figure is **[unverified]** — use your `a` scalar, don't hard-code it.
- **Protein**: **top of the range, ≥2.4 g/kg FFM.** Protein is the non-negotiable variable in every recomp result [Barakat 2020 **[B]**; Longland 2016 **[A]**]
- **Training**: **genuinely progressive** RT — Barakat names progressive overload as one of only two conditions **[B]**
- **Strategy**: `simultaneous` only. Split is incoherent here by definition.
- **Duration**: **12–24 weeks minimum.** Recomp is slow; anything under 12 weeks won't clear InBody measurement noise.
- **Entry** (all must hold):
  - Training age ∈ {novice, intermediate}, **OR** returning after detraining, **OR** PBF elevated and never resistance-trained — these are Barakat's three reliable populations **[B]**
  - Entered ΔSMM > 0 and ΔBFM < 0 and |ΔBW| small
- **Exit**: either target reached, or ΔSMM stalls for 8 weeks → hand off to 근성장모드 or 감량모드
- **Refuses** (this is the mode's most important property):
  - **Advanced/elite AND already lean** → tell the user honestly: at ≤0.375 %BW/month ceiling × 0.5 maintenance factor, the predicted monthly SMM change is below what an InBody can resolve. Recommend 근성장모드 or 감량모드 instead.
  - **Any user who wants speed.** Recomp costs an intermediate ~70–80 % of their surplus-driven gain rate **[B]**. Put that number on the tile.

### 근성장모드 (Muscle-Gain Mode) — 린매스업 at low `a`, 벌크업 at high `a`

- **Direction**: ΔSMM > 0; ΔBFM permitted to rise
- **`a` range**: 0.25 – 0.60 → **0.25–0.5 %BW/week gain**, **10–20 % surplus** [Iraki 2019 **[A]**]. `하` = 린매스업 end; `상` = 벌크업 end, and **advanced/elite should be clamped to the low end** — Iraki explicitly says advanced bodybuilders should be more conservative **[A]**
- **Protein**: **1.6–2.2 g/kg/day**, 0.40–0.55 g/kg per meal, 3–6 meals [Iraki 2019 **[A]**]
- **Fat**: 0.5–1.5 g/kg/day [Iraki 2019 **[A]**]
- **Strategy**: `simultaneous`. A mini-cut (2–8 wk, 25–30 % deficit, ~1.0–1.5 %BW/wk **[B]**) may fire **internally** when PBF crosses the ceiling — subject to the **1:4 dieting-to-gaining week ratio [B]**
- **Duration**: 3–6 months [RP **[B]**], then a maintenance block
- **Entry**: PBF at or below the gaining band — **men 10–15 %, women 20–25 %** [Helms/3DMJ **[B]**]; Korean 린매스업 convention is **men 13–18 %, women 18–24 %** **[B]**. These bands differ; pick one and say which.
- **Exit**: PBF exceeds the ceiling (→ mini-cut or 감량모드), or target SMM reached
- **Refuses**: starting a bulk above the PBF ceiling; promising gain rates above the training-age ceiling; **any p-ratio-based rate bonus for being lean** — that mechanism is actively disputed (Nuckols/Trexler vs Henselmans, with Henselmans publicly reversing **[A/B]**)

### 유지모드 (Maintenance Mode) — the one the owner didn't ask for and needs

- **Direction**: ΔBW ≈ 0, ΔSMM ≥ 0, ΔBFM ≈ 0
- **`a`**: ≈ 0 (energy balance)
- **Protein**: keep at the gaining-phase range, ~1.6–2.2 g/kg **[A]**
- **Duration**: **4–12 weeks**, or **half-to-double the preceding diet's length** **[B]**
- **Entry**: a diet or gain phase just ended; or the user hit their target
- **Exit**: user chooses the next phase; hormones/performance recovered
- **Refuses**: being sold as a metabolism repair. **Framed as the recovery diet (straight to maintenance), not the reverse diet.** Regain rate ~0.5–1.5 %BW/month if any **[B]**. Do **not** promise TDEE "rebuilding" — no evidence supports it **[B]**

---

## 9. Auto-selection: what the literature says the decision rule must key on

The owner wants entered (Δweight, ΔSMM, ΔBFM) to auto-pick a mode. The research says the **deltas alone are insufficient** — three more inputs are load-bearing:

1. **Training age** — it is the single strongest moderator in the whole literature (Barakat's populations **[B]**; Iraki's advanced caveat **[A]**; your own engine's ceilings). Without it, 리컴프모드 will be recommended to people for whom it is unmeasurable.
2. **Current PBF** — it gates 근성장모드 entry (10–15 % / 20–25 % **[B]**) and it determines whether diet-break machinery helps at all (the 2024 meta-analysis found the RMR benefit concentrated in overweight/obese, not trained **[A]**).
3. **Sex** — but for the **EA floor** (§4.3, hard safety rail, **[A]**), **not** for a ×0.5 gain-rate penalty (§5.7, **contradicted [A]**). These two are currently the wrong way round in the spec I was given.

**The delta signature alone maps like this:**

| ΔBW | ΔSMM | ΔBFM | Mode |
|---|---|---|---|
| < 0 | ≈ 0 | < 0 | **감량모드** |
| < 0 | < 0 | < 0 | **감량모드** (and warn: SMM loss is a cost, not a goal) |
| ≈ 0 | > 0 | < 0 | **리컴프모드** — *if* training-age/PBF gates pass; else split into 감량 → 근성장 |
| > 0 | > 0 | ≥ 0 | **근성장모드** |
| > 0 | > 0 | < 0 | **리컴프모드 at the surplus edge**, or 근성장모드 — physiologically the hardest ask; runner-up should always be the split strategy |
| ≈ 0 | ≈ 0 | ≈ 0 | **유지모드** |

The ambiguous row — `ΔBW > 0, ΔSMM > 0, ΔBFM < 0` — is where your engine's two-strategy race earns its keep, and it is the row where the owner most needs to see the runner-up and the reasoning.

---

## 10. Sources

**Peer-reviewed (existence, authorship and venue confirmed via search; full texts were not readable in this session):**

- [Helms, Aragon & Fitschen (2014). Evidence-based recommendations for natural bodybuilding contest preparation: nutrition and supplementation. *JISSN* 11:20](https://pubmed.ncbi.nlm.nih.gov/24864135/)
- [Helms, Zinn, Rowlands & Brown (2014). A Systematic Review of Dietary Protein During Caloric Restriction in Resistance Trained Lean Athletes: A Case for Higher Intakes. *IJSNEM* 24(2):127–138](https://journals.humankinetics.com/downloadpdf/journals/ijsnem/24/2/article-p127.xml)
- [Helms & Fitschen et al. Recommendations for natural bodybuilding contest preparation: resistance and cardiovascular training](https://ro.ecu.edu.au/ecuworkspost2013/1869/)
- [Iraki, Fitschen, Espinar & Helms (2019). Nutrition Recommendations for Bodybuilders in the Off-Season: A Narrative Review. *Sports* 7(7):154](https://www.mdpi.com/2075-4663/7/7/154)
- [Barakat, Pearson, Escalante, Campbell & De Souza (2020). Body Recomposition: Can Trained Individuals Build Muscle and Lose Fat at the Same Time? *Strength Cond J* 42(5)](https://journals.lww.com/nsca-scj/fulltext/2020/10000/body_recomposition__can_trained_individuals_build.3.aspx)
- [Longland et al. (2016). Higher compared with lower dietary protein during an energy deficit… *Am J Clin Nutr*](https://www.sciencedirect.com/science/article/pii/S0002916522065595) · [NCT01776359](https://clinicaltrials.gov/study/NCT01776359)
- [Garthe et al. (2011). Effect of two different weight-loss rates on body composition and strength and power-related performance in elite athletes. *IJSNEM* 21(2):97](https://pubmed.ncbi.nlm.nih.gov/21558571/)
- [Trexler, Smith-Ryan & Norton (2014). Metabolic adaptation to weight loss: implications for the athlete. *JISSN* 11:7](https://pubmed.ncbi.nlm.nih.gov/24571926/)
- [Byrne et al. (2018). Intermittent energy restriction improves weight loss efficiency in obese men: the MATADOR study. *Int J Obes*](https://www.nature.com/articles/ijo2017206)
- [Peos et al. (2021). Continuous versus Intermittent Dieting for Fat Loss and Fat-Free Mass Retention in Resistance-trained Adults: The ICECAP Trial. *MSSE*](https://www.ovid.com/jnls/acsm-msse/abstract/10.1249/mss.0000000000002636~continuous-versus-intermittent-dieting-for-fat-loss-and) · [secondary analysis, *PLOS One*](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0247292)
- [Effects of intermittent dieting with break periods on body composition and metabolic adaptation: a systematic review and meta-analysis (2024). *Nutrition Reviews* 83(1):59](https://pubmed.ncbi.nlm.nih.gov/38193357/)
- [Campbell et al. (2020). Intermittent Energy Restriction Attenuates the Loss of Fat Free Mass in Resistance Trained Individuals. *JFMK* 5:19](https://www.mdpi.com/2411-5142/5/1/19) · [published reanalysis comment](https://pubmed.ncbi.nlm.nih.gov/33467300/)
- [Peos et al. (2023). The Effects of Intermittent Diet Breaks during 25% Energy Restriction on Body Composition and RMR in Resistance-Trained Females: RCT](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10170537/)
- [Refalo et al. (2025). Sex differences in absolute and relative changes in muscle size following resistance training: systematic review with Bayesian meta-analysis](https://pubmed.ncbi.nlm.nih.gov/40028215/) · [PMC11869894](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11869894/)
- [Roth et al. (2023). Resistance training volume does not influence lean mass preservation during energy restriction in trained males. *Scand J Med Sci Sports*](https://onlinelibrary.wiley.com/doi/10.1111/sms.14237) · [related: PMC9012799](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9012799/)
- [Alpert (2005). A limit on the energy transfer rate from the human fat store in hypophagia](https://pubmed.ncbi.nlm.nih.gov/15615615/)
- [Ruiz-Castellano et al. (2021). Achieving an Optimal Fat Loss Phase in Resistance-Trained Athletes: A Narrative Review. *Nutrients* 13(9):3255](https://www.mdpi.com/2072-6643/13/9/3255)
- [Nutritional Recommendations for Physique Athletes (2020)](https://pubmed.ncbi.nlm.nih.gov/32148575/)
- [Alterations in Measures of Body Composition… during Preparation for Physique Competition: A Systematic Review of Case Studies](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10204542/)
- [Post-competition recovery in natural physique athletes. *JISSN* 23(1)](https://www.tandfonline.com/doi/abs/10.1080/15502783.2026.2676190)
- [The effects of reverse dieting on mitigating weight regain after a caloric deficit: a preliminary analysis. *JISSN* 22(sup2)](https://www.tandfonline.com/doi/abs/10.1080/15502783.2025.2550185)
- [ISSN position stand: diets and body composition](https://link.springer.com/article/10.1186/s12970-017-0174-y)
- [Aragon & Schoenfeld. Nutrient timing revisited: is there a post-exercise anabolic window?](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3577439/)
- [Intermittent Dieting: Theoretical Considerations for the Athlete](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6359485/)

**Evidence-based coaching organizations:**

- [Stronger by Science — Should You Cut Before You Bulk?: How Body-Fat Levels Affect Your P-Ratio](https://www.strongerbyscience.com/p-ratios/) · [Rebuttal](https://www.strongerbyscience.com/p-ratios-rebuttal/) · [Rebuttal to the Rebuttal to the Rebuttal](https://www.strongerbyscience.com/p-ratios-rebuttal-2/)
- [Menno Henselmans — What's the optimal BF% for bulking? I was WRONG](https://mennohenselmans.com/whats-the-optimal-bf-for-bulking-i-was-wrong/) · [ICECAP review](https://mennohenselmans.com/icecap-diet-break-study-review/) · [Campbell refeed review](https://mennohenselmans.com/campbell-refeed-study-review/) · [New science: spot reduction is not a myth](https://mennohenselmans.com/science-spot-reduction-myth/)
- [MacroFactor — Reverse Dieting: Hype Versus Evidence](https://macrofactor.com/reverse-dieting/) · [Can You Lose Fat and Gain Muscle at the Same Time?](https://macrofactor.com/recomposition/)
- [RP Strength — All about diet breaks & refeeds](https://rpstrength.com/blogs/articles/all-about-diet-breaks-refeeds) · [The Value of Post-Diet Maintenance](https://rpstrength.com/blogs/articles/the-value-of-post-diet-maintenance) · [Why Massing is Beneficial](https://rpstrength.com/blogs/articles/why-massing-is-beneficial)
- [3DMJ — The Recovery Diet](https://www.3dmjvault.com/courses/the-recovery-diet) · [Helms: The Recovery Diet, Not the Reverse Diet](https://www.youtube.com/watch?v=IR4RjUd6LRY)
- [Lyle McDonald — Determining Calorie Intake for Muscle Gain](https://bodyrecomposition.com/muscle-gain/calories-for-muscle-gain) · [Calorie Partitioning](https://bodyrecomposition.com/muscle-gain/a-guide-to-calorie-partitioning)
- [Biolayne — New data on diet breaks](https://biolayne.com/reps/issue-21/new-data-on-diet-breaks/) · [Muscle Growth: Does Sex Make a Difference?](https://biolayne.com/reps/issue-36/muscle-growth-does-sex-make-a-difference/)
- [Legion — Metabolic Damage and Starvation Mode, Debunked by Science](https://legionathletics.com/metabolic-damage/)
- [University of Sydney — Spot reduction: why targeting weight loss to a specific area is a myth](https://www.sydney.edu.au/news-opinion/news/2023/11/07/spot-reduction--why-targeting-weight-loss-to-a-specific-area-is-.html)

**Korean vernacular (community/industry usage — cited for terminology, not for physiology):**

- [나무위키 — 커팅](https://namu.wiki/w/%EC%BB%A4%ED%8C%85) · [벌크업](https://namu.wiki/w/%EB%B2%8C%ED%81%AC%EC%97%85) · [체성분 검사](https://namu.wiki/w/%EC%B2%B4%EC%84%B1%EB%B6%84%20%EA%B2%80%EC%82%AC)
- [몬스터짐 — 상승 다이어트 하는 방법](https://www.monsterzym.com/index.php?dispatch=community.view&community_code=coach&community_data_idx=10424958&sl=en) · [보디빌딩 시합을 준비하는 영양](https://www.monsterzym.com/index.php?dispatch=community.view&community_code=column&community_data_idx=1728175&sl=en) · [커팅과 린매스업](https://www.monsterzym.com/index.php?dispatch=community.view&community_code=coach&community_data_idx=8824992&sl=ko)
- [Blind 헬스·다이어트 — 벌크업?? 살크업?? 린매스업?? 상승다이어트??](https://www.teamblind.com/kr/post/%EB%B2%8C%ED%81%AC%EC%97%85-%EC%82%B4%ED%81%AC%EC%97%85-%EB%A6%B0%EB%A7%A4%EC%8A%A4%EC%97%85-%EC%83%81%EC%8A%B9%EB%8B%A4%EC%9D%B4%EC%96%B4%ED%8A%B8-r6J8hd5b)
- [beautypl — 초보 다이어터라면 벌크업 대신 린매스업](https://beautypl.com/wellness/2023/07/lean-mass-up-body-fat-percentage/)
- [헤럴드 — 유지어터, 락토오보… 별별 다이어트 신조어](http://mrealfoods.heraldcorp.com/view.php?ud=20190403000482)
- [경향신문 수피의 헬스 가이드 — 벌크업 식단의 핵심 탄수화물](https://www.khan.co.kr/article/202512130900005)
- [tilnote 헬스 문해력 — 벌크업과 커팅](https://tilnote.io/en/books/6a0af304feaf255d2099bb3c/6a0af303feaf255d2099bb08)
- [FlexToast — 바디 리컴포지션 가이드](https://www.flextoast.com/ko/learn/body-recomposition-guide)

---

## 11. The three things to verify before any of this becomes a constant

Because I could not read a single full text, these are the items where a wrong number does real damage and where a 10-minute check on an unblocked machine pays for itself:

1. **Alpert's units** — `31 kcal/lb/day` vs `31 kcal/kg/day`, plus whether the ~22 kcal/lb correction is real. Affects every 감량모드 duration estimate for higher-BF users. (§7.2)
2. **Refalo et al. 2025's actual effect sizes** — confirm "relative increases similar between sexes, Δ 0.69 %" before deleting the `female ×0.5`. Affects every female user's predicted timeline. (§7.1)
3. **Barakat 2020's actual practical-recommendation table** — specifically whether "−100 to −200 kcal/day" is in the paper or is a blog invention. It is the number 리컴프모드 would be built on. (§3.1)