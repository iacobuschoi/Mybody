# 식단 기록(Diet Tab) — Open-Source Food-Recognition Sweep

**Swept:** 2026-09-19. GitHub metadata pulled live from the API (stars / license / `pushed_at` / archived flag are verified). Paper numbers come from search-result summaries — `arxiv.org`, `huggingface.co`, `pmc.ncbi.nlm.nih.gov`, `biorxiv.org`, `openaccess.thecvf.com` and `kr.openfoodfacts.org` are all **blocked by this environment's egress proxy**, so I could not open primary PDFs. Every number sourced that way is tagged `[secondary]`. Anything I could not confirm at all is tagged `[unverified]`.

---

## 0. Bottom line first

**There is no open-source model you can ship that will look at a photo of 김치찌개 and tell you it was 480 kcal / 28g protein. Not one. Not in 2026.**

Three separate walls, in order of severity:

1. **Portion, not identity, is the problem.** The Nutrition5k paper (Google, CVPR 2021) measured this directly: predicting **calories-per-gram** from an image gives ~9.5% error; predicting **total calories** (which requires knowing how much is there) gives **26.1%** — a ~3× jump from the same image with the same model. `[secondary]` Every "food AI" demo that impresses you is solving the easy half.
2. **Korean food is a data desert in open source.** Food-101 is 101 Western dishes. FoodSeg103 is Western/Chinese ingredients. ISIA Food-500 is Chinese-weighted. The only two open-source Korean food recognition repos on GitHub have **14 stars and 4 stars**, and both are dead. The good Korean data exists — but it's on AI Hub, behind Korean phone verification, and it is a *dataset*, not a model.
3. **Nothing usable runs in a browser.** The classifiers small enough for `transformers.js` (MobileNet-class, <20MB) only do Western dish labels. The models that actually reason about food (FoodLMM = LISA-7B + SAM ViT-H) are ~15GB `[estimate]` and need a GPU server.

**What IS real in 2026:** frontier VLM APIs (Gemini 3.x Flash, GPT-5 Mini, Claude Haiku 4.5) at ~**80 kcal MAE per meal**, and — this is the important finding — **context metadata cuts that error dramatically**. Mybody already has the context every research paper says is missing.

---

## 1. The framing the user needs to hear

> "식사 사진 찍으면 자동으로 칼로리 나와요" 앱들이 실제로 하는 일은, **음식 이름을 맞히고 표준 1인분 영양성분을 그대로 가져오는 것**입니다. 사진에서 양을 재는 게 아니라요.

Evidence that this is the actual bottleneck, not my opinion:

| Finding | Number | Source |
|---|---|---|
| Nutrition5k: kcal/gram vs total kcal, same images | 9.5% → **26.1%** MAE | Nutrition5k CVPR 2021 `[secondary]` |
| Nutrition5k: RGB only → RGB+depth | 70.6 kcal MAE (26.1%) → **47.6 kcal (18.8%)** | ditto `[secondary]` |
| Nutrition5k: with explicit volume scalar | **41.3 kcal (16.5%)** | ditto `[secondary]` |
| NutriBench: LLM given a **perfect text description** (no image at all), carbs within ±7g | **66.8%** (GPT-4o + CoT, best of 12 models) | NutriBench, 11,857 meals |
| Korea's own commercial leader (누비랩) achieving 95% | requires a **fixed-geometry tray scanner with volume detection**, not a phone | Nuvilab marketing `[unverified independently]` |

Read that Nutrition5k depth row again. **Adding a depth sensor cut the error by a third.** The user's phone photo has no depth channel, no fiducial marker, no fixed camera height, and no known plate diameter. Nutrition5k's own numbers were measured on single plates, shot overhead, from a **fixed rig, in Google cafeterias**. A phone snap of 순대국밥 on a 학식 tray is strictly harder than the benchmark condition.

And NutriBench's cultural-bias finding is directly aimed at this user: models did **worse on high-carb-staple cuisines** (Sri Lanka cited as the worst). Korean food is rice-staple, soup-heavy, and banchan-plural. Every structural property that makes NutriBench models fail is present in 학식.

---

## 2. Food classification models

### 2.1 Food-101 and its fine-tunes — solved, and useless here

Food-101 is **saturated**. Reported top-1: **NoisyViT 99.5%**, boundary-aware CNN 99.17%, anti-noise/covariance 92.57% `[secondary, all 2025 papers]`. The benchmark is finished as a research problem.

It is also **101 Western dishes** — apple pie, beignets, caesar salad, escargots, foie gras, huevos rancheros, macarons. The Korean intersection is approximately: **bibimbap** (and arguably sushi/ramen/pho/dumplings as adjacent Asian classes). That's it. There is **no** 김치찌개, 제육볶음, 순대국밥, 삼겹살, 부대찌개, 김치볶음밥, 떡볶이, 순두부찌개, 갈비탕, 냉면.

A Food-101 model shown 제육볶음 will confidently return something from its 101 classes, because softmax always returns something. **This is worse than useless — it is confidently wrong.** Correct call: do not ship Food-101 in a Korean app.

