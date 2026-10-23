# QGroundControl-Bastion: зміни відносно QGroundControl

Форк базується на `mavlink/qgroundcontrol` (ревізія `fba7dfc`, 22.10.2026) і додає:

1. **Мультикамера** — одночасний показ кількох відеопотоків: кілька камер на одному дроні, кілька дронів, або все разом.
2. **Пакування** — MSI-інсталятор для Windows і Docker-образ для його збірки; `.deb` для Ubuntu збирається наявним Linux-образом.
3. **Назва QGroundControl-Bastion** — усі імена й шляхи відрізняються від оригіналу, тож обидві версії можна встановити одночасно.
4. **GitLab CI** — автоматична збірка `.deb`, `.apk` і `.msi` на власних раннерах (ноутбук і Windows VM), релізи для тегів.

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
| `feat(FlyView): show the map and every camera as blocks` | Карта й усі камери, крім розгорнутої, — блоки однакового розміру |
| `ci: move package builds to GitLab CI` | `.gitlab-ci.yml`, скрипти `deploy/ci`, без GitHub Actions |

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

- на весь екран — вибрана камера **або** карта;
- у лівому нижньому куті — блок PiP (карта, коли на весь екран камера, або вибрана камера, коли на весь екран карта), а праворуч від нього — по блоку такого самого розміру на кожну іншу камеру. Тож карта й усі камери завжди видимі;
- **клік по блоку камери** — ця камера на весь екран (якщо на весь екран була карта, вона переходить у блок PiP); потоки не перезапускаються;
- **клік по блоку PiP з картою** — карта на весь екран;
- розмір блоків змінюється ручкою блоку PiP; при багатьох камерах ряд стискається;
- **подвійний клік по камері на весь екран** — повноекранний режим;
- назва камери — у правому нижньому куті і камери на весь екран, і кожного блоку;
- **червоне коло** поруч із назвою — запис цього потоку (окремий файл), **іконка камери** — фото з кадру;
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
| `src/FlyView/MultiCameraView.qml` | Плитка на кожен потік: вибрана заповнює відеоелемент (на весь екран або в PiP), решта переноситься в ряд блоків; назва, кнопки запису/фото |
| `src/FlyView/FlyView.qml` (`cameraStrip`) | Ряд блоків камер праворуч від PiP того самого розміру; область PiP + ряду передається шару віджетів, щоб він їх не перекривав |
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

