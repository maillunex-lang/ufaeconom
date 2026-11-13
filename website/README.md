# BUSINESS EMPIRE ONLINE: Liquid Glass landing

Public URL: https://rikagro.ru/business-empire/

This is separate from the existing Agro Empire Online site at /agrogame/. Deployment directory: /var/www/rikagro-game/business-empire/. No Nginx modification or new service was required.

## Sources and assets

- website/index.html: Russian-language responsive single-page site. No trackers, external fonts, framework, autoplay or remote CDN.
- website/refresh_latest.py: validates the next APK and atomically updates the public alias and JSON metadata.
- icon.svg: reused for favicon.
- assets/gameplay-ufa.jpg, assets/gameplay-city-closeup.jpg, assets/gameplay-sterlitamak.jpg: actual 1280x720 frames captured from the game scene with Godot 4.6 on Lunex via virtual X11. Two real owned plots and production data were set up using the game's own methods in an isolated clone. These JPEG files are served from VPS, not in GitHub.

## Publishing updates

Install website/index.html to /var/www/rikagro-game/business-empire/index.html.
Install icon.svg into /var/www/rikagro-game/business-empire/assets/icon.svg.
Install website/refresh_latest.py to /opt/ufaeconom-landing/refresh_latest.py.

A 5-minute cron is configured at /etc/cron.d/ufaeconom-landing-apk:

    */5 * * * * root /usr/bin/python3 /opt/ufaeconom-landing/refresh_latest.py >> /var/log/ufaeconom-landing-apk.log 2>&1

The script scans only /var/www/rikagro-game/agrogame/download/BusinessEmpireOnline-X.Y[-Z]-debug.apk (or -release.apk). For each candidate it validates APK metadata, package com.ufaeconom.business, filename version, Android signature and known certificate digest. The highest validated versionCode is selected; downgrades and swapping a changed APK with an identical version code are refused. A valid new release atomically updates /business-empire/download/BusinessEmpireOnline-latest.apk and /business-empire/release/latest.json.

**When a new version is built:** put the fully built APK into the watched download directory with the correct file name. Within the next 5-minute scan, the site switches automatically if the APK passes all checks. The site does NOT build the APK or update an already-installed app on a phone. A release signed by a new certificate requires manual review.

Initial verified release: **0.4.0** (versionCode 4), 27,575,788 bytes, SHA-256 8fc240d97967adc59df8d074a79978579799ef2f6dcd6da3f4f3358a12e3abf5.

The game's main source includes some 0.5 systems, but no 0.5 Android APK was published during initial landing deployment. Future features are explicitly marked as in-development on the site.

## Quality controls and limitations

HTML static checks include correct screenshot alt text, main CTA, responsive CSS breakpoints, one small inline JS script, dialog, reduced-motion and reduced-transparency preferences, forced-color and no-blur fallbacks. The hero screenshot is preloaded; gallery screenshots load lazily.

Actual browser rendering across 360, 390, 768 and 1440px, 200% zoom and real field CWV metrics were NOT measured in the first deployment because no browser was available on Lunex. These remain useful QA follow-ups. No success in real downloads/installs or conversion rate is claimed from HTTP checks alone.

Do not modify the existing /agrogame/ landing, running game services, Nginx configuration or unrelated APKs.