Available HF fine-tunes (found via search; `huggingface.co` is proxy-blocked so I could not verify downloads/likes/sizes):
- `prithivMLmods/Food-101-93M` — SigLIP2-base-patch16-224 fine-tune, 101 classes `[unverified metadata]`
- `AventIQ-AI/Food-Classification-AI-Model` — DeiT-base-patch16-224, 101 classes `[unverified metadata]`
- `Kaludi/food-category-classification-v2.0` — **12 coarse categories** (Bread/Dairy/Dessert/Egg/Fried/Fruit/Meat/Noodles/Rice/Seafood/Soup/Vegetable) `[unverified metadata]`
- `Kaludi/Food-Classification` — **7 classes**. Toy. `[unverified metadata]`

The 12-category one is the only interesting shape: coarse categories are *honest* about their resolution. But 12 categories cannot separate 김치찌개 from 된장찌개 (both "Soup") — which is a 2× macro difference.

### 2.2 Google AIY `food_V1` (TF Hub / Kaggle) — the best "small model" option, with a caveat

- **`google/aiy/vision/classifier/food_V1/1`** — MobileNet V1 backbone, 224×224 input, **~2,000+ food classes**, TFLite-ready.
- The class list is far broader than Food-101 and is the only small open model with a plausible shot at Korean dish labels.
- **Caveat, stated by Google's own docs:** trained on a dataset **skewed toward North American foods**. `[secondary]`
- **Zero nutrition output.** It emits a label. You still need a nutrition DB lookup and a portion number.
- **Status:** TF Hub has been folded into Kaggle Models; the artifact is still served but this is frozen 2019-era work. Treat as **legacy but functional**.

### 2.3 Larger classification datasets (datasets, not shippable models)

| Dataset | Size | Classes | Korean coverage |
|---|---|---|---|
| ISIA Food-500 | 399,726 images | 500 | Chinese-weighted; some Korean dishes `[unverified]` |
| FoodX-251 (2019) | 158,846 images | 251 | Western-weighted |
| Recipe1M / Recipe1M+ | ~1M recipes + images | cross-modal retrieval | Western; **access requires registration/agreement** |
| im2recipe | Recipe1M's model | — | Retrieval, not nutrition. Research code, pre-VLM era. **Superseded.** |

`im2recipe` returns *a recipe*, not *your portion*. It was interesting in 2017. In 2026 a VLM does the same job better in one call.

---

## 3. Food SEGMENTATION models — the portion-size half

This is the correct place to look, because segmentation gives you **pixel area**, which is the only image-derived portion signal available without depth.

### 3.1 FoodSeg103 — `LARC-CMU-SMU/FoodSeg103-Benchmark-v1`

- **127 ★ · Apache-2.0 · last push 2024-01-17** → **~20 months dormant**
- 7,118 images, **104 classes** (103 ingredients + background), 4,983 train / 2,135 val
- Best reported baseline: **ViT-B/16 + MLA decoder = 45.1 mIoU, 57.4 mAcc**
- Dataset download is **password-gated** (`LARCdataset9947`, published in the repo); pretrained models via a SharePoint link
- **Ingredient-level, not dish-level.** It segments "rice", "egg", "tomato" — not "비빔밥".
- **Verdict: dormant code, but the dataset itself doesn't rot.** 45 mIoU on a clean benchmark is a weak foundation for portion math. Usable for research; not for a shipping estimate.

### 3.2 FoodSAM — `jamesjg/FoodSAM`

- **184 ★ · Apache-2.0 · last push 2024-01-24** → **~20 months dormant**
- Fuses SAM-generated masks with a coarse semantic segmenter
- Reported on FoodSeg103: **46.42 mIoU / 58.27 mAcc / 84.10 aAcc** `[secondary]`
- **Beats the FoodSeg103 baseline by ~1.3 mIoU** while dragging in SAM ViT-H (~2.4GB `[unverified]`)
- **Verdict:** a +1.3 mIoU gain for a 2.4GB dependency is a research result, not a product decision. **Dormant.**

### 3.3 Others

- **`jamesjg/FoodInsSeg`** — ingredient-level *instance* segmentation benchmark. **3 ★**, last activity 2025-04. Effectively unused.
- **`NimaVahdat/FoodSeg_mask2former`** — Mask2Former fine-tuned on FoodSeg103 + Gradio demo. **10 ★**, updated 2026-01-20. Alive-ish, tiny, one person. Useful as a *reference implementation*, not a dependency.
- **`puzhijie7-spec/HEFGNet`** — fine-grained food segmentation, official impl `[metadata unverified]`.
- **UEC FoodPix / UEC Food-100/256** — Japanese lab datasets. Japanese food ≠ Korean food (no 찌개 culture, no banchan spread), and the licensing is academic-request-based. `[unverified currency]`
- **Swin-TUNA (2507.17347)**, **weakly-supervised ViT+SAM (2509.19028)**, **PCA-CNN (2411.01469)** — 2025-era FoodSeg103 papers, incremental mIoU. Not products.

**Segmentation verdict:** the field's *best* result is ~46 mIoU on a 104-class Western/Chinese ingredient benchmark, and even a perfect mask gives you **area in pixels**, not **grams**. Converting area→volume→mass requires depth or a known-scale reference. Nobody has solved this from a single uncalibrated phone photo.

---

## 4. End-to-end "image → nutrition" research

### 4.1 Google im2calories (2015) — **never released. Dead on arrival.**

