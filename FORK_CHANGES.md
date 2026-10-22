# Зміни у форку sanyazar/qgroundcontrol

Форк базується на `mavlink/qgroundcontrol` (ревізія `fba7dfc`, 22.10.2026) і додає:

1. **Мультикамера** — одночасний показ кількох відеопотоків: кілька камер на одному дроні, кілька дронів, або все разом.
2. **Пакування** — MSI-інсталятор для Windows і Docker-образ для його збірки; `.deb` для Ubuntu збирається наявним Linux-образом.
3. **Назва QGroundControl-Bastion** — усі імена й шляхи відрізняються від оригіналу, тож обидві версії можна встановити одночасно.
4. **GitHub Actions** — автоматична збірка `.deb`, `.apk` і `.msi`, на серверах GitHub або на власних машинах.

Документація для користувача англійською (як і решта документації QGC): [Multiple Cameras](docs/en/qgc-user-guide/fly_view/multi_camera.md), розділ **Multiple Cameras** у [Video settings](docs/en/qgc-user-guide/settings_view/video.md), збірка пакетів — [Building using Containers](docs/en/qgc-dev-guide/getting_started/container.md#native-packages-deb-and-msi).

## Коміти

| Коміт | Опис |
| ----- | ---- |
| `feat(Video): show multiple camera streams from multiple vehicles` | Мультикамера: C++ менеджер потоків, QML-вигляд, налаштування, unit-тест |
| `build(Windows): add MSI packaging and Windows Docker builder` | CPack WIX, пресет `Windows-msi`, `Dockerfile.windows`, тест пакування |
| `docs: document multi-camera mode and fork changes` | Документація |
| `build: rename to QGroundControl-Bastion and add package workflow` | Перейменування, `packages.yml` |
| `ci(packages): fetch upstream version tags before packaging` | Виправлення версії `0.0.0` у CI |
| `ci(packages): add Android APK and self-hosted runner support` | `.apk`, підпис, вибір раннера |
| `ci(packages): build a .deb for each supported Ubuntu release` | `.deb` для 22.04 / 24.04 / 26.04 |
| `feat(Video): add Dahua, Hikvision and Uniview camera presets` | Пресети камер |
| `ci(packages): check Docker access on self-hosted runners` | Зрозуміла помилка, якщо раннер не має доступу до Docker |
| `feat(Comms): configure cameras per comm link` | Камери в діалозі comm link, назва в правому нижньому куті |

## 1. Мультикамера

### Як користуватися

1. **Налаштування → Video → Multiple camera streams** — увімкнути (або перемикачем **Show cameras in the Fly View** у діалозі comm link).
2. **Maximum streams** — скільки потоків декодувати одночасно (за замовчуванням 4, від 1 до 9).
3. **Камери дрона — у його comm link** (основний спосіб): **Налаштування → Comm Links → Edit** (або **Add New Link**) → під налаштуваннями зв'язку розділ **Cameras** → **Add Camera** для кожної камери. Усі налаштування камери згруповані в одній картці. Камери зберігаються разом з link і показуються, поки link підключено.
4. **Other Camera Streams** (Налаштування → Video) — камери, не прив'язані до comm link; ті самі поля плюс **Vehicle ID**.

Поля камери (однакові в обох місцях):
   - **Vehicle ID** — лише в Other Camera Streams: MAVLink SYSID дрона (`0` — не прив'язаний до дрона);
   - **Name** — назва, що показується в правому нижньому куті відео (і в мініатюрі, і в головному), напр. `Front`, `Thermal`;
   - **Camera type** — **Dahua**, **Hikvision**, **Uniview (UNV)** або **Custom URL**;
   - для **Custom URL**: **Stream URL** — `rtsp://…`, `udp://0.0.0.0:5600`, `udp265://…`, `mpegts://…`, `tcp://…`;
   - для пресетів: **Camera address** (IP), **RTSP port** (за замовчуванням `554`), **Login** (`admin`), **Password**, **Channel** (`1`, на NVR — номер камери), **Stream** (Main — повна якість, Sub — легший потік). URL будується сам і показується під полями з прихованим паролем.
5. Камери, які підтримують MAVLink camera protocol, з'являються самі — з усіх підключених дронів.

У Fly View:

- велике відео — головний потік, угорі по центру — мініатюри решти;
- **клік по мініатюрі** — зробити її головною (потоки не перезапускаються);
- **подвійний клік по головному** — повний екран;
- назва камери — у правому нижньому куті кожної плитки;
- **червоне коло** в лівому нижньому куті плитки — запис цього потоку (окремий файл), **іконка камери** поруч — фото з кадру;
- червона крапка біля назви — потік зараз пишеться.

Файли: `<папка відео>/2026-10-22_20.15.03.Vehicle_1_Front.mkv`, `<папка фото>/2026-10-22_20.15.07.512.Vehicle_2_Down.jpg`.

### Пресети камер

| Тип | RTSP URL (канал 1) |
| --- | ------------------ |
| Dahua | `rtsp://<адреса>:<порт>/cam/realmonitor?channel=1&subtype=0` (sub: `subtype=1`) |
| Hikvision | `rtsp://<адреса>:<порт>/Streaming/Channels/101` (sub: `102`; канал 2 — `201`/`202`) |
| Uniview (UNV) | `rtsp://<адреса>:<порт>/unicast/c1/s0/live` (sub: `s1`) |

Логін і пароль передаються камері через RTSP-автентифікацію GStreamer (`user-id`/`user-pw`) і не потрапляють у логи: ключ потоку містить лише хеш URL.
Паролі зберігаються у файлі налаштувань QGC відкритим текстом (як і будь-які URL потоків), тож краще завести на камері окремий обліковий запис лише з правом перегляду.
Код: `MultiCameraManager::manualStreamUri()` / `manualStreamPreview()`, тест `_testCameraPresetUris`.

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
| `src/VideoManager/MultiCameraManager.{h,cc}` | Збирає список потоків (камери підключених comm link → інші ручні потоки → `VIDEO_STREAM_INFORMATION` усіх камер усіх дронів), ліміт, дедуплікація, вибір головного. Доступний у QML як `QGroundControl.videoManager.multiCamera` |
| `src/VideoManager/MultiCameraStream.{h,cc}` | Один потік: власний `VideoReceiver` + sink, прив'язаний до свого `VideoOutput`; старт/рестарт, запис, фото |
| `src/VideoManager/VideoManager.{h,cc}` | Створює менеджер, передає йому готовність GStreamer, у мультирежимі не запускає свої одиночні приймачі й не зупиняє потік попереднього активного дрона |
| `src/FlyView/MultiCameraView.qml` | Головне відео + мініатюри, кнопки запису/фото |
| `src/FlyView/FlyViewVideo.qml`, `FlyView.qml` | Перемикання між звичайним відео й мультикамерою, PiP |
| `src/AppSettings/CameraStreamsEditor.qml` | Редактор списку камер (картка на камеру, пресети); використовується в діалозі comm link і в налаштуваннях Video |
| `src/AppSettings/LinkConfigurationManager.qml` | Розділ **Cameras** у діалозі comm link |
| `src/Comms/LinkConfiguration.{h,cc}`, `LinkManager.cc` | Властивість `cameras` (JSON) у кожного link, копіювання при редагуванні, збереження в `LinkConfigurations/LinkN/cameras` |
| `src/AppSettings/MultiCameraSettings.qml`, `pages/Video.SettingsUI.json` | Сторінка Video: Other Camera Streams |
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

- **Ubuntu .deb** — окремий пакет для Ubuntu 22.04, 24.04 і 26.04 (Docker-образи `ubuntu-2204`, `ubuntu`, `ubuntu-2604`), бо кожен прив'язаний до версій ffmpeg/libvpx/openh264 свого релізу. Файли `qgroundcontrol-bastion_<версія>_ubuntu<реліз>_amd64.deb`, артефакти `qgroundcontrol-bastion-ubuntu<реліз>`; AppImage (з 22.04, працює на більшості дистрибутивів) — артефакт `qgroundcontrol-bastion-appimage`. Ставте `.deb` саме для своєї версії Ubuntu (`lsb_release -rs`);
- **Android .apk** — Docker-образ `android`, потім `deploy/android/sign-apk.sh` вирівнює й підписує APK; артефакт `qgroundcontrol-bastion-android` (`QGroundControl-Bastion.apk`, пакет `org.mavlink.qgroundcontrol.bastion`);
- **Windows .msi** — Qt MSVC, GStreamer, WiX 5, пресет `Windows-msi`; артефакт `qgroundcontrol-bastion-windows`;
- **GitHub release** — для тегів `vX.Y.Z…` публікує всі пакети як реліз.

Запускається: кнопкою **Run workflow** на вкладці Actions, пушем у `feat/multi-camera` (крім змін лише в документації) і тегом:

```bash
git tag v5.2.1 && git push fork v5.2.1
```

Артефакти зберігаються 30 днів: Actions → запуск → **Artifacts**.
Workflow офіційного QGC у форку запускаються лише для `master`, тегів `vX.Y.Z` і pull request'ів, тож пуші у `feat/multi-camera` їх не чіпають.
Форк створюється без тегів, тому workflow підтягує теги `v*` з `mavlink/qgroundcontrol` — інакше версія пакета була б `0.0.0` і пакування б відмовило.

### Підпис Android

Без налаштувань APK підписується одноразовим ключем: він встановлюється, але наступна збірка (з іншим ключем) не оновить його поверх — доведеться видаляти. Для постійного ключа:

```bash
keytool -genkeypair -keystore bastion.jks -alias bastion -keyalg RSA -keysize 3072 -validity 10000
base64 -w0 bastion.jks   # вміст -> секрет BASTION_ANDROID_KEYSTORE
```

Секрети репозиторію (**Settings → Secrets and variables → Actions → Secrets**): `BASTION_ANDROID_KEYSTORE`, `BASTION_ANDROID_KEYSTORE_PASSWORD`, `BASTION_ANDROID_KEY_ALIAS` (`bastion`). Сам `bastion.jks` зберігайте поза репозиторієм: без нього оновлення встановлених APK неможливі.

## 5. Збірка на власних машинах (self-hosted runners)

За замовчуванням збирають сервери GitHub. Щоб збирати на своєму ноутбуці, зареєструйте раннери й задайте змінні репозиторію (**Settings → Secrets and variables → Actions → Variables**):

| Змінна | Значення | Що збирає | Де |
| ------ | -------- | --------- | -- |
| `BASTION_LINUX_RUNNER` | `bastion-linux` | `.deb`, AppImage, `.apk` | Ubuntu з Docker |
| `BASTION_WINDOWS_RUNNER` | `bastion-windows` | `.msi` | Windows (VM) |

Видаліть змінну — збірка повернеться на сервери GitHub. На self-hosted раннерах кроки звільнення диска пропускаються, а кеші (`.ccache`, `.cache/CPM`, Docker-образи) зберігаються між запусками, тож повторні збірки йдуть за хвилини.

**Linux-раннер (без VM, прямо на Ubuntu):**

1. GitHub → **Settings → Actions → Runners → New self-hosted runner → Linux x64** — виконати показані команди від окремого користувача, до `./config.sh` додати `--labels bastion-linux`.
2. `sudo usermod -aG docker <користувач-раннера>`
3. `sudo ./svc.sh install <користувач-раннера> && sudo ./svc.sh start`

**Windows-раннер (VM на KVM):**

1. `sudo apt install qemu-kvm libvirt-daemon-system virt-manager` і `sudo usermod -aG libvirt,kvm $USER`.
2. ISO: Windows Server 2022 Evaluation (180 днів) або Windows 11 + драйвери virtio-win.
3. virt-manager: 6 vCPU, 10–12 ГБ RAM, диск 150 ГБ (qcow2, virtio), CPU `host-passthrough`.
4. У VM встановити Git, Python 3.12, [uv](https://docs.astral.sh/uv/) (`winget install --id astral-sh.uv -e`), .NET SDK 8 і Visual Studio 2022 Build Tools (`python tools\setup\install_dependencies --platform windows --msvc` з клону форку). Qt, CMake і WiX workflow ставить сам.
5. Раннер: **New self-hosted runner → Windows x64**, `--labels bastion-windows`, встановити як службу.

**Безпека:** репозиторій публічний — ніколи не направляйте на self-hosted раннери workflow з подією `pull_request`, бо чужий PR виконає код на вашій машині. `packages.yml` запускається лише вашими пушами, тегами й вручну. Додатково: **Settings → Actions → General → Require approval for all external contributors**.

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
