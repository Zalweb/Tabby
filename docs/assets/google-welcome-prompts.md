# Google welcome mascot artwork

Generated for [QA-025](../progress/tasks/QA-025.md) on 2026-11-17 using the built-in image generation tool with transparent_background=true. The user-supplied [login illustration](../../assets/branding/Tabby%20Cat%20Expense%20Tracker%20Login.png) was the character/style reference only. All15 introduction references in assets/reference/introduction reference idea informed native screen layout, not additional product capabilities. Generated PNGs were copied into the project without raster editing; text, gradients, controls and motion are native Flutter UI.

## Welcome prompt

Output: [tabby-welcome-v3.png](../../assets/branding/tabby-welcome-v3.png). Used on login and the first/last introduction screens. Source generation: exec-ea32c28b-64d1-4baf-bcf8-509612358096.png.

```text
Use case: illustration-story. Asset type: transparent production mobile welcome/onboarding mascot asset for Tabby. Input image is CHARACTER AND STYLE REFERENCE only; do not reproduce its UI, text, status bar or surrounding icons. Create the exact same charcoal-black tabby cat with gray forehead/body/tail stripes, white muzzle/chest/paws, orange inner ears and nose, big glossy oval eyes and bold clean black outlines. One joyful full-body cat doing a small welcoming hop, both front paws lifted with soft pink paw pads, one eye winking and friendly open smile, curved striped tail. Warm, cute, polished clean 2D cartoon, subtle simple shading. Preserve the cat identity and normal anatomy. Composition centered in square, all ears/paws/tail visible with 12 percent padding. Truly transparent background. No objects, icons, coins, speech bubbles, typography, logo, status bar, floor shadow or background scene. Single cat only. For an uncluttered cream and amber Google-only sign-in page.
```

## Notebook prompt

Output: [tabby-notebook-v3.png](../../assets/branding/tabby-notebook-v3.png). Used on shared-expense introduction and profile setup. Source generation: exec-e03dccdd-a23c-4fcc-bcf2-9f1c4568655a.png.

```text
Use case: illustration-story. Asset type: transparent production mobile introduction mascot asset for Tabby expense sharing. Input image is CHARACTER AND STYLE REFERENCE only, not a UI to reproduce. Draw the exact same charcoal-black/gray tabby cat, white muzzle/chest/paws, warm orange inner ears and nose, large glossy eyes, rounded proportions and clean bold outlines. Friendly calm sitting full-body pose, holding ONE small plain warm-cream notebook with an emerald green spine against its chest and gently pointing to it with a paw. No text or numbers on the notebook. Curved striped tail and both ears/paws fully visible. Warm polished 2D cartoon, simple subtle shading, centered square composition with 12 percent clear padding. Genuinely transparent background. One cat and one notebook only. No other icons, currency, bills, UI, logo, text, speech bubbles, badges, symbols, scene or floor shadow. Maintain identical character identity to the reference.
```

## Other assets and behavior

[google-g.png](../../assets/branding/google-g.png) is the official Google raster mark downloaded from https://developers.google.com/identity/images/g-logo.png, not generated art. The existing launcher icon from [QA-023](mascot-launcher-prompts.md) remains packaged. Generated characters have no embedded interface text. A subtle vertical float pauses on background/hidden routes and respects reduced motion; these are illustrations, not a newly generated frame-by-frame sprite animation.

Phone/tablet/light/dark previews use real production widgets with fixture text and an Arial substitute for unavailable Inter. Native isolated tablet cases decode and render the actual assets. [Verification and limits](../verification/VER-QA-025-GOOGLE-ENTRY.md).