Announced by Kevin Murphy at a 2015 summit. Press cycle: Fortune, Digital Trends, TechXplore, Gigazine. The reported design (per-pixel depth → volume → plate-relative portion → nutrition DB) is *exactly* the right architecture, which is why it still gets cited. But Murphy stated it was **a research project with no plans for release** — and eleven years later there has been **no code, no weights, no follow-up product**. Even the demo needed a **dropdown for the user to correct misidentifications, "which happens somewhat frequently."** `[secondary]`

Anyone who cites im2calories as evidence this works is citing a press release from 2015.

### 4.2 Nutrition5k (Google, CVPR 2021) — **dataset released, repo now ARCHIVED**

- `google-research-datasets/Nutrition5k` — **416 ★ · ARCHIVED (read-only) · CC-BY-4.0** per README `[license field not returned by API]`
- ~5,000 real plates from Google cafeterias: video streams, **depth images (Intel RealSense)**, per-ingredient weights, high-accuracy macro annotations. ~20k short videos + 3.5k RGB-D stills.
- Paper claims accuracy "outperforming professional nutritionists" `[secondary]`
- Reported baselines `[secondary]`:

| Method | kcal MAE | MAPE |
|---|---|---|
| 2D direct prediction (RGB) | 70.6 | 26.1% |
| + depth as extra channel | 47.6 | **18.8%** |
| volume scalar approach | 41.3 | **16.5%** |
| (calories **per gram**, i.e. portion removed) | — | **9.5%** |

- **This is the single most important table in the whole sweep.** It quantifies exactly how much of the error is portion estimation, and it shows depth buying a 28% relative error reduction.
- **Limitations that kill phone transfer:** fixed overhead scanning rig, controlled lighting, single plate, cafeteria-style plating, RGB-**D**. None of that survives contact with a 학식 tray or a 배달 용기.
- **Verdict: the dataset is alive and valuable. The repo is frozen.** Community re-implementations exist (`Oatsty/nutrition5k`, `hlchen23/Nutrition5k_run`, `SightVanish/NutritionEstimation`, `zhonghao-sheng/food-calorie-estimation`) — all small, unmaintained-scale forks `[metadata unverified]`.

### 4.3 MenuMatch (2013)

Estimates calories from **restaurant menu items** by matching the dish to a restaurant's published nutrition data — not from pixels-to-grams. Pre-deep-learning. **No maintained implementation. Dead.** But note: *the idea is sound and is exactly what Mybody should do for 프랜차이즈 메뉴* — match to a known menu item instead of guessing from pixels.

### 4.4 Newer depth/volume research (2022–2026)

`DPF-Nutrition` (depth prediction + fusion, 2310.11702), `Image-Based Food Energy Estimation with Depth Domain Adaptation` (2208.12153), `Nutrition Estimation … Transformer with Depth Sensing` (2406.01938), `Visual-Ingredient Feature Fusion` (2505.08747, reports **PMAE 14.43%** vs prior best 15.9% `[secondary]`), `FLAVA contrastive RGB-D` (2025), `V-Nutri` (egocentric cooking video, 2604.11913).

**Every single one of the strong results uses depth or video.** The SOTA on Nutrition5k has moved from 26.1% → ~14.4% PMAE in five years, and essentially all of the gain came from **not using a single RGB image**. That trend line is the answer to "왜 사진 한 장으로 안 되나요".

### 4.5 DietDelta (CVPR-W 2026, 2604.06352) — **the most practically relevant paper in this sweep**

Estimates what was **actually consumed** from **paired before-and-after images**, predicting weight *differences*, explicitly modeling **plate waste**. Its stated motivation is that existing systems analyze only the pre-meal image and **implicitly assume complete consumption**.

That assumption is catastrophically wrong for the exact foods this user eats: 국밥 국물 남김, 반찬 안 먹음, 도시락 절반. **Every naive photo-calorie app systematically over-counts Korean meals**, because banchan and soup broth are photographed and then not finished.

---

## 5. Vision-language models

### 5.1 FoodLMM — `YuehaoYin/FoodLMM`

- **67 ★ · Apache-2.0 · created 2024-06-09 · last push 2024-06-10 · 6 commits total**
- Built on **LISA (LISA-7B-v1-explanatory) + SAM ViT-H**; training data generated from **Nutrition5k + FoodSeg103 via GPT-4**
- Capabilities: food/ingredient recognition, recipe generation, **nutrition estimation**, **segmentation masks**, multi-round chat. Novel task-specific tokens/heads.
- `FoodLMM-Chat` weights published on HF; LoRA merge scripts included
- **README reports no MAE/PMAE for Nutrition5k** — I checked. You cannot tell from the repo how well it estimates nutrition.
- **Size: ~15GB fp16 for the 7B + SAM ViT-H stack `[estimate, not verified]`.** Server-only, GPU-only.
- **Verdict: abandoned research code.** Six commits over one day, then 15 months of silence. The repo is the artifact of a paper, not a project. Its knowledge is Nutrition5k (Google cafeteria food) + FoodSeg103 (Western ingredients) — **it has never seen 순대국밥.**

### 5.2 Food-R1 (arXiv 2606.04986, June 2026) — newest, unproven

