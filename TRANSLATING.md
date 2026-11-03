# Translating iOSExtendBattery

Anyone can propose a translation or correction through a GitHub pull request. You do not need a jailbroken device or Xcode to edit translations. Changes are reviewed and tested before inclusion in a release; submitting a correction does not publish a package automatically.

## Fix a translation

1. Open `Resources/Localizations/<language>.lproj/Localizable.strings` on GitHub.
2. Click the pencil button. GitHub can create a fork for your proposed edit.
3. Change the text on the **right** of `=`. Keep the key on the left unchanged. The matching English text is in `en.lproj/Localizable.strings`.
4. Submit a pull request, naming the language and briefly explaining the correction.

If you prefer not to edit files, [open a translation correction issue](https://github.com/twomee/ios-extend-battery-release/issues/new?template=translation.yml). Include the current text, your suggested wording and the language.

Each entry has this format:

```text
"SCREEN_ON" = "Your translation";
```

Keep semicolons, quotation marks, `\n`, and meaningful spaces at the start/end. Escape a quotation mark as `\"`. Save as UTF-8. Prefer concise labels, but preserve the meaning of diagnostic explanations.

## Format arguments and technical meaning

Preserve placeholders such as `%@`, `%ld` and `%lu`, including their types. `%%` displays a literal percent sign. If the argument order must change, use positional placeholders consistently, for example `%2$@` and `%1$ld`. The validator rejects unsafe or incompatible formats.

Unavailable data is **unknown**, not zero. CPU time is cumulative for a process lifetime; it is not measured battery energy. Relative consumption estimates are not battery percentage points lost. Preserve those distinctions. Keep technical process names, JSON/TXT and units recognizable. Do not manually reverse RTL text or add direction controls to compensate for layout.

## Add a language

Create `<Apple-language-code>.lproj/Localizable.strings` under `Resources/Localizations/`, using the English catalog as a reference. Examples: `nl`, `pt-PT`, `zh-Hant`. Add translated entries with the same keys. Partial catalogs are accepted: missing entries use English. Empty values, unknown/duplicate keys and invalid formats are rejected. English entry coverage does not establish translation quality.

The tweak selects a supported language using the system's language preferences, with English fallback. Language resources are bundled locally; no translation service or network request runs on the phone.

## Validate

With Python 3.11+:

```sh
python3 tools/validate-localizations.py
python3 -m unittest discover -s tests -p test_localizations.py
```

`--strict` additionally requires every English entry in every language. On macOS you can also run `plutil -lint` on the changed file. Full interface acceptance runs on Simulator with fixtures; it cannot judge whether a phrase sounds natural. Native-speaker feedback is welcome.

## Initial translation status

English and Hebrew preserve the existing interface. Arabic (`ar`), German (`de`), Spanish (`es`), French (`fr`), Italian (`it`), Japanese (`ja`), Korean (`ko`), Brazilian Portuguese (`pt-BR`), Russian (`ru`), Ukrainian (`uk`), Simplified Chinese (`zh-Hans`) and Traditional Chinese (`zh-Hant`) start as machine-assisted drafts. Automated checks do not mean these drafts have native-speaker approval.

Translation contributions use the project's MIT license. Mention your preferred credit in the pull request if you would like attribution.
