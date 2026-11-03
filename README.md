# iOSExtendBattery

Battery statistics since unplugging, inside Settings → Battery.

## Features

- A **Since Unplugged** tab alongside the standard battery views.
- Native battery and activity charts, with Screen On and Screen Off time.
- Separate app and system-process lists, app icons and process diagnostics.
- Cycle history, comparisons and readable diagnostic exports.
- English and Hebrew, with light and dark appearance.

Requires a rootless jailbreak. Currently supported on **iOS 17.1.1**; tested on iPhone 15 Pro.
System accounting can update with a delay; unavailable measurements are shown explicitly.

## Build

Requires macOS, Xcode and [Theos](https://theos.dev/).

```sh
THEOS="$HOME/theos" make -C producerprobe package FINALPACKAGE=1
```

The installable `.deb` is generated in `producerprobe/packages/`. Install it with your package manager and reload the collector through your jailbreak's userspace restart. Reopen Settings afterward.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and local checks.

## License

[MIT](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md).