- Unified multi-task food VLM: CoT cold-start instruction tuning → **GRPO reinforcement fine-tuning**
- Ships **CalorieBench-80K**, the first food benchmark with **CoT annotations for calorie reasoning**
- Claims code + weights + benchmark released `[repo not located in this sweep — I could not find or verify the GitHub URL; arxiv.org is proxy-blocked]`
- **Verdict: too new to trust, three months old, no adoption signal, no independent replication.** Worth re-checking in six months. Do not build on it.

### 5.3 Benchmarks — what frontier VLMs actually score

**Ten-model dietary assessment benchmark, 2026** (bioRxiv `10.64898/2026.07.26.740845`; PMC13483877; PubMed 42619751) — **3,229 food images**, ten approaches (Gemini 2.0/2.5/3.0 Flash + 3.1 Flash Lite, GPT-4o, GPT-4o-mini, GPT-5 Mini, Claude Haiku 4.5): `[secondary]`

| Model | Calorie CCC | Calorie MAE | Note |
|---|---|---|---|
| **Gemini 3.0 Flash** | **0.767** | **80.7 kcal** | best accuracy |
| Gemini 3.1 Flash Lite | 0.754 | — | best ingredient Jaccard **0.655**, lowest cost |
| Gemini 2.0 Flash | 0.742 | — | competitive at a fraction of cost |

**Read the MAE honestly: ±80 kcal *per meal*.** Across 3 meals/day that is a ±240 kcal/day error band — and the weekly check-in Mybody already runs adjusts calories by far less than that. **The photo estimate is noisier than the signal it would be feeding.**

**"Are Vision-Language Models Ready for Dietary Assessment?" (2504.06925):** closed-source models exceed **90% EWR** for **single-product** images, but the paper's own conclusion is that VLMs "face challenges in fine-grained food recognition, particularly in distinguishing subtle differences in **cooking styles** and visually similar food items, which limits their reliability for automatic dietary assessment," with "remaining challenges in calorie estimation and component detection for **complex, multi-item meals**." `[secondary]`

"Subtle differences in cooking styles" and "complex multi-item meals" is a literal description of a Korean 밥상: rice + soup + main + 3–5 banchan, several of which differ only by 양념.

**NutriBench** (text, no images) — 11,857 real-world meal descriptions with macro labels. Best: **GPT-4o + CoT, 66.82% accuracy** where accuracy = **carb error < 7g**, 99.16% answer rate. LLMs answered 72 queries in 2 min vs 43 min for humans. **Models did worse on high-carb-staple cuisines.** This is the cleanest evidence available: even with the vision problem entirely removed, frontier LLMs miss carbs by >7g **a third of the time**.

**January Food Benchmark (JFB, 2508.09966)** — 1,000 human-validated food images. GPT-4o overall **70.6** (best config 74.1), best Gemini config **60.7**, and vendor model `january/food-vision-v1` **86.2**. ⚠️ **Published by January AI, whose own model wins by 12 points. Treat with the skepticism any vendor-authored benchmark deserves.**

**Contextual-metadata benchmark (2507.07048, ACETADA dataset)** — **the finding Mybody should act on.** Feeding LMMs contextual metadata (GPS → venue type, timestamp → meal type, known food items) improved, in example cases, **caloric absolute error by 100 kcal and absolute percentage error by 23.42 points.** The dataset uses paired pre/post smartphone images in free-living conditions with fiducial markers.

**Mybody already knows: the user's target macros, his physique mode, his weight trend, what he logged yesterday, what time it is, and what he eats repeatedly.** The research says that context is worth more than a bigger model.

**Conflicting MAPE numbers** (`[unverified — from search summaries, PMC blocked]`): one study reports ChatGPT/Claude at **36.3%/37.3% MAPE for weight**, **35.8% for energy**, with Gemini at **64.2–109.9%** — while the hospital-meal study reports ChatGPT-4o and Gemini 1.5 Pro at **r > 0.8, frequently within ±10%**. The reconciliation: the hospital study used **standardized meals with known portions**. Controlled portions → good numbers. Free-living portions → 35%+ error. **That gap IS the portion problem, visible in the literature as a contradiction.**

---

## 6. Ready-to-run open-source apps

| Repo | ★ | License | Last push | Photo→nutrition? | Verdict |
|---|---|---|---|---|---|
| `simonoppowa/OpenNutriTracker` | **2,548** | **GPL-3.0** | **2026-09-18** | ❌ no photo AI | **Very alive.** Flutter/Dart. Search + barcode + quick-add, Open Food Facts/USDA backed. Self-hostable backend. |
| `apoorvdarshan/fud-ai` | **420** | **MIT** | **2026-09-17** | ✅ **BYOK VLM** | **Alive.** Kotlin/Swift native. 13 AI providers (Gemini/OpenAI/Claude/Grok/Groq/custom), up to 10 photos + note, barcode, voice. **Owns no model.** |
| `ignoxx/caloriemate` | 39 | ⚠️ **NO LICENSE FILE** | 2026-06-10 | ✅ BYOK VLM | Go/PocketBase/TS. OpenRouter (Gemini 2.5 Flash) or Ollama. README's own words: "a **rough estimate**". **No license = legally not reusable.** |
| `tahaygun/ai-calorie-tracker` | 23 | NOASSERTION | **2026-09-19** | ✅ BYOK VLM | Next.js/TS, no account. Closest stack match to Mybody. Tiny. |
| `openfoodfacts/openfoodfacts-server` | 1,156 | — | 2026-09-18 | barcode DB | **Very alive.** 4M+ products, 150 countries. Korean coverage `[unverified — kr.openfoodfacts.org blocked]`. |
| `jrhizor/awesome-nutrition-tracking` | — | — | — | index | Useful directory. |

