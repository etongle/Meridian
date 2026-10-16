# Third-party notices

## Sparkle

Sparkle 2.10.0 is distributed under its BSD-style license. The unmodified license is bundled in the framework included in the application. Source and full terms: https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE

## Open-Meteo

Weather API: https://open-meteo.com/ . Weather data attribution and endpoint terms are available from https://open-meteo.com/en/terms and the API documentation. The default free endpoint is intended for non-commercial use. These service terms are separate from Meridian's own noncommercial software license; they do not grant commercial rights to Meridian.

## Global region metadata

Representative region names, country codes, coordinates and legacy identifier mappings use IANA tzdb 2026e. The included `zone.tab` and `backward` files are in the public domain. Source: https://www.iana.org/time-zones . The source archive SHA-256 is `b26882805f26aac59d5b222978e6580484b834ccdc98be89df2f05a6dc53a652`. Original files and license are in `ThirdParty/TimeZones/`; the license is included in the app as `TimeZones-LICENSE.txt`. Time calculations continue to use macOS time-zone rules.

English and Simplified Chinese exemplar city names use Unicode CLDR, revision `91c267402229a59e3ef2774544f001bf959e8809`, under Unicode License V3. Source: https://github.com/unicode-org/cldr-json . Original data and license are in `ThirdParty/CLDR/`; the full notice is included in the app as `CLDR-LICENSE.txt`.

`scripts/generate-world-regions.py` reproduces the compiled catalog from these vendored files. Builds do not fetch location data at runtime.

## Brand artwork

The Meridian app icon and launch posters were generated for this project using the built-in image generation tool, with the actual native application screenshot as the product reference. Prompts are recorded in BRAND.md. No third-party brand or App Store endorsement is implied.
