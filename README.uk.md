# Pixel 5 KernelSU-Next + SuSFS

[English](README.md) | [Українська](README.uk.md)

Цей репозиторій містить відтворюваний процес збирання зміненого ядра Android 14 для Google Pixel 5 (`redfin`). Отримане ядро інтегрує KernelSU-Next і застарілу SuSFS v2 та зберігає ABI, якого очікують стокові модулі в `/vendor`.

## Призначення

Проєкт перетворює закріплений вихідний код ядра Google на перевірюване ядро KernelSU-Next + SuSFS і пакує його в замінні образи `boot.img` та `vendor_boot.img`. Стоковий `vendor.img` використовується як еталон ABI і залишається вхідним артефактом.

KernelSU-Next і SuSFS підтримуються окремими групами патчів. Тому зовнішні ревізії, порядок патчів і зміни сумісності видимі в Git та можуть перевірятися й оновлюватися незалежно.

## Upstream-джерела

- **Ядро Google:** [android.googlesource.com/kernel/msm](https://android.googlesource.com/kernel/msm), гілка `android-msm-redbull-4.19-android14`, базовий коміт `7b0944645172e8b690d42f68c8973ccb0ca45730`. GitHub-дзеркало доступне в [aosp-mirror/kernel_msm](https://github.com/aosp-mirror/kernel_msm).
- **KernelSU-Next:** [sidex15/KernelSU-Next](https://github.com/sidex15/KernelSU-Next), ref `v3.3.0-legacy-susfs-v2`, коміт [`36679224f26d03f2bb105c4686cf390eb63178c2`](https://github.com/sidex15/KernelSU-Next/commit/36679224f26d03f2bb105c4686cf390eb63178c2).
- **Референсний порт SuSFS v2.2.0:** [sreeshankark/android_kernel_oneplus_avicii](https://github.com/sreeshankark/android_kernel_oneplus_avicii), гілка `14`, коміт [`3f46c998`](https://github.com/sreeshankark/android_kernel_oneplus_avicii/commit/3f46c998). Адаптація для Pixel 5 зафіксована в `patches/susfs-v2.2.0-redbull.patch`; під час збірки окреме дерево SuSFS не клонується.

Точні ревізії, які використовує збірка, записані в `config/versions.env`; файли патчів у цьому репозиторії є перевірюваним шаром інтеграції між цими джерелами та деревом ядра Pixel 5.

Серія також містить `susfs-mount-namespace-copy.patch`, який зберігає SUSFS mount ID під час копіювання наявного mount namespace через `CLONE_NEWNS`.

## Чому цей процес використовує legacy SuSFS v2

Ціллю є база Google Android 14 / Linux 4.19 для Pixel 5, закріплена у
`config/versions.env`. Процес використовує окремо перевірювану адаптацію
референсного порту v2.2.0 і відповідний ref інтеграції KernelSU-Next
`v3.3.0-legacy-susfs-v2`, бо повна серія патчів підтримується та ABI-перевіряється
саме для цієї бази. Це вибір сумісності, а не твердження, що інша гілка SuSFS
за своєю природою менш безпечна.

Міграцію на іншу лінію SuSFS наразі не оголошено. Таку міграцію слід вважати
новою інтеграцією: закріпити кандидатні вихідні тексти, перебазувати кожен
патч з `patches/series`, застосувати їх без fuzz, виконати чисте збирання й
вимагати ABI-звіт стокового vendor без розбіжностей перед пакуванням або
тестуванням на пристрої.

## Ліцензія та походження

Виконувані матеріали й оригінальні інтеграційні патчі ліцензовані як
`GPL-2.0-only`; документація README і guide — як `CC-BY-4.0`. Патчі, похідні
від upstream-проєктів, зберігають застосовні до них upstream-повідомлення та
умови. Сферу дії описано у [LICENSE](LICENSE), а походження сторонніх
матеріалів — у [NOTICE](NOTICE).

## Вхідні дані

- Checkout ядра Android 14 для Pixel 5 (`redfin`) у WSL/Linux.
- Відповідні заводські `boot.img`, `vendor_boot.img` та `vendor.img` в одному каталозі `stock-images/`.
- Інструменти збірки ядра Android і platform tools (`repo`, Git, Python 3, `lz4`, `cpio`, `mkbootimg`, `unpack_bootimg`, `avbtool`, `fastboot` та `adb`).
- Розблокований bootloader для тестування на пристрої.

Закріплені база Google і ревізія KernelSU-Next записані в `config/versions.env`. Порядок застосування патчів визначений у `patches/series`.

## Результати

Скрипт збирання створює ядро та машинозчитувані файли доказів у `out/android-msm-pixel-4.19/dist/`:

- `Image.lz4-dtb` і `vmlinux`;
- `ksu-next-susfs-build-proof.txt` із хешами вихідних текстів, конфігурації, перевірок цілісності та образів;
- `stock-vendor-module-abi-kmi-full-report.txt`, у якому мають бути нуль CRC-розбіжностей і нуль відсутніх символів.

Після успішного збирання та ABI-аудиту скрипт пакування створює замінні `boot.img` і `vendor_boot.img` у новому каталозі в `repacked-images/`. Рядок версії ідентифікує коміт інтеграції, наприклад `4.19.278-ksun-susfs-g<integration-sha>`.

Жоден зі скриптів не прошиває пристрій. Прошивання є окремим ручним кроком із використанням створених образів; докладний посібник також охоплює перевірку та відновлення.

## Робочий процес

1. Підготуйте або синхронізуйте робочу копію ядра та розмістіть відповідні стокові образи в `stock-images/`.
2. Запустіть `build_ksu_next_susfs_kmi.sh`, щоб повернутися до закріпленої бази, застосувати серію патчів, зібрати ядро та виконати ABI-аудит стокових модулів vendor.
3. Продовжуйте лише після успішної збірки, коли доказ і ABI-звіт показують нуль розбіжностей.
4. Запустіть `package_kernel_images.sh`, щоб створити `boot.img` та `vendor_boot.img`.
5. Перевірте пакет і, за потреби, вручну прошийте створені образи.

Повна інструкція зі збирання, пакування, прошивання, перевірки, відновлення та оновлення наведена в [guide.uk.md](guide.uk.md).