**The decisive pattern: every single working photo-calorie app in open source is a thin UI over a commercial VLM API.** Not one ships its own food model. The 2,548-star winner — the most successful FOSS nutrition tracker by an order of magnitude — **doesn't do photo recognition at all.** It does search, barcode, and quick-add, and it is the one people actually use.

That is the market telling you what works.

---

## 7. Korean-specific reality check

### 7.1 Open-source Korean food recognition: essentially nonexistent

Exhaustive GitHub search. The **complete** list of Korean food recognition repos with ≥1 star:

| Repo | ★ | Last activity | Verdict |
|---|---|---|---|
| `tonyslowdown/kfood-server` | 14 | **2024-07-28** | Django + TensorFlow Korean food recognition API. **Dead-ish (14 months).** |
| `tonyslowdown/deep-features` | 4 | **2020-02-13** | Inception-v3 Korean food. **DEAD (6+ years).** |
| `ejcho3792/pjt_k_food` | 2 | 2022-04 | **DEAD.** |
| `Happy623623/korean-food-calorie` | 0 | 2026-06 | 한식 15종, EfficientNet-B0 + YOLO11n. Student project. |
| `SeungEon-Ai/korean-food-classifier-ML-app` | 0 | 2026-05 | Student project. |
| `hyosuk121/...korean-food...` | 0 | 2021-12 | **DEAD.** |

**Total community investment in open-source Korean food recognition: 20 stars.** There is nothing to fork.

### 7.2 K-foodNet (Nutrition Research and Practice, 2019) — the best published Korean result

- **92,000+ images, 23 Korean food groups**, downsampled to 150×150, 3:1 split (69k train / 23k test)
- **91.3% test accuracy, 0.4 ms recognition time** — beat AlexNet, GoogLeNet, VGG, ResNet
- Per-class breakdown is the honest part: **백김치, 쌀밥, 김밥 all >95%** — but **제육볶음 and 깍두기 only ~87%**
- **No public code or weights.** Journal paper only.

Note what fails: the *homogeneous-texture, red-sauce, mixed* dishes. 제육볶음 vs 오징어볶음 vs 낙지볶음 vs 닭갈비 are all "red stir-fried meat/seafood on a plate" and have **materially different macros**. This is the Korean-specific failure mode, and it's measured.

### 7.3 AI Hub — the real Korean data, and it's excellent

This is the one genuinely strong asset, and the user can access it because he's Korean:

| Dataset | Scale | Notes |
|---|---|---|
| **음식 이미지 및 영양정보 텍스트** (`dataSetSn=74`) | **400+ 한식·외식 메뉴, ~842,000 images** (5MP+) | annotation JSON + **영양정보 메타데이터** |
| **건강관리를 위한 음식 이미지** (`dataSetSn=242`) | **400여 종, 종당 2,000+ images** | explicitly built for **"음식 종류와 양(portion) 추정"**; **1인분 기준 에너지/탄수화물/단백질/지방** |
| **한국 이미지(음식)** (`dataSetSn=79`) | 150종 × ~1,000장 | 대분류(밥/면/국) → 소분류 구조 |
| 당뇨관리 앱 음식 이미지 (`dataSetSn=71392`) | — | diabetes-app sourced `[unverified scale]` |

⚠️ The two 842k figures may describe the **same build under two catalog entries** — search results conflate them. `[partially verified]`

AI Hub's own pitch is the point: *"온라인에 공개된 음식 사진 데이터셋은 **서양 음식 위주**여서, 한식 이미지 데이터를 다수 확보"*. They built this **because** Food-101 is useless in Korea.

**Access terms (verified):** 대한민국 국민 대상, **휴대폰 인증** 후 자동 승인 다운로드. **상업적 이용 시 수행기관과 별도 협의 필요.** For a personal single-user app: fine. If Mybody ever ships commercially: **you must negotiate.** Flag this now, not later.

### 7.4 Korean nutrition database — free, official, and the actual foundation

**식품의약품안전처 식품영양성분 통합 DB** (data.go.kr `15127578`, foodsafetykorea.go.kr, data.mfds.go.kr):

- **~46,000 entries**: **가공식품 ~42,600** / 식품원재료 ~2,200 / **음식(외식·프랜차이즈 조리식품) ~1,300**
- Up to **24 nutrients** per item, 식품분류체계, 출처, 생성일자
- **OpenAPI, XML + JSON, free**
- Planned expansion to ~60,000 entries `[as of the announcement; current count unverified]`

**The asymmetry matters enormously:** 42,600 processed-food entries (편의점 도시락, 삼각김밥, 단백질바, 과자 — **barcode-scannable, exact**) vs only **~1,300 음식 entries** for the 학식·배달·식당 food that makes up most of a 22-year-old's diet.

