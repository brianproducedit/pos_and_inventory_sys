# Environment Variables Setup

This project uses the `envied` package to manage environment variables securely.

## Setup

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Update the values in `.env` as needed for your environment.

3. Run the code generator:
   ```bash
   flutter pub run build_runner build
   ```

## Usage

Import the environment class and use the variables:

```dart
import '../config/env.dart';

// Use the base URL
final url = '${Env.baseUrl}/api/endpoint';

// Access other environment variables
// final apiKey = Env.apiKey;
```

## Adding New Environment Variables

1. Add the variable to your `.env` file:
   ```
   NEW_VARIABLE=value
   ```

2. Add it to the `Env` class in `lib/config/env.dart`:
   ```dart
   @EnviedField(varName: 'NEW_VARIABLE')
   static const String newVariable = _Env.newVariable;
   ```

3. Run the code generator:
   ```bash
   flutter pub run build_runner build
   ```

## Security Notes

- The `.env` file is automatically excluded from version control via `.gitignore`
- Environment variables are compiled into the app at build time
- Never commit the actual `.env` file with sensitive information