У CI `.deb` робиться з AppImage (див. [Пайплайн](#пайплайн-gitlab-ciyml)); локально те саме:

```bash
python3 deploy/ci/deb_from_appimage.py QGroundControl-Bastion-*-x86_64.AppImage build-deb "$(deploy/ci/version.sh)"
```

Нативний `.deb` під конкретний реліз Ubuntu збирає Linux-образ поруч з AppImage:

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

## 4. Репозиторій і CI в GitLab

Основний репозиторій — self-hosted GitLab (`https://basta.zar.in.ua/bastion/qgroundcontrol-bastion`, у локальній мережі й ззовні).

Гілки: `main` — чистий upstream QGroundControl, доки зміни форку не завершено; `feat/multi-camera` — уся робота форку (мультикамера, пакування Bastion, GitLab CI), пайплайни збирають її; `upstream-master` — копія `master` з `mavlink/qgroundcontrol`. GitHub-форк `sanyazar/qgroundcontrol` більше не оновлюється.

### Перенос репозиторію (один раз)

1. У GitLab: **New project → Create blank project**, назва `qgroundcontrol-bastion`, **без** README («Initialize repository with a README» вимкнено).
2. На ноутбуці, у клоні з гілкою `feat/multi-camera`:

   ```bash
   cd ~/qgs/src/qgroundcontrol
   git fetch fork && git checkout feat/multi-camera && git pull --ff-only fork feat/multi-camera
   git remote add gitlab http://<адреса-gitlab>/<група>/qgroundcontrol-bastion.git
   git push gitlab feat/multi-camera           # робоча гілка з усіма змінами
   git push gitlab master:main                 # main = чистий upstream
   git push gitlab --tags                      # теги версій upstream: потрібні для номера версії пакетів
   git push gitlab master:upstream-master      # оригінальний QGC — для майбутніх оновлень
   git branch -u gitlab/feat/multi-camera      # далі git pull/push іде в GitLab
   ```

   Якщо HTTP-пуш великого репозиторію обривається: `git config http.postBuffer 524288000` і повторити (або SSH-адреса).
3. У GitLab: **Settings → Repository → Branch defaults** — default branch `main`.

### Пайплайн `.gitlab-ci.yml`

Етапи: спершу паралельно `appimage`, `apk` і `msi` (кожен — окремий артефакт); коли AppImage готовий, `deb` перепаковує його в `.deb` без повторної збірки (1–2 хв). Нативні `.deb` під конкретний реліз Ubuntu — ручні jobs `deb-native`.

| Job | Етап | Раннер | Результат (артефакти, 30 днів) |
| --- | ---- | ------ | ------------------------------ |
| `appimage` | build | `bastion-linux` | `QGroundControl-Bastion-<версія>-x86_64.AppImage` + `.sha256` (зібрано на Ubuntu 22.04) |
| `apk` | build | `bastion-linux` | `QGroundControl-Bastion-<версія>.apk` (підписаний) + `.sha256` |
| `msi` | build | `bastion-windows` | `QGroundControl-Bastion-<версія QGC>-AMD64.msi` + `.sha256` |
| `deb` | packages | `bastion-linux` | `qgroundcontrol-bastion_<версія>_amd64.deb` + `.sha256` — один пакет для Ubuntu 22.04, 24.04 і 26.04 |
| `deb-native: [ubuntu-2204, 22.04]` / `[ubuntu, 24.04]` / `[ubuntu-2604, 26.04]` (вручну ▶) | packages | `bastion-linux` | `qgroundcontrol-bastion_<версія>_ubuntu<реліз>_amd64.deb` + `.sha256` |
| `release` (лише для тегів `bastion-vX.Y.Z`) | release | `bastion-linux` | Пакети в **Deploy → Package registry** і реліз у **Deploy → Releases** |

**`deb` з AppImage** (`deploy/ci/deb_from_appimage.py`): вміст AppImage (Qt, GStreamer з плагінами, кодеки) розпаковується в `/opt/QGroundControl-Bastion` і запускається через його `AppRun`; `/usr/bin/QGroundControl-Bastion`, ярлик меню, іконки й metainfo — у стандартних місцях. Залежності — лише бібліотеки, які AppImage свідомо бере з системи (glibc, драйвери GL/EGL, X11/XCB, шрифти); їхні назви однакові в 22.04–26.04 (для перейменованих у 24.04 — альтернативи `libasound2 | libasound2t64`). Якщо AppImage почне вимагати нову системну бібліотеку, job впаде з її назвою — додайте її в таблицю `REQUIRED`/`OPTIONAL` у скрипті.

**`deb-native`** компілюється в Docker-образі вибраного релізу й використовує системні ffmpeg/GStreamer — менший пакет, але лише для свого релізу. Запуск: **Build → Pipelines →** пайплайн **→** кнопка ▶ біля потрібного `deb-native`. Jobs не чекають на інші етапи й не блокують пайплайн.

Linux-jobs ідуть паралельно, тому кожен Linux-раннер має мати власний том для dind (`/var/lib/docker`).

Запускається пушем, що змінює код/збірку (зміни лише в документації не запускають), кнопкою **Build → Pipelines → Run pipeline** і тегом релізу форку (див. [Версії](#версії)).

### Версії

Версію рахує `deploy/ci/version.sh`:

```text
<версія QGC>+bastion<версія форку>[~<гілка>]-<номер пайплайна>
5.2.0~dev+bastion0.1.0~feat-multi-camera-57     збірка з робочої гілки
5.2.0~dev+bastion0.1.0-58                       реліз bastion-v0.1.0
5.2.1+bastion0.2.0-73                           після оновлення з upstream 5.2.1 і релізу форку 0.2.0
```

| Частина | Звідки | Коли змінюється |
| ------- | ------ | --------------- |
| версія QGC | найближчий тег upstream `vX.Y.Z[-dev]` (`git describe`); `-dev` → `~dev`, тож знімок розробки старший за попередній реліз, але молодший за `X.Y.Z` | при оновленні з upstream |
| версія форку | файл `BASTION_VERSION` (semver) | вручну: MAJOR — несумісні зміни (налаштування, формат), MINOR — нові можливості, PATCH — виправлення |
| `~<гілка>` | `CI_COMMIT_REF_SLUG`, лише для гілок, крім гілки за замовчуванням, і не для тегів | `~` сортується раніше, тож реліз тієї самої версії завжди новіший за збірки з гілки |
| номер пайплайна | `CI_PIPELINE_IID` — ревізія Debian | кожен пайплайн, тож `apt` завжди бачить новішу збірку |

Порядок для `apt`/`dpkg`: спершу версія QGC, потім версія форку, потім гілка, потім пайплайн. Номер коміту й пайплайна є в описі пакета з AppImage (`apt show qgroundcontrol-bastion`). Та сама версія в назвах AppImage і APK; MSI лишає числову версію QGC, бо Windows Installer приймає лише `X.Y.Z` з малими числами.

Реліз форку: підняти `BASTION_VERSION`, закомітити й поставити тег `bastion-v<та сама версія>` (теги `vX.Y.Z` — це теги оригінального QGC):

```bash
echo 0.2.0 > BASTION_VERSION && git commit -am "chore: release 0.2.0"
git tag bastion-v0.2.0 && git push gitlab HEAD bastion-v0.2.0
```

Job `release` перевіряє, що тег і `BASTION_VERSION` збігаються.

Скрипти: `deploy/ci/version.sh` (версія), `deploy/ci/deb_from_appimage.py` (`.deb` з AppImage), `deploy/ci/finalize-deb.sh` (перевірка, версія й назва нативного `.deb`), `deploy/ci/sign-apk-docker.sh` (підпис APK у Docker-образі), `deploy/ci/build-msi.ps1` (Qt, WiX, MSVC, збірка MSI), `deploy/ci/publish-release.sh` (реліз через API GitLab).
Linux-збірки йдуть у тих самих Docker-образах, що й локально; кеші (`.ccache`, `.cache/CPM`), Python-середовище й папка збірки MSI зберігаються між запусками.
Версія пакета береться з `git describe`; якщо теги не запушено, CI підтягує теги `v*` з `mavlink/qgroundcontrol`.

### Раннери

**Linux (ноутбук)**, Docker executor з Docker-in-Docker. Jobs працюють в образі `docker:29.1.4` і збирають Docker-образи з `deploy/docker` у власному сервісі `docker:29.1.4-dind`. Тека `/builds` спільна для job і сервісу, тому bind-mount з `run_docker.py` працює.

У GitLab: **Admin → CI/CD → Runners → New instance runner**: Tags `bastion-linux`, «Run untagged jobs» вимкнено → **Create runner**, скопіювати токен `glrt-…`. Раннер у контейнері (`gitlab/gitlab-runner`) або встановлений пакетом:

```bash
sudo gitlab-runner register --non-interactive --url http://<адреса-gitlab> \
    --token glrt-XXXX --executor docker --docker-image alpine:3.22 \
    --docker-privileged --description bastion-linux
```

Потрібно в `config.toml` раннера:

```toml
concurrent = 1                      # на реєстрацію; паралельність — кількома раннерами з окремими томами

[[runners]]
  [runners.docker]
    privileged = true               # для docker:dind
    # Кеш образів dind між jobs: без нього кожен job наново збирає образ (Qt, SDK).
    # Окремий том для кожного раннера: два dind не можуть працювати з одним томом.
    volumes = ["/cache", "bastion-dind:/var/lib/docker"]
```

Після змін: `docker restart <контейнер-раннера>` або `sudo gitlab-runner restart`. AppImage пакується без FUSE (`QGC_DOCKER_FUSE=0`). Старий GitHub-раннер можна прибрати: `cd ~/actions-runner && sudo ./svc.sh stop && sudo ./svc.sh uninstall`.

**Windows (VM)**, shell executor, PowerShell (адміністратор):

1. Інструменти, якщо ще не встановлені: Git, .NET SDK 8, VS 2022 Build Tools (`python tools\setup\install_dependencies --platform windows --msvc` з клону репозиторію).
2. Раннер:

   ```powershell
   New-Item -ItemType Directory C:\GitLab-Runner | Out-Null
   Invoke-WebRequest https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-windows-amd64.exe `
       -OutFile C:\GitLab-Runner\gitlab-runner.exe
   cd C:\GitLab-Runner
   .\gitlab-runner.exe register --non-interactive --url http://<адреса-gitlab> --token glrt-YYYY `
       --executor shell --shell powershell --builds-dir C:\b --description bastion-windows
   .\gitlab-runner.exe install --user .\builder --password '<пароль builder>'
   .\gitlab-runner.exe start
   ```

   Токен — з **New project runner** з тегом `bastion-windows`. Короткий `--builds-dir C:\b` потрібен, бо шляхи Qt перевищують ліміт Windows. `build-msi.ps1` сам знаходить uv або встановлює його в `C:\ci-tools\uv`, а Python 3.12 завантажує через uv, тож службі вистачає встановлених для всіх користувачів Git, .NET і Build Tools.

### Підпис Android

Без налаштувань APK підписується одноразовим ключем: він встановлюється, але наступна збірка (з іншим ключем) не оновить його поверх — доведеться видаляти. Для постійного ключа:

```bash
keytool -genkeypair -keystore bastion.jks -alias bastion -keyalg RSA -keysize 3072 -validity 10000
base64 -w0 bastion.jks   # вміст -> змінна BASTION_ANDROID_KEYSTORE
```

Змінні проєкту (**Settings → CI/CD → Variables**, Masked): `BASTION_ANDROID_KEYSTORE`, `BASTION_ANDROID_KEYSTORE_PASSWORD`, `BASTION_ANDROID_KEY_ALIAS` (`bastion`). Сам `bastion.jks` зберігайте поза репозиторієм: без нього оновлення встановлених APK неможливі.

## Перевірка

```bash
just build
ctest -R MultiCameraManagerTest --output-on-failure
just lint
```

Ручна перевірка мультикамери без заліза — два SITL-дрони й тестові потоки GStreamer, див. розділ **Testing Without Hardware** у [Multiple Cameras](docs/en/qgc-user-guide/fly_view/multi_camera.md#testing-without-hardware).

## Оновлення з upstream

```bash
git remote add upstream https://github.com/mavlink/qgroundcontrol.git   # один раз
git fetch upstream --tags
git checkout feat/multi-camera
git rebase upstream/master   # конфлікти найімовірніші у VideoManager.cc, FlyViewVideo.qml, FlyView.qml, Video.SettingsUI.json
git push --force-with-lease gitlab feat/multi-camera
git push gitlab upstream/master:upstream-master upstream/master:main --tags
```