**Translation: barcode is a solved problem in Korea. Restaurant/학식 food is not, and no amount of AI fixes a 1,300-row database.**

International APIs: **FatSecret** (56 localized country datasets, 26 languages, 5,000 free calls/day, "Premier Free" for students with attribution — **Korean dataset presence `[unverified]`**), **Nutritionix** (1.9M items, NLP-based). **Open Food Facts** (4M+ products, free, no key) — **Korean coverage unverified**, and crowdsourced coverage of Korean 편의점 SKUs is plausibly thin.

### 7.5 누비랩 (Nuvilab) — proof of what it takes

Korean company, founded 2018. Claims **95% accuracy**, 41M+ cumulative food data points (2023-09) `[company marketing, unverified independently]`. Deployed in 급식/병원/호텔/군부대.

**How:** AI Food **Tray** Scanner / **Bin** Scanner / **Conveyor** Scanner — **fixed-geometry hardware with 부피 감지 (volume detection)**, 1-second scan, and pre/post tray comparison for 잔반.

Korea's most successful food-recognition company solved this by **controlling the camera geometry and measuring volume**. They did not solve it with a phone camera. If a funded company with 41M labeled Korean meals needed a hardware rig, a localStorage prototype will not out-engineer them with a `<input type="file" accept="image/*" capture>`.

---

## 8. Browser feasibility (tfjs / ONNX Runtime Web / transformers.js)

| Model | Size | Browser-capable? | But does it help? |
|---|---|---|---|
| MobileNet-class classifier | **<20MB**, ms inference | ✅ yes, comfortably | ❌ Western labels only |
| AIY `food_V1` (MobileNetV1, 2k classes) | ~20MB TFLite `[est.]` | ✅ needs TFLite→ONNX/tfjs conversion | ⚠️ NA-skewed, **label only, no nutrition, no portion** |
| ViT-B/16 quantized (q8) | ~90–100MB `[est.]` | ⚠️ heavy first load | ❌ Food-101 classes |
| SigLIP2-base food fine-tune | ~100MB+ `[est.]` | ⚠️ marginal | ❌ Food-101 classes |
| Mask2Former / FoodSAM segmentation | SAM ViT-H ~2.4GB `[unverified]` | ❌ **no** | — |
| FoodLMM (LISA-7B + SAM ViT-H) | ~15GB fp16 `[estimate]` | ❌ **absolutely not** | — |
| Frontier VLM (Gemini 3.x Flash etc.) | N/A | ❌ server/API only | ✅ the only thing that works |

**Runtime facts (verified):** `transformers.js` v3 shipped **October 2024** with WebGPU (reported up to 100× faster than WASM), **120 architectures**, **1,200+ pre-converted models**; ONNX Runtime Web has had WebGPU since **ORT 1.17**. q8 quantization is the practical browser default. The plumbing is genuinely mature.

**The conclusion is brutal and clean:** the browser ML stack is ready. **The model isn't.** Everything small enough to run client-side is trained on the wrong food and outputs the wrong thing (a label, not grams). Everything that reasons correctly needs a server. There is **no middle.**

---

## 9. Alive vs. dead — the verdict table

### ✅ Actually usable in 2026

| Thing | Why |
|---|---|
| **식약처 식품영양성분 통합 DB OpenAPI** | Free, official, ~46,000 Korean entries, JSON. **The foundation of the whole feature.** |
| **AI Hub 한식 이미지 데이터셋 (842k imgs, 400 메뉴, 1인분 영양정보)** | Best Korean food data on earth, free for Korean citizens, **portion-labeled** |
| **Open Food Facts API + browser barcode scan** | 4M+ products, free, no key; Korean coverage `[unverified]` |
| **Frontier VLM APIs (Gemini 3.x Flash / GPT-5 Mini / Claude Haiku 4.5)** | ~80 kcal MAE; the only thing that works on arbitrary Korean food; **context metadata cuts error a lot** |
| **`OpenNutriTracker` (2,548★, GPL-3.0, pushed yesterday)** | Best reference for **UX of manual logging**. Copy its interaction model, not its code (GPL). |
| **`fud-ai` (420★, MIT, pushed 2026-09-17)** | MIT, readable BYOK-VLM prompt/parse pipeline worth reading |
| **`transformers.js` v3 / ORT Web** | Mature runtime — for **barcode/OCR**, not food ID |
| **Nutrition5k dataset (CC-BY-4.0)** | Valuable data; **repo archived** |

### ⚠️ Research-grade, don't ship

FoodSeg103 benchmark (20mo dormant, 45.1 mIoU) · FoodSAM (20mo dormant, 46.4 mIoU, 2.4GB) · Food-R1 (3 months old, unverified repo) · DietDelta (great idea, CVPR-W 2026, no product) · AIY `food_V1` (frozen 2019, NA-skewed) · `caloriemate` (**no license**) · FoodSeg_mask2former (10★, one person)

### ☠️ Dead — do not build on these

