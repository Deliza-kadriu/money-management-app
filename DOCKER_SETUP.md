# Docker Setup for Flutter Money Manager

## What Docker is good for here

Use Docker for:

- creating the Flutter project
- running `flutter pub get`
- running code generation
- running tests
- running static analysis
- keeping a consistent Flutter SDK version

## What Docker is not ideal for

For a Flutter mobile app, Docker is **not** a full replacement for native tooling.

Important limitations:

- iOS builds still require Xcode on the host Mac
- iOS simulator runs on the host, not inside the container
- Android emulator is usually better on the host machine
- signing and release packaging are still host-driven tasks

So the best setup is:

- Docker for shared CLI/dev environment
- Host machine for simulator/emulator and release signing

## Files included

- `Dockerfile`
- `docker-compose.yml`
- `.dockerignore`

## Build the image

```bash
docker compose build
```

## Open a shell in the Flutter container

```bash
docker compose run --rm flutter
```

## Create the Flutter project in this folder

If you want to initialize the app from inside Docker:

```bash
docker compose run --rm flutter flutter create .
```

If the folder already contains files, use:

```bash
docker compose run --rm flutter flutter create --project-name money_manager .
```

## Common commands

Install packages:

```bash
docker compose run --rm flutter flutter pub get
```

Run analyzer:

```bash
docker compose run --rm flutter flutter analyze
```

Run tests:

```bash
docker compose run --rm flutter flutter test
```

Generate code:

```bash
docker compose run --rm flutter dart run build_runner build --delete-conflicting-outputs
```

## Recommended workflow

1. Use Docker to create and maintain the Flutter environment.
2. Open the project locally in Android Studio or VS Code.
3. Run emulator/simulator from the host machine.
4. Use Docker for repeatable commands like analyze, test, and codegen.

## Suggested next project step

After building the image, initialize the Flutter app and then add:

- `flutter_riverpod`
- `go_router`
- `drift`
- `sqlite3_flutter_libs`
- `path_provider`
- `intl`
- `uuid`
- `flutter_local_notifications`
- `timezone`
- `fl_chart`
- `excel`

## Optional future Docker improvements

- separate CI image
- pinned Flutter version via ARG
- Android SDK image for debug builds
- Makefile shortcuts
- devcontainer support
