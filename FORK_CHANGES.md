# Зміни у форку sanyazar/qgroundcontrol

Форк базується на `mavlink/qgroundcontrol` (ревізія `fba7dfc`, 22.10.2026) і додає:

1. **Мультикамера** — одночасний показ кількох відеопотоків: кілька камер на одному дроні, кілька дронів, або все разом.
2. **Пакування** — MSI-інсталятор для Windows і Docker-образ для його збірки; `.deb` для Ubuntu збирається наявним Linux-образом.
3. **Назва QGroundControl-Bastion** — усі імена й шляхи відрізняються від оригіналу, тож обидві версії можна встановити одночасно.
4. **GitHub Actions** — автоматична збірка `.deb` і `.msi`.

Документація для користувача англійською (як і решта документації QGC): [Multiple Cameras](docs/en/qgc-user-guide/fly_view/multi_camera.md), розділ **Multiple Cameras** у [Video settings](docs/en/qgc-user-guide/settings_view/video.md), збірка пакетів — [Building using Containers](docs/en/qgc-dev-guide/getting_started/container.md#native-packages-deb-and-msi).

## Коміти

| Коміт | Опис |
| ----- | ---- |
| `feat(Video): show multiple camera streams from multiple vehicles` | Мультикамера: C++ менеджер потоків, QML-вигляд, налаштування, unit-тест |
| `build(Windows): add MSI packaging and Windows Docker builder` | CPack WIX, пресет `Windows-msi`, `Dockerfile.windows`, тест пакування |
| `docs: document multi-camera mode and fork changes` | Документація |
| `build: rename to QGroundControl-Bastion and add package workflow` | Перейменування, `packages.yml` |

## 1. Мультикамера

### Як користуватися

1. **Налаштування → Video → Multiple camera streams** — увімкнути.
2. **Maximum streams** — скільки потоків декодувати одночасно (за замовчуванням 4, від 1 до 9).
3. **Manual Camera Streams** — додати потоки вручну, по рядку на камеру:
   - **Vehicle ID** — MAVLink SYSID дрона (`0` — не прив'язаний до дрона);
   - **Name** — підпис на плитці, напр. `Front`, `Thermal`;
   - **Stream URL** — `rtsp://…`, `udp://0.0.0.0:5600`, `udp265://…`, `mpegts://…`, `tcp://…`.
4. Камери, які підтримують MAVLink camera protocol, з'являються самі — з усіх підключених дронів.

У Fly View:

- велике відео — головний потік, угорі по центру — мініатюри решти;
- **клік по мініатюрі** — зробити її головною (потоки не перезапускаються);
- **подвійний клік по головному** — повний екран;
- **червоне коло** на плитці — запис цього потоку (окремий файл), **іконка камери** — фото з кадру;
- червона крапка біля назви — потік зараз пишеться.

Файли: `<папка відео>/2026-10-22_20.15.03.Vehicle_1_Front.mkv`, `<папка фото>/2026-10-22_20.15.07.512.Vehicle_2_Down.jpg`.

### Правила підбору потоків

- спочатку ручні, потім MAVLink, доки не досягнуто **Maximum streams**;
- потоки з однаковим URL відкидаються (ручний має пріоритет) — два приймачі не можуть ділити один UDP-порт чи RTSP-сесію;
- для кожного нового MAVLink-потоку QGC надсилає камері `MAV_CMD_VIDEO_START_STREAMING`;
- дрон підключився/відключився — список оновлюється автоматично.

### Обмеження

- у мультирежимі вимкнено керування підвісом і трекінг кліком по відео (головний потік може належати не активному дрону);
- для записів мультикамери не пишуться субтитри з телеметрією;
- спільні для всіх потоків налаштування: Low Latency Mode, RTP jitter buffer, RTSP timeout, auto-reconnect;
- нові написи в інтерфейсі англійською — українською з'являться після перекладу.

### Як це влаштовано

| Файл | Роль |
| ---- | ---- |
| `src/VideoManager/MultiCameraManager.{h,cc}` | Збирає список потоків (ручні з налаштувань + `VIDEO_STREAM_INFORMATION` усіх камер усіх дронів), ліміт, дедуплікація, вибір головного. Доступний у QML як `QGroundControl.videoManager.multiCamera` |
| `src/VideoManager/MultiCameraStream.{h,cc}` | Один потік: власний `VideoReceiver` + sink, прив'язаний до свого `VideoOutput`; старт/рестарт, запис, фото |
| `src/VideoManager/VideoManager.{h,cc}` | Створює менеджер, передає йому готовність GStreamer, у мультирежимі не запускає свої одиночні приймачі й не зупиняє потік попереднього активного дрона |
| `src/FlyView/MultiCameraView.qml` | Головне відео + мініатюри, кнопки запису/фото |
| `src/FlyView/FlyViewVideo.qml`, `FlyView.qml` | Перемикання між звичайним відео й мультикамерою, PiP |
| `src/AppSettings/MultiCameraSettings.qml`, `pages/Video.SettingsUI.json` | Сторінка налаштувань і редактор ручних потоків |
| `src/Settings/Video.SettingsGroup.json`, `VideoSettings.{h,cc}` | Факти `multiCameraEnabled`, `multiCameraMaxStreams`, `multiCameraStreams` (JSON) |
| `test/VideoManager/MultiCameraManagerTest.{h,cc}` | Перетворення MAVLink URI, ручні потоки, ліміт, дедуплікація, головний потік |

Кожна плитка має власний `VideoOutput` на весь час життя потоку: перемикання головного змінює лише геометрію, тож sink не перепідключається. Приймач знищується до того, як QML видаляє `VideoOutput` (`detachVideoOutput` у `Component.onDestruction`).

## 2. Пакування

### Ubuntu `.deb`

Наявний Linux-образ на Ubuntu вже збирає `.deb` поруч з AppImage:

```bash
python3 deploy/docker/run_docker.py build ubuntu       # Ubuntu 24.04
python3 deploy/docker/run_docker.py build ubuntu-2204  # Ubuntu 22.04
sudo apt install ./build/qgroundcontrol-bastion_*.deb  # встановлюється в /opt/QGroundControl-Bastion
```

### Windows `.msi`

- `cmake/install/CPack/CreateCPackWIX.cmake` — CPack-генератор `WIX` (WiX Toolset 5, `CPACK_WIX_VERSION 4`): встановлення для всіх користувачів, ярлики в «Пуск» і на робочому столі, фіксований `CPACK_WIX_UPGRADE_GUID` — нова версія оновлює стару на місці. **GUID не змінювати.**
- `QGC_CPACK_GENERATOR=WIX` або пресет `Windows-msi`.
- `deploy/docker/Dockerfile.windows` + `deploy/docker/build-windows.ps1` — образ із MSVC Build Tools, Qt, GStreamer, WiX; збирає `.msi` у змонтовану папку.

Windows-контейнери працюють **лише на Windows-хості** (Windows 11 Pro / Server 2022, Docker у режимі Windows containers):

```powershell
docker build -f deploy/docker/Dockerfile.windows -t qgc-windows-docker .
docker run --rm -m 16g --cpus 8 `
    -v "${PWD}:C:\project\source" -v "${PWD}\build\docker-windows:C:\project\build" `
    qgc-windows-docker
# результат: build\docker-windows\QGroundControl-Bastion-<версія>-AMD64.msi
```

Без Docker, на машині з MSVC, Qt і `wix`:

```powershell
cmake --preset Windows-msi
cmake --build --preset Windows-msi --target qgc-package
```

## 3. QGroundControl-Bastion поруч з оригіналом

Імена задані в `cmake/CustomOptions.cmake` (`QGC_APP_NAME`, `QGC_ORG_NAME`, `QGC_PACKAGE_NAME`); пакування й лаунчери беруть їх звідти.

| Що | Оригінал | Bastion |
| -- | -------- | ------- |
| Пакет `.deb` / `.rpm` | `qgroundcontrol` | `qgroundcontrol-bastion` |
| Файл `.deb` | `qgroundcontrol_<версія>_amd64.deb` | `qgroundcontrol-bastion_<версія>_amd64.deb` |
| Каталог встановлення (Linux) | `/opt/QGroundControl` | `/opt/QGroundControl-Bastion` |
| Команда запуску | `/usr/bin/QGroundControl` | `/usr/bin/QGroundControl-Bastion` |
| Ярлик / іконки | `org.mavlink.qgroundcontrol.desktop`, `QGroundControl.png` | `org.mavlink.qgroundcontrol.bastion.desktop`, `QGroundControl-Bastion.png` |
| AppImage | `QGroundControl-x86_64.AppImage` | `QGroundControl-Bastion-x86_64.AppImage` |
| Windows | `Program Files\QGroundControl`, NSIS `.exe` | `Program Files\QGroundControl-Bastion`, `QGroundControl-Bastion-<версія>-AMD64.msi` |
| Налаштування (Linux) | `~/.config/QGroundControl/` | `~/.config/QGroundControl-Bastion/` |
| Дані (логи, місії, відео) | `~/Documents/QGroundControl` | `~/Documents/QGroundControl-Bastion` |
| Android | `org.mavlink.qgroundcontrol` | `org.mavlink.qgroundcontrol.bastion` |

Збірки не з релізного тегу (як і в оригіналі) додають до назви застосунку « Daily», тож налаштування й дані лежать у `…/QGroundControl-Bastion Daily`.
Ім'я пакета Debian не може містити `_` (це роздільник між назвою й версією у файлі), тому пакет називається `qgroundcontrol-bastion`.

Після перейменування стару папку збірки треба видалити (`rm -rf build`): CMake кешує старі імена.

Не перейменовано: валідатори пакетів і workflow офіційного QGC (`.github/scripts/validate_native_package.py`, `deploy/docker/validate_native_package.py`, `linux.yml`, `docker.yml`) — вони, як і раніше, очікують `QGroundControl` і у форку не використовуються.

## 4. GitHub Actions

`.github/workflows/packages.yml` (**Bastion Packages**):

- **Ubuntu .deb** — збирає Docker-образом `ubuntu`, перевіряє, що пакет називається `qgroundcontrol-bastion`; артефакт `qgroundcontrol-bastion-linux` (`.deb`, `.sha256`, AppImage);
- **Windows .msi** — `windows-2022`, Qt MSVC, GStreamer, WiX 5, пресет `Windows-msi`; артефакт `qgroundcontrol-bastion-windows`;
- **GitHub release** — для тегів `vX.Y.Z…` публікує обидва пакети як реліз.

Запускається: кнопкою **Run workflow** на вкладці Actions, пушем у `feat/multi-camera` (крім змін лише в документації) і тегом:

```bash
git tag v5.2.1 && git push fork v5.2.1
```

Артефакти зберігаються 30 днів: Actions → запуск → **Artifacts**.
Workflow офіційного QGC у форку запускаються лише для `master`, тегів `vX.Y.Z` і pull request'ів, тож пуші у `feat/multi-camera` їх не чіпають.

## Перевірка

```bash
just build
ctest -R MultiCameraManagerTest --output-on-failure
just lint
```

Ручна перевірка мультикамери без заліза — два SITL-дрони й тестові потоки GStreamer, див. розділ **Testing Without Hardware** у [Multiple Cameras](docs/en/qgc-user-guide/fly_view/multi_camera.md#testing-without-hardware).

## Оновлення з upstream

```bash
git remote add upstream https://github.com/mavlink/qgroundcontrol.git
git fetch upstream
git rebase upstream/master   # конфлікти найімовірніші у VideoManager.cc, FlyViewVideo.qml, Video.SettingsUI.json
```