| Thing | Status |
|---|---|
| **Google im2calories** | Announced 2015, **never released**, no follow-up in 11 years |
| **`google-research-datasets/Nutrition5k` repo** | **ARCHIVED** (dataset still fine) |
| **`YuehaoYin/FoodLMM`** | 6 commits, dead since **2024-06-10**, no accuracy in README |
| **MenuMatch** | 2013, pre-DL, no implementation |
| **`tonyslowdown/kfood-server`** (14★) | Last touched **2024-07** |
| **`tonyslowdown/deep-features`** (4★) | Last touched **2020-02** — **6 years dead** |
| **`ejcho3792/pjt_k_food`**, `hyosuk121/...` | 2021–2022, dead |
| **Food-101 fine-tunes, for a Korean app** | Technically alive, **functionally dead** — 101 Western dishes |
| **im2recipe / Recipe1M retrieval** | Superseded by VLMs |

---

## 10. What Mybody should actually build

**Architecture: manual-first, barcode-exact, photo-assisted. In that priority order.**

```
1. 자주 먹는 음식 (내 기록에서 원탭)     ← 90% of real logging, 0 kcal error beyond the DB
2. 검색 (식약처 46,000건 + 1인분 프리셋)   ← exact, official, Korean
3. 바코드 (편의점 도시락/삼각김밥/프로틴바)  ← 42,600 processed entries = exact
4. 사진 (VLM API, 보조 수단)             ← ±80 kcal, ALWAYS editable, never silent
```

**Why manual-first is the right call, not a cop-out:** the 2,548-star FOSS nutrition tracker has **no photo AI**. The four photo-AI repos have 39, 23, 420 and 0 stars combined maturity. And a 22-year-old eats the same ~40 things on rotation — 제육덮밥, 김치찌개, 닭가슴살, 편의점 도시락, 프로틴 쉐이크. **After week one, "자주 먹는 음식"원탭 is faster than taking a photo and is exactly right instead of ±26%.**

**If photo logging ships, these rules are non-negotiable — they're the same standard Mybody already applies to InBody noise:**

1. **Never write a photo estimate silently.** It lands in an editable draft: 음식명 (correctable) + **양 (1인분 / 0.5인분 / 1.5인분 슬라이더)** + macros. The user confirms. **The portion control is the entire feature** — it's the variable the model can't see.
2. **Show a range, not a point.** `약 520 kcal (±130)`, not `521 kcal`. ±25% is the literature's number for free-living portions. Displaying `521` is a lie with a decimal point.
3. **Mark the source on every entry.** `사진 추정` vs `바코드` vs `직접 입력` should be visually distinct, and weekly/monthly 달성률 should be able to say *"이번 주 기록의 40%가 사진 추정입니다 — 실제 오차는 더 클 수 있어요."* Mybody already tells the user when a body-comp change is below the InBody noise floor. **Same standard: if the week's data is mostly photo estimates, the 달성률 is softer than the number implies.**
4. **Send context with the photo.** The ACETADA result — **~100 kcal / 23 percentage points of error removed by metadata** — is the highest-leverage thing in this entire report and it costs nothing. Send: 시간대(아침/점심/저녁), 목표 매크로, 최근 자주 먹은 음식 목록, 오늘 남은 칼로리, 체형 모드. The model stops guessing "some Korean stew" and starts choosing among things this specific user actually eats.
5. **Ask about 잔반, per DietDelta.** One tap after the meal: `다 먹음 / 2/3 / 절반 / 조금`. Korean meals are *systematically* over-counted because banchan and 국물 get photographed and not finished. This single tap removes more error than upgrading the model.
6. **For 프랜차이즈, do MenuMatch, not vision.** 맘스터치·빽다방·김밥천국 publish nutrition. Matching the menu item beats estimating pixels, always. The 식약처 음식 DB (~1,300 외식 entries) is the seed.
7. **No client-side food model.** The honest sentence for the user: *"한식 인식용 오픈소스 모델은 사실상 없습니다. Food-101은 서양 음식 101종이라 김치찌개를 모릅니다."*

**On the coaching nudges the user asked for** — these are the *good* part of the request, and they need **zero** AI. They are arithmetic on the targets Mybody already computes:

- `단백질 40g 남았습니다 — 닭가슴살 200g이면 채워집니다` (target − logged, plus a suggestion from his own frequent-foods list)
- `오늘 칼로리 다 썼습니다 (2,180 / 2,150 kcal)`
- `탄수화물이 목표보다 60g 많습니다`
- `이번 주 단백질 달성률 78% — 4일 연속 미달입니다`

These are **100% reliable** because they're deterministic, and they're what the user actually asked for in message (2). **Ship the nudges and the manual logging first. They work perfectly. Then bolt photo on as an optional, always-editable convenience.**

---

## 11. What I could not verify

- **Hugging Face model metadata** (downloads, likes, exact file sizes, whether ONNX exports exist) — `huggingface.co` is proxy-blocked. All HF model claims are `[unverified]`.
- **Primary paper PDFs** — `arxiv.org`, `pmc.ncbi.nlm.nih.gov`, `biorxiv.org`, `openaccess.thecvf.com`, `ar5iv.labs.arxiv.org`, `awesomepapers.io` all blocked. **All paper numbers are `[secondary]`** — from search-engine summaries of those papers and of reviews citing them. The Nutrition5k table and the 2026 ten-model benchmark should be re-checked against the PDFs before anyone quotes them externally.
- **Open Food Facts Korean product count** — `kr.openfoodfacts.org` blocked.
- **Food-R1's GitHub repo URL** — claimed released, not located.
- **FoodLMM / SAM ViT-H exact model sizes** — estimates from architecture, not measured.
- **AI Hub dataset 74 vs 242 overlap** — both reported as ~842k/400종; likely the same build under two catalog entries.
- **누비랩's 95% accuracy** — company marketing, no independent evaluation found.
- **FatSecret Korean dataset presence** — 56 country datasets claimed, Korea not confirmed.

