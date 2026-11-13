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


## Синхронизация релизных каналов (обновление 13.11.2026)

`website/refresh_channels.py` отдельно от стабильного обновлятора проверяет наличие подписанных бета-APK в `/var/www/rikagro-game/business-empire/beta/` и публикует `/business-empire/release/channels.json`. Проверяются packageId, versionCode, версия в имени файла и пакете, известный Android signing cert, SHA-256 и размер. Копирование/переименование беты без корректной подписи и согласованной версии не делает её релизом.

Пример настройки существующего cron (отдельная строка, только после установки и проверки):

```cron
*/5 * * * * root /usr/bin/python3 /opt/ufaeconom-landing/refresh_channels.py >> /var/log/ufaeconom-landing-channels.log 2>&1
```

Стабильный канал и бета различаются: `latest.apk` обновляется только старым стабильным release workflow. Beta располагается в `beta/BusinessEmpireOnline-X.Y.Z-beta.apk`, является отдельным дополнением сайта, не вытесняет стабильную версию и не запускает MMO backend.

`website/index.html` показывает отдельную бета-карточку, версию и размер из JSON без полного перерисовывания страницы. Если последний контрольный JSON временно недоступен, сохраняется вручную проверенная безопасная ссылка на 0.7.0-beta; не происходит подмены на неизвестный APK.

Проверки:

```sh
python3 -m unittest -v website.test_refresh_channels
python3 -m website.refresh_channels --stable /var/www/rikagro-game/business-empire/release/latest.json --beta-dir /var/www/rikagro-game/business-empire/beta --output /tmp/business-empire-channels-qa.json
```

**Граница автоматизации:** Release checker обновляет только **подтверждённые файлы сборок и их метаданные**. Он не создаёт APK, не публикует закрытые GitHub-ветки, не переписывает описания игровых механик сам по себе и не выставляет тестовый сервер наружу. При появлении новых систем текстовые разделы и скриншоты требуют проверки и отдельного обновления в репозитории.

Подтверждённая бета 0.7.0-beta: 27 618 811 байт; SHA-256 `cb28533d8b2b303b106c098940a319d63e75937b87fb7d8d03edecc14c07bbb3`. Публичный MMO-сервер пока не запущен; на реальных Android-телефонах версия не тестировалась.