---

## Sources

- [LARC-CMU-SMU/FoodSeg103-Benchmark-v1](https://github.com/LARC-CMU-SMU/FoodSeg103-Benchmark-v1) · [FoodSeg103 project page](https://xiongweiwu.github.io/foodseg103.html) · [jamesjg/FoodSAM](https://github.com/jamesjg/FoodSAM) · [FoodSAM paper](https://arxiv.org/abs/2308.05938) · [jamesjg/FoodInsSeg](https://github.com/jamesjg/FoodInsSeg) · [NimaVahdat/FoodSeg_mask2former](https://github.com/NimaVahdat/FoodSeg_mask2former)
- [google-research-datasets/Nutrition5k](https://github.com/google-research-datasets/Nutrition5k) · [Nutrition5k paper](https://arxiv.org/pdf/2103.03375) · [CVPR 2021 PDF](https://openaccess.thecvf.com/content/CVPR2021/papers/Thames_Nutrition5k_Towards_Automatic_Nutritional_Understanding_of_Generic_Food_CVPR_2021_paper.pdf) · [Depth domain adaptation](https://arxiv.org/pdf/2208.12153) · [DPF-Nutrition](https://arxiv.org/pdf/2310.11702) · [Visual-Ingredient Feature Fusion](https://arxiv.org/pdf/2505.08747)
- [im2calories coverage (Fortune)](https://fortune.com/2015/06/02/google-calorie-count-photos) · [TechXplore](https://techxplore.com/news/2015-06-google-im2calories-calories-meal-photo.html)
- [YuehaoYin/FoodLMM](https://github.com/YuehaoYin/FoodLMM) · [Food-R1](https://arxiv.org/abs/2606.04986) · [Are VLMs Ready for Dietary Assessment?](https://arxiv.org/abs/2504.06925) · [Ten-model VLM benchmark (bioRxiv)](https://www.biorxiv.org/content/10.64898/2026.07.26.740845v1) · [same, PubMed](https://pubmed.ncbi.nlm.nih.gov/42619751/) · [NutriBench](https://arxiv.org/pdf/2407.12843) · [NutriBench project page](https://mehak126.github.io/nutribench.html) · [January Food Benchmark](https://arxiv.org/abs/2508.09966) · [Contextual metadata / ACETADA](https://arxiv.org/abs/2507.07048) · [DietDelta](https://arxiv.org/abs/2604.06352)
- [simonoppowa/OpenNutriTracker](https://github.com/simonoppowa/OpenNutriTracker) · [apoorvdarshan/fud-ai](https://github.com/apoorvdarshan/fud-ai) · [ignoxx/caloriemate](https://github.com/ignoxx/caloriemate) · [tahaygun/ai-calorie-tracker](https://github.com/tahaygun/ai-calorie-tracker) · [openfoodfacts-server](https://github.com/openfoodfacts/openfoodfacts-server) · [awesome-nutrition-tracking](https://github.com/jrhizor/awesome-nutrition-tracking) · [tonyslowdown/kfood-server](https://github.com/tonyslowdown/kfood-server)
- [AI Hub 음식 이미지 및 영양정보 텍스트](https://aihub.or.kr/aihubdata/data/view.do?dataSetSn=74) · [건강관리를 위한 음식 이미지](https://aihub.or.kr/aihubdata/data/view.do?dataSetSn=242) · [한국 이미지(음식)](https://aihub.or.kr/aihubdata/data/view.do?dataSetSn=79) · [AI Hub 이용정책](https://www.aihub.or.kr/intrcn/guid/usagepolicy.do?currMenu=151&topMenu=105)
- [식약처 식품영양성분DB OpenAPI (공공데이터포털)](https://www.data.go.kr/data/15127578/openapi.do) · [식품영양성분 데이터베이스](https://various.foodsafetykorea.go.kr/nutrient/) · [식약처 데이터활용서비스](https://www.foodsafetykorea.go.kr/apiMain.do) · [전국통합식품영양성분정보(음식) 표준데이터](https://www.data.go.kr/data/15100070/standard.do)
- [K-foodNet (Nutrition Research and Practice 2019)](https://koreascience.kr/article/JAKO201935236776891.page) · [Detecting Korean Food Using Hierarchical Model](https://arxiv.org/abs/2409.02448) · [누비랩](https://www.nuvilab.com/ko)
- [Transformers.js v3](https://huggingface.co/blog/transformersjs-v3) · [transformers.js repo](https://github.com/xenova/transformers.js/) · [AIY food_V1 on TF Hub](https://tfhub.dev/google/aiy/vision/classifier/food_V1/1) · [Food-101 SOTA (Papers with Code)](https://paperswithcode.com/sota/fine-grained-image-classification-on-food-101) · [FatSecret Platform API](https://platform.fatsecret.com/platform-api) · [Open Food Facts data](https://world.openfoodfacts.org/data